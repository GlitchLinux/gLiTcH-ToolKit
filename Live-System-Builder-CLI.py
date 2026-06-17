#!/usr/bin/env python3
"""
Glitch Linux Live System Builder - CLI Edition
================================================
A terminal utility that builds a complete, bootable live ISO from a
running Linux system - in one fully automated pipeline.

Pipeline:
  1. Rsync the running system into a clean remastered snapshot
  2. Fix systemd, fstab, hostname and initramfs for live-boot
  3. Compress everything into filesystem.squashfs (xz)
  4. Download hybrid BIOS+EFI bootfiles (ISOLINUX -> GRUB2 chainload)
  5. Generate GRUB2 config with persistence/toram/encryption entries
  6. Build a hybrid ISO with xorriso (dd-able to USB)

Output: <workdir>/<distro-name>.iso  (BIOS + EFI bootable)

Requirements: xorriso, wget, rsync, squashfs-tools, live-boot
Run as root: sudo python3 Live-System-Builder-CLI.py
"""

import sys
import os
import re
import subprocess
import shutil
import time
import argparse
import signal
from pathlib import Path

# ---------------------------------------------------------------
# ANSI COLORS
# ---------------------------------------------------------------
class C:
    RESET   = "\033[0m"
    BOLD    = "\033[1m"
    RED     = "\033[91m"
    GREEN   = "\033[92m"
    YELLOW  = "\033[93m"
    BLUE    = "\033[94m"
    CYAN    = "\033[96m"
    DIM     = "\033[2m"

# ---------------------------------------------------------------
# EMBEDDED ISO BUILDER SCRIPT
# ---------------------------------------------------------------
ISO_BUILDER_SCRIPT = r"""#!/bin/bash
# Embedded ISO builder - called automatically after squashfs creation
# Args: $1=parent_dir  $2=iso_name  $3=system_name  $4=volume_name  $5=output_file

set -e

parent_dir="$1"
iso_name="$2"
system_name="$3"
volume_name="$4"
output_file="$5"

# -- Dependency check --
for cmd in xorriso wget lzma tar; do
    if ! command -v "$cmd" &>/dev/null; then
        if command -v apt-get &>/dev/null; then
            apt-get install -y -qq xorriso wget lzma 2>/dev/null || true
        fi
    fi
done

# -- Detect live system type --
if [ -d "$parent_dir/live" ]; then
    live_dir="live"
    live_path="$parent_dir/live"
elif [ -d "$parent_dir/casper" ]; then
    live_dir="casper"
    live_path="$parent_dir/casper"
else
    echo "ERROR: No live/ or casper/ directory found in $parent_dir" >&2
    exit 1
fi

# -- Find kernel/initrd --
vmlinuz=""
initrd=""
for file in "$live_path"/vmlinuz*; do
    [ -f "$file" ] && vmlinuz=$(basename "$file") && break
done
for file in "$live_path"/initrd* "$live_path"/initramfs*; do
    [ -f "$file" ] && initrd=$(basename "$file") && break
done

if [ -z "$vmlinuz" ] || [ -z "$initrd" ]; then
    echo "ERROR: Missing vmlinuz or initrd in $live_path" >&2
    ls -la "$live_path" >&2
    exit 1
fi

echo "DETECTED: live_dir=$live_dir vmlinuz=$vmlinuz initrd=$initrd"

# -- Working dir --
work_dir="/tmp/iso_build"
rm -rf "$work_dir"
mkdir -p "$work_dir"

echo "STEP: Copying system files to work dir..."
cp -r "$parent_dir"/* "$work_dir/"

# -- Download bootfiles --
echo "STEP: Downloading hybrid bootfiles..."
temp_dl="/tmp/bootfiles_dl_$$"
mkdir -p "$temp_dl"
wget --quiet \
    "https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/ISO-Hybrid-Base-2.tar.lzma" \
    -O "$temp_dl/bootfiles.tar.lzma"
echo "STEP: Extracting bootfiles..."
unlzma "$temp_dl/bootfiles.tar.lzma" 2>/dev/null || lzma -d "$temp_dl/bootfiles.tar.lzma" 2>/dev/null || true
tar -xf "$temp_dl/bootfiles.tar" -C "$work_dir" --strip-components=1 2>/dev/null || true
rm -rf "$temp_dl"
chmod -R 755 "$work_dir" 2>/dev/null || true

# -- Copy splash --
mkdir -p "$work_dir/boot/grub"
if [ -f "/boot/grub/themes/splash.png" ]; then
    cp "/boot/grub/themes/splash.png" "$work_dir/boot/grub/splash.png" 2>/dev/null || true
fi

# -- GRUB theme --
cat > "$work_dir/boot/grub/theme.cfg" <<'THEME_EOF'
title-text: ""
title-font: "Sans Bold 28"
title-color: "#FFFFFF"
desktop-color: "#111111"
desktop-image: "/boot/grub/splash.png"
message-font: "Sans Regular 20"
message-color: "#FFFFFF"
message-bg-color: "#303030"
terminal-font: "Sans Regular 20"

+ boot_menu {
  left = 10%
  top = 20%
  width = 70%
  height = 80%
  item_font = "DejaVu Sans Bold 14"
  item_color = "grey"
  item_height = 32
  item_icon_space = 8
  item_spacing = 2
  selected_item_font = "DejaVu Sans Bold 14"
  selected_item_color= "#ffffff"
  icon_height = 32
  icon_width = 32
  scrollbar = false
  scrollbar_width = 20
}

+ progress_bar {
  id = "__timeout__"
  left = 15%
  top = 85%
  height = 5
  width = 70%
  fg_color = "grey"
  bg_color = "#303030"
  border_color = "#303030"
}
THEME_EOF

# -- GRUB config --
cat > "$work_dir/boot/grub/grub.cfg" <<GRUB_EOF
if loadfont \$prefix/fonts/font.pf2 ; then
  set gfxmode=800x600
  set gfxpayload=keep
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod gfxterm
  insmod png
  terminal_output gfxterm
fi

if background_image "/boot/grub/splash.png"; then
  set color_normal=light-gray/black
  set color_highlight=white/black
elif background_image "/splash.png"; then
  set color_normal=light-gray/black
  set color_highlight=white/black
else
  set menu_color_normal=cyan/blue
  set menu_color_highlight=white/blue
fi

if [ -s \$prefix/theme.cfg ]; then
  set theme=\$prefix/theme.cfg
fi

set default=0
set timeout=10

GRUB_EOF

if [ "$live_dir" = "casper" ]; then
cat >> "$work_dir/boot/grub/grub.cfg" <<GRUB_EOF
menuentry "${system_name} - Live" {
    linux /casper/${vmlinuz} boot=casper quiet splash
    initrd /casper/${initrd}
}
menuentry "${system_name} - Boot to RAM" {
    linux /casper/${vmlinuz} boot=casper quiet splash toram
    initrd /casper/${initrd}
}
menuentry "${system_name} - Encrypted Persistence" {
    linux /casper/${vmlinuz} boot=casper components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /casper/${initrd}
}
GRUB_EOF
else
cat >> "$work_dir/boot/grub/grub.cfg" <<GRUB_EOF
menuentry "${system_name} - Live" {
    linux /live/${vmlinuz} boot=live config quiet splash
    initrd /live/${initrd}
}
menuentry "${system_name} - Boot to RAM" {
    linux /live/${vmlinuz} boot=live config quiet splash toram
    initrd /live/${initrd}
}
menuentry "${system_name} - Encrypted Persistence" {
    linux /live/${vmlinuz} boot=live components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/${initrd}
}
menuentry "${system_name} - Unencrypted Persistence" {
    linux /live/${vmlinuz} boot=live components quiet splash persistence
    initrd /live/${initrd}
}
GRUB_EOF
fi

# -- ISOLINUX config (chainloads GRUB2) --
cat > "$work_dir/isolinux/isolinux.cfg" <<'ISO_EOF'
default grub2_chainload
timeout 1
prompt 0

label grub2_chainload
  linux /boot/grub/lnxboot.img
  initrd /boot/grub/core.img
ISO_EOF

# -- autorun.inf --
cat > "$work_dir/autorun.inf" <<AUTORUN_EOF
[Autorun]
icon=iso.ico
label=${system_name}
AUTORUN_EOF

# -- Build ISO with xorriso --
echo "STEP: Building ISO with xorriso..."
mbr_file="$work_dir/isolinux/isohdpfx.bin"
[ ! -f "$mbr_file" ] && mbr_file="/usr/lib/ISOLINUX/isohdpfx.bin"

xorriso -as mkisofs \
    -iso-level 3 \
    -volid "$volume_name" \
    -full-iso9660-filenames \
    -R -J -joliet-long \
    -isohybrid-mbr "$mbr_file" \
    -b isolinux/isolinux.bin \
    -c isolinux/boot.cat \
    -no-emul-boot \
    -boot-load-size 4 \
    -boot-info-table \
    -eltorito-alt-boot \
    -e boot/grub/efi.img \
    -no-emul-boot \
    -isohybrid-gpt-basdat \
    -append_partition 2 0xEF "$work_dir/boot/grub/efi.img" \
    -o "$output_file" \
    "$work_dir" 2>&1

EXIT_CODE=$?
rm -rf "$work_dir"

if [ $EXIT_CODE -eq 0 ]; then
    size=$(du -h "$output_file" 2>/dev/null | cut -f1)
    echo "ISO_SUCCESS: $output_file ($size)"
    exit 0
else
    echo "ISO_FAILED: xorriso exited with code $EXIT_CODE" >&2
    exit 1
fi
"""


# ---------------------------------------------------------------
# GLOBAL CANCEL FLAG
# ---------------------------------------------------------------
_cancelled = False

def _signal_handler(sig, frame):
    global _cancelled
    _cancelled = True
    print(f"\n{C.YELLOW}[!] Interrupt received, cancelling...{C.RESET}")

signal.signal(signal.SIGINT, _signal_handler)
signal.signal(signal.SIGTERM, _signal_handler)


# ---------------------------------------------------------------
# UTILITY FUNCTIONS
# ---------------------------------------------------------------
def log_info(msg):
    print(f"{C.DIM}[INFO]{C.RESET}  {msg}")

def log_ok(msg):
    print(f"{C.GREEN}[ OK ]{C.RESET}  {msg}")

def log_warn(msg):
    print(f"{C.YELLOW}[WARN]{C.RESET}  {msg}")

def log_err(msg):
    print(f"{C.RED}[ ERR]{C.RESET}  {msg}")

def log_step(step, total, msg):
    bar = f"{C.CYAN}{C.BOLD}[{step}/{total}]{C.RESET}"
    print(f"\n{bar} {C.BOLD}{msg}{C.RESET}")

def log_progress(msg):
    print(f"{C.BLUE}[...]{C.RESET}  {msg}")


def run_cmd(cmd, shell=True, timeout=600):
    """Run a command and return (returncode, stdout, stderr)."""
    try:
        result = subprocess.run(
            cmd, shell=shell, capture_output=True, text=True,
            timeout=timeout
        )
        return result.returncode, result.stdout.strip(), result.stderr.strip()
    except subprocess.TimeoutExpired:
        return -1, "", "Command timed out"
    except Exception as e:
        return -1, "", str(e)


def human_size(size_bytes):
    """Convert bytes to human-readable size."""
    if size_bytes is None:
        return "Unknown"
    for unit in ['B', 'KB', 'MB', 'GB', 'TB']:
        if abs(size_bytes) < 1024.0:
            return f"{size_bytes:.1f} {unit}"
        size_bytes /= 1024.0
    return f"{size_bytes:.1f} PB"


def get_current_hostname():
    rc, out, _ = run_cmd("hostname")
    if rc == 0 and out:
        return out.strip()
    return "live-system"


def get_disk_free(path):
    try:
        st = os.statvfs(path)
        return st.f_bavail * st.f_frsize
    except Exception:
        return 0


def get_root_used():
    rc, out, _ = run_cmd("df -B1 / | tail -1 | awk '{print $3}'")
    if rc == 0 and out:
        try:
            return int(out)
        except ValueError:
            pass
    return 0


def get_current_username():
    """Get the primary non-root user (UID >= 1000)."""
    try:
        with open("/etc/passwd") as f:
            for line in f:
                parts = line.strip().split(":")
                if len(parts) >= 7:
                    uid = int(parts[2])
                    shell = parts[6]
                    if 1000 <= uid < 60000 and "/nologin" not in shell and "/false" not in shell:
                        return parts[0]
    except Exception:
        pass
    return None


def get_writable_mountpoints():
    """Get a list of writable mount points suitable for building."""
    candidates = ["/tmp"]
    try:
        with open("/proc/mounts") as f:
            for line in f:
                parts = line.split()
                if len(parts) < 3:
                    continue
                dev, mnt, fstype = parts[0], parts[1], parts[2]
                if fstype in ("proc", "sysfs", "devtmpfs", "tmpfs", "cgroup", "cgroup2",
                              "securityfs", "devpts", "pstore", "debugfs", "tracefs",
                              "configfs", "fusectl", "hugetlbfs", "mqueue", "binfmt_misc",
                              "autofs", "efivarfs", "fuse.gvfsd-fuse", "overlay", "squashfs",
                              "iso9660", "udf"):
                    continue
                if not dev.startswith("/dev/") and not dev.startswith("//") and ":" not in dev:
                    continue
                if mnt == "/":
                    continue
                if mnt.startswith(("/proc", "/sys", "/dev", "/run", "/snap")):
                    continue
                if os.path.isdir(mnt) and os.access(mnt, os.W_OK):
                    candidates.append(mnt)
    except Exception:
        pass

    for extra in ["/mnt", "/home"]:
        if extra not in candidates and os.path.isdir(extra) and os.access(extra, os.W_OK):
            free = get_disk_free(extra)
            if free > 2 * 1024**3:
                candidates.append(extra)

    return candidates


def confirm(prompt):
    """Ask y/n confirmation. Returns True if yes."""
    while True:
        resp = input(f"{C.BOLD}{prompt} [y/N]: {C.RESET}").strip().lower()
        if resp in ("y", "yes"):
            return True
        if resp in ("n", "no", ""):
            return False


def interactive_setup(args):
    """Interactive setup wizard - prompts for build location, hostname, username."""
    print(f"\n{C.BOLD}{'=' * 56}{C.RESET}")
    print(f"{C.BOLD}  Glitch Linux Live System Builder - Setup{C.RESET}")
    print(f"{'=' * 56}\n")

    current_host = get_current_hostname()
    current_user = get_current_username()

    rc, kernel_ver, _ = run_cmd("uname -r")
    kernel = kernel_ver if rc == 0 else "Unknown"
    root_used = get_root_used()
    print(f"  {C.DIM}Hostname: {current_host}  |  Kernel: {kernel}  |  Root: ~{human_size(root_used)}{C.RESET}")
    if current_user:
        print(f"  {C.DIM}Primary user: {current_user}{C.RESET}")
    print()

    # --- 1. Build location ---
    if not args.workdir_set:
        mounts = get_writable_mountpoints()
        print(f"{C.BOLD}  Select build location:{C.RESET}")
        for i, mnt in enumerate(mounts, 1):
            free = get_disk_free(mnt)
            print(f"    {C.CYAN}{i}{C.RESET}) {mnt}  ({human_size(free)} free)")
        print(f"    {C.CYAN}c{C.RESET}) Custom path")
        print()

        while True:
            choice = input(f"  {C.BOLD}Choose [1]: {C.RESET}").strip()
            if choice == "":
                args.workdir = mounts[0]
                break
            elif choice.lower() == "c":
                custom = input(f"  {C.BOLD}Enter path: {C.RESET}").strip()
                if custom and os.path.isdir(custom) and os.access(custom, os.W_OK):
                    args.workdir = custom
                    break
                else:
                    log_err("Invalid or non-writable path. Try again.")
            else:
                try:
                    idx = int(choice)
                    if 1 <= idx <= len(mounts):
                        args.workdir = mounts[idx - 1]
                        break
                except ValueError:
                    pass
                log_err("Invalid selection. Try again.")

        print(f"  {C.GREEN}>{C.RESET} Build location: {args.workdir}\n")

    # --- 2. Distro name ---
    if args.name == "glitch-live":
        resp = input(f"  {C.BOLD}Live OS name [{args.name}]: {C.RESET}").strip()
        if resp:
            args.name = resp
        print(f"  {C.GREEN}>{C.RESET} OS name: {args.name}\n")

    # --- 3. Hostname ---
    if not args.hostname:
        resp = input(f"  {C.BOLD}Change hostname? (enter = keep '{current_host}'): {C.RESET}").strip()
        if resp:
            args.hostname = resp
            print(f"  {C.GREEN}>{C.RESET} Hostname: {args.hostname}\n")
        else:
            args.hostname = current_host
            print(f"  {C.GREEN}>{C.RESET} Hostname: {current_host} (unchanged)\n")

    # --- 4. Username ---
    if not args.username:
        if current_user:
            resp = input(f"  {C.BOLD}Change username? (enter = keep '{current_user}'): {C.RESET}").strip()
            if resp:
                if re.match(r'^[a-z_][a-z0-9_-]*$', resp) and len(resp) <= 32:
                    args.username = resp
                    print(f"  {C.GREEN}>{C.RESET} Username: {current_user} -> {args.username}\n")
                else:
                    log_err("Invalid username (lowercase, a-z 0-9 _ - only). Keeping original.")
                    args.username = None
                    print(f"  {C.GREEN}>{C.RESET} Username: {current_user} (unchanged)\n")
            else:
                print(f"  {C.GREEN}>{C.RESET} Username: {current_user} (unchanged)\n")
        else:
            print(f"  {C.DIM}  No regular user detected, skipping username prompt.{C.RESET}\n")

    print(f"{'=' * 56}\n")
    return args


# ---------------------------------------------------------------
# BUILD LOGIC
# ---------------------------------------------------------------
def check_cancelled():
    if _cancelled:
        log_warn("Cancelled by user.")
        sys.exit(1)


def step_install_deps():
    """Step 1: Check & install dependencies."""
    required_pkgs = [
        "squashfs-tools", "rsync", "live-boot", "live-boot-initramfs-tools",
    ]
    missing = []
    for pkg in required_pkgs:
        rc, _, _ = run_cmd(f"dpkg -s {pkg} 2>/dev/null | grep -q '^Status:.*installed'")
        if rc != 0:
            missing.append(pkg)

    if missing:
        log_warn(f"Missing packages: {', '.join(missing)}")
        log_progress("Installing missing dependencies...")
        run_cmd("apt-get update -qq", timeout=120)
        for pkg in missing:
            check_cancelled()
            rc, _, _ = run_cmd(f"apt-get install -y -qq {pkg}", timeout=180)
            if rc == 0:
                log_ok(f"Installed: {pkg}")
            else:
                log_warn(f"Could not install: {pkg} (may be optional)")
    else:
        log_ok("All dependencies satisfied.")


def step_prepare_dirs(work_dir, distro_name):
    """Step 2: Prepare working directories."""
    remastered = os.path.join(work_dir, "remastered")
    live_dir = os.path.join(work_dir, distro_name, "live")

    if os.path.exists(remastered):
        log_warn(f"Removing existing remastered dir: {remastered}")
        shutil.rmtree(remastered, ignore_errors=True)

    os.makedirs(remastered, exist_ok=True)
    os.makedirs(live_dir, exist_ok=True)
    log_ok(f"Created: {remastered}")
    log_ok(f"Created: {live_dir}")
    return remastered, live_dir


def step_rsync(remastered, work_dir):
    """Step 3: Rsync the running system."""
    excludes = [
        "/dev/*", "/proc/*", "/sys/*", "/tmp/*", "/run/*",
        "/mnt/*", "/media/*", "/live/*", "/lib/live/mount/*",
        "/cdrom/*", "/initrd/*",
        "/var/cache/apt/archives/*", "/var/lib/apt/lists/*",
        "/var/log/*", "/root/.cache", "/root/.thumbnails",
        "/home/x/Desktop/gocryptfs/",
        "/home/*/.cache", "/home/*/.thumbnails",
        "/swap.file", "/swapfile",
        "/usr/lib/live/mount/rootfs/*",
        "/usr/lib/live/mount/medium/*",
        "/usr/lib/live/mount/overlay/*",
    ]
    rel_work = work_dir.lstrip("/")
    if rel_work:
        excludes.append(f"/{rel_work}")

    exclude_args = " ".join([f'--exclude="{e}"' for e in excludes])
    rsync_cmd = f'rsync -aHAXS --numeric-ids --info=progress2 / "{remastered}" {exclude_args}'

    log_progress("Running rsync... (this may take a while)")
    try:
        proc = subprocess.Popen(
            rsync_cmd, shell=True,
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1
        )
        last_pct = -1
        for line in proc.stdout:
            check_cancelled()
            line = line.strip()
            match = re.search(r'(\d+)%', line)
            if match:
                pct = int(match.group(1))
                if pct != last_pct and pct % 5 == 0:
                    last_pct = pct
                    print(f"\r{C.BLUE}[...]{C.RESET}  rsync: {pct}%", end="", flush=True)
        print()  # newline after progress
        proc.wait()
        if proc.returncode != 0:
            log_warn(f"rsync exited with code {proc.returncode} (some warnings are normal)")
    except Exception as e:
        log_err(f"rsync error: {e}")
        sys.exit(1)

    log_ok("System rsync complete.")

    # Create essential empty directories
    for d in ["dev", "proc", "sys", "tmp", "run", "mnt", "media"]:
        os.makedirs(os.path.join(remastered, d), exist_ok=True)


def step_fix_systemd(remastered, hostname):
    """Step 4: Fix systemd / live boot config."""
    log_progress("Preparing live-boot filesystem configuration...")

    for d in ["dev", "proc", "sys", "run/systemd", "var/lib/systemd",
               "etc/systemd/system", "etc/live", "etc/live/boot"]:
        os.makedirs(os.path.join(remastered, d), exist_ok=True)

    # Empty fstab
    fstab_path = os.path.join(remastered, "etc", "fstab")
    fstab_orig = os.path.join(remastered, "etc", "fstab.orig")
    if os.path.exists(fstab_path):
        shutil.copy2(fstab_path, fstab_orig)
    with open(fstab_path, 'w') as f:
        f.write("")
    log_ok("fstab emptied (live-boot manages mounts).")

    # Hostname
    with open(os.path.join(remastered, "etc", "hostname"), 'w') as f:
        f.write(hostname + '\n')

    with open(os.path.join(remastered, "etc", "hosts"), 'w') as f:
        f.write(f"127.0.0.1\tlocalhost\n")
        f.write(f"127.0.1.1\t{hostname}\n")
        f.write(f"::1\t\tlocalhost ip6-localhost ip6-loopback\n")
        f.write(f"ff02::1\t\tip6-allnodes\n")
        f.write(f"ff02::2\t\tip6-allrouters\n")
    log_ok(f"Hostname set to: {hostname}")

    # machine-id
    machine_id_path = os.path.join(remastered, "etc", "machine-id")
    if not os.path.exists(machine_id_path):
        rc, _, _ = run_cmd(f'systemd-machine-id-setup --root="{remastered}"')
        if rc != 0:
            rc2, uuid_out, _ = run_cmd("cat /proc/sys/kernel/random/uuid")
            if rc2 == 0:
                with open(machine_id_path, 'w') as f:
                    f.write(uuid_out.replace('-', '') + '\n')

    # RESUME=none
    resume_dir = os.path.join(remastered, "etc", "initramfs-tools", "conf.d")
    os.makedirs(resume_dir, exist_ok=True)
    with open(os.path.join(resume_dir, "resume"), 'w') as f:
        f.write("RESUME=none\n")
    log_ok("Set RESUME=none in initramfs config.")

    # resolv.conf
    resolv_path = os.path.join(remastered, "etc", "resolv.conf")
    if os.path.exists(resolv_path) or os.path.islink(resolv_path):
        try:
            os.remove(resolv_path)
        except OSError:
            pass
    with open(resolv_path, 'w') as f:
        f.write("nameserver 8.8.8.8\n")
        f.write("nameserver 8.8.4.4\n")

    log_ok("Filesystem configuration complete.")


def mount_chroot(work):
    """Bind-mount essential filesystems for chroot operations."""
    mounts = [
        ("/proc", os.path.join(work, "proc")),
        ("/sys", os.path.join(work, "sys")),
        ("/dev", os.path.join(work, "dev")),
        ("/dev/pts", os.path.join(work, "dev", "pts")),
    ]
    for src, dst in mounts:
        os.makedirs(dst, exist_ok=True)
        rc, _, _ = run_cmd(f'mountpoint -q "{dst}"')
        if rc != 0:
            run_cmd(f'mount --bind {src} "{dst}"')


def unmount_chroot(work):
    """Unmount chroot filesystems safely."""
    for target in ["dev/pts", "dev", "sys", "proc"]:
        mount_point = os.path.join(work, target)
        rc, _, _ = run_cmd(f'umount "{mount_point}" 2>/dev/null')
        if rc != 0:
            run_cmd(f'umount -l "{mount_point}" 2>/dev/null')


def step_ensure_live_boot(remastered):
    """Step 5: Ensure live-boot packages are functional in chroot."""
    log_progress("Verifying live-boot packages inside remastered system...")

    mount_chroot(remastered)

    critical_files = [
        "usr/bin/live-boot",
        "usr/share/initramfs-tools/hooks/live",
        "usr/share/initramfs-tools/scripts/live",
        "usr/lib/live/boot/9990-main.sh",
    ]

    missing_files = [f for f in critical_files if not os.path.exists(os.path.join(remastered, f))]

    if missing_files:
        log_warn(f"Missing critical live-boot files: {', '.join(missing_files)}")
        log_progress("Reinstalling live-boot packages inside chroot...")

        run_cmd(f'chroot "{remastered}" apt-get update -qq', timeout=120)

        for pkg in ["live-boot", "live-boot-initramfs-tools"]:
            rc, _, err = run_cmd(
                f'chroot "{remastered}" apt-get install --reinstall -y -qq {pkg}',
                timeout=180
            )
            if rc == 0:
                log_ok(f"Reinstalled {pkg} in chroot.")
            else:
                log_warn(f"Failed to reinstall {pkg}: {err}")
                run_cmd(f'chroot "{remastered}" dpkg --configure -a', timeout=60)

        # Verify again
        still_missing = [f for f in critical_files if not os.path.exists(os.path.join(remastered, f))]
        if still_missing:
            log_warn("Attempting to copy live-boot files from host system...")
            for f in still_missing:
                host_path = os.path.join("/", f)
                target_path = os.path.join(remastered, f)
                if os.path.exists(host_path):
                    os.makedirs(os.path.dirname(target_path), exist_ok=True)
                    if os.path.isdir(host_path):
                        shutil.copytree(host_path, target_path, dirs_exist_ok=True)
                    else:
                        shutil.copy2(host_path, target_path)
                    log_ok(f"Copied from host: {f}")
                else:
                    log_err(f"CRITICAL: {f} not found on host either!")
    else:
        log_ok("All critical live-boot files present.")

    run_cmd(f'chroot "{remastered}" dpkg --configure -a', timeout=60)
    log_ok("Live-boot package verification complete.")


def step_cleanup(remastered):
    """Step 6: Clean up remastered system."""
    cleanup_files = [
        "var/lib/alsa/asound.state",
        "root/.bash_history",
        "root/.xsession-errors",
        "root/.xsession-errors.old",
        "etc/blkid-cache",
    ]
    for f in cleanup_files:
        full = os.path.join(remastered, f)
        if os.path.exists(full):
            try:
                os.remove(full)
            except OSError:
                pass

    # Remove persistent udev rules
    udev_dir = os.path.join(remastered, "etc", "udev", "rules.d")
    if os.path.exists(udev_dir):
        for f in os.listdir(udev_dir):
            if f.startswith("70-persistent"):
                try:
                    os.remove(os.path.join(udev_dir, f))
                except OSError:
                    pass

    # Remove DHCP leases
    for pattern_dir in ["var/lib/dhcp", "var/lib/dhcpcd"]:
        full = os.path.join(remastered, pattern_dir)
        if os.path.exists(full):
            for f in os.listdir(full):
                if "lease" in f:
                    try:
                        os.remove(os.path.join(full, f))
                    except OSError:
                        pass

    # Clear temp dirs
    for d in ["var/tmp", "tmp"]:
        full = os.path.join(remastered, d)
        if os.path.exists(full):
            for item in os.listdir(full):
                item_path = os.path.join(full, item)
                try:
                    if os.path.isdir(item_path):
                        shutil.rmtree(item_path)
                    else:
                        os.remove(item_path)
                except OSError:
                    pass

    # Set proper permissions
    tmp_dir = os.path.join(remastered, "tmp")
    if os.path.exists(tmp_dir):
        os.chmod(tmp_dir, 0o1777)
    run_dir = os.path.join(remastered, "run")
    if os.path.exists(run_dir):
        os.chmod(run_dir, 0o755)

    log_ok("Cleanup complete.")


def verify_initrd_has_live(initrd_path, work):
    """Check if initrd contains live-boot scripts."""
    if not os.path.isfile(initrd_path):
        return False

    verify_dir = os.path.join(work, "tmp", "_initrd_verify")
    if os.path.exists(verify_dir):
        shutil.rmtree(verify_dir, ignore_errors=True)
    os.makedirs(verify_dir, exist_ok=True)

    rc, _, _ = run_cmd(f'unmkinitramfs "{initrd_path}" "{verify_dir}" 2>/dev/null', timeout=60)
    if rc != 0:
        shutil.rmtree(verify_dir, ignore_errors=True)
        return False

    found_live = False
    for root_dir, dirs, files in os.walk(verify_dir):
        if "live" in files:
            parent = os.path.basename(root_dir)
            if parent == "scripts":
                found_live = True
                break

    shutil.rmtree(verify_dir, ignore_errors=True)
    return found_live


def step_regenerate_initramfs(remastered):
    """Step 7: Regenerate initramfs with live-boot support."""
    log_progress("Preparing initramfs for live boot...")

    boot_dir = os.path.join(remastered, "boot")
    if not os.path.isdir(boot_dir):
        log_err("CRITICAL: No /boot directory found!")
        unmount_chroot(remastered)
        return

    initrd_files = sorted(
        [f for f in os.listdir(boot_dir) if f.startswith("initrd")],
        reverse=True
    )
    if not initrd_files:
        log_err("CRITICAL: No initrd found in /boot!")
        unmount_chroot(remastered)
        return

    initrd_path = os.path.join(boot_dir, initrd_files[0])
    backup_path = initrd_path + ".pre-squash-backup"

    log_progress(f"Checking rsynced initrd: {initrd_files[0]}...")
    rsynced_has_live = verify_initrd_has_live(initrd_path, remastered)

    if rsynced_has_live:
        log_ok("Rsynced initrd ALREADY contains live-boot scripts.")
    else:
        log_warn("Rsynced initrd does NOT contain live-boot scripts.")

    # Backup regardless
    shutil.copy2(initrd_path, backup_path)

    # Attempt rebuild
    mount_chroot(remastered)

    hook_path = os.path.join(remastered, "usr", "share", "initramfs-tools", "hooks", "live")
    script_path = os.path.join(remastered, "usr", "share", "initramfs-tools", "scripts", "live")

    if not os.path.exists(hook_path) or not os.path.exists(script_path):
        log_warn("Live-boot hooks not found - skipping rebuild, using rsynced initrd.")
        if os.path.exists(backup_path):
            shutil.copy2(backup_path, initrd_path)
        unmount_chroot(remastered)
        return

    log_progress("Live-boot hook and script confirmed present. Rebuilding...")
    rc, out, err = run_cmd(f'chroot "{remastered}" update-initramfs -u -k all', timeout=600)
    if rc != 0:
        log_warn(f"update-initramfs had issues: {err}")

    rebuilt_has_live = verify_initrd_has_live(initrd_path, remastered)

    if rebuilt_has_live:
        log_ok("VERIFIED: Rebuilt initrd contains live-boot scripts.")
        if os.path.exists(backup_path):
            os.remove(backup_path)
    else:
        log_err("Rebuilt initrd LOST live-boot scripts!")
        if rsynced_has_live:
            log_warn("Restoring backed-up rsynced initrd (which had live scripts).")
            shutil.copy2(backup_path, initrd_path)
            os.remove(backup_path)
            log_ok("Original rsynced initrd restored.")
        else:
            log_err("Neither rsynced nor rebuilt initrd has live-boot scripts!")
            log_err("The live system may NOT boot. Ensure live-boot is installed on the source system.")
            if os.path.exists(backup_path):
                os.remove(backup_path)

    unmount_chroot(remastered)


def step_rename_user(remastered, old_user, new_user):
    """Rename a user account inside the remastered chroot.

    Renames:
      - /etc/passwd, /etc/shadow, /etc/group, /etc/gshadow entries
      - Home directory /home/old -> /home/new
      - /etc/sudoers.d/ references
    """
    log_progress(f"Renaming user '{old_user}' -> '{new_user}' in remastered system...")

    passwd_path = os.path.join(remastered, "etc", "passwd")
    shadow_path = os.path.join(remastered, "etc", "shadow")
    group_path  = os.path.join(remastered, "etc", "group")
    gshadow_path = os.path.join(remastered, "etc", "gshadow")

    def sed_replace(filepath, old, new):
        """Replace username at start-of-line in passwd/shadow/group style files."""
        if not os.path.exists(filepath):
            return
        with open(filepath, 'r') as f:
            content = f.read()
        # Replace the username field (first field before colon)
        content = re.sub(
            rf'^{re.escape(old)}:',
            f'{new}:',
            content,
            flags=re.MULTILINE
        )
        # Also replace in group member lists (after last colon)
        content = re.sub(
            rf'([:,]){re.escape(old)}([,\n])',
            rf'\1{new}\2',
            content
        )
        content = re.sub(
            rf'([:,]){re.escape(old)}$',
            rf'\1{new}',
            content,
            flags=re.MULTILINE
        )
        with open(filepath, 'w') as f:
            f.write(content)

    # Update account files
    for fpath in [passwd_path, shadow_path, group_path, gshadow_path]:
        sed_replace(fpath, old_user, new_user)

    # Update home directory path in passwd
    if os.path.exists(passwd_path):
        with open(passwd_path, 'r') as f:
            content = f.read()
        content = content.replace(f'/home/{old_user}', f'/home/{new_user}')
        with open(passwd_path, 'w') as f:
            f.write(content)

    # Rename home directory
    old_home = os.path.join(remastered, "home", old_user)
    new_home = os.path.join(remastered, "home", new_user)
    if os.path.isdir(old_home) and not os.path.exists(new_home):
        os.rename(old_home, new_home)
        log_ok(f"Home directory renamed: /home/{old_user} -> /home/{new_user}")
    elif os.path.isdir(old_home):
        log_warn(f"/home/{new_user} already exists, skipping home rename.")

    # Update sudoers.d if the old user has a sudoers file
    sudoers_dir = os.path.join(remastered, "etc", "sudoers.d")
    if os.path.isdir(sudoers_dir):
        old_sudoer = os.path.join(sudoers_dir, old_user)
        new_sudoer = os.path.join(sudoers_dir, new_user)
        if os.path.isfile(old_sudoer):
            with open(old_sudoer, 'r') as f:
                content = f.read()
            content = content.replace(old_user, new_user)
            with open(new_sudoer, 'w') as f:
                f.write(content)
            os.remove(old_sudoer)
            log_ok(f"Sudoers file renamed: {old_user} -> {new_user}")

    # Update /etc/lightdm, /etc/sddm.conf, /etc/gdm if they reference the user
    for conf in ["etc/lightdm/lightdm.conf", "etc/sddm.conf", "etc/sddm.conf.d/autologin.conf"]:
        conf_path = os.path.join(remastered, conf)
        if os.path.isfile(conf_path):
            with open(conf_path, 'r') as f:
                content = f.read()
            if old_user in content:
                content = content.replace(old_user, new_user)
                with open(conf_path, 'w') as f:
                    f.write(content)
                log_ok(f"Updated user reference in {conf}")

    log_ok(f"User rename complete: {old_user} -> {new_user}")


def step_squashfs(remastered, squashfs_out):
    """Step 8: Create filesystem.squashfs."""
    if os.path.exists(squashfs_out):
        os.remove(squashfs_out)

    mksquashfs_cmd = (
        f'mksquashfs "{remastered}" "{squashfs_out}" '
        f'-comp xz -b 512k -Xbcj x86 -no-progress'
    )

    log_progress("Running mksquashfs... (this will take several minutes)")
    rc, out, err = run_cmd(mksquashfs_cmd, timeout=7200)
    if rc != 0:
        log_err(f"mksquashfs failed: {err}")
        sys.exit(1)

    if not os.path.isfile(squashfs_out):
        log_err("filesystem.squashfs was not created")
        sys.exit(1)

    sq_size = os.path.getsize(squashfs_out)
    log_ok(f"filesystem.squashfs created: {human_size(sq_size)}")
    return sq_size


def step_copy_boot_files(remastered, live_dir):
    """Step 9: Copy vmlinuz and initrd to live/ directory."""
    boot_dir = os.path.join(remastered, "boot")

    if not os.path.isdir(boot_dir):
        log_err("No /boot directory found in remastered system!")
        return

    vmlinuz_files = sorted(
        [f for f in os.listdir(boot_dir) if f.startswith("vmlinuz")],
        reverse=True
    )
    initrd_files = sorted(
        [f for f in os.listdir(boot_dir) if f.startswith("initrd") or f.startswith("initramfs")],
        reverse=True
    )

    if vmlinuz_files:
        src = os.path.join(boot_dir, vmlinuz_files[0])
        dst = os.path.join(live_dir, "vmlinuz")
        shutil.copy2(src, dst)
        log_ok(f"Copied: {vmlinuz_files[0]} -> live/vmlinuz ({human_size(os.path.getsize(dst))})")
    else:
        log_err("No vmlinuz found in /boot!")

    if initrd_files:
        src = os.path.join(boot_dir, initrd_files[0])
        dst_name = "initrd.gz" if initrd_files[0].endswith(".gz") else "initrd.img"
        dst = os.path.join(live_dir, dst_name)
        shutil.copy2(src, dst)
        log_ok(f"Copied: {initrd_files[0]} -> live/{dst_name} ({human_size(os.path.getsize(dst))})")
    else:
        log_err("No initrd found in /boot!")


def step_build_iso(parent_dir, iso_output, system_name, volume_name):
    """Step 10: Build the ISO."""
    script_path = "/tmp/_glitch_iso_builder.sh"
    try:
        with open(script_path, 'w') as f:
            f.write(ISO_BUILDER_SCRIPT)
        os.chmod(script_path, 0o755)
    except Exception as e:
        log_err(f"Failed to write ISO builder script: {e}")
        return None, None

    log_progress(f"Building: {iso_output}")

    try:
        proc = subprocess.Popen(
            ["/bin/bash", script_path,
             parent_dir, os.path.basename(iso_output),
             system_name, volume_name, iso_output],
            stdout=subprocess.PIPE, stderr=subprocess.STDOUT,
            text=True, bufsize=1
        )
        iso_path = None
        iso_size = None
        for line in proc.stdout:
            line = line.strip()
            if not line:
                continue
            if line.startswith("STEP:"):
                log_progress(line[5:].strip())
            elif line.startswith("DETECTED:"):
                log_info(line[9:].strip())
            elif line.startswith("ISO_SUCCESS:"):
                parts = line[12:].strip()
                if " (" in parts:
                    iso_path = parts[:parts.rfind(" (")]
                    iso_size = parts[parts.rfind("(")+1:parts.rfind(")")]
                else:
                    iso_path = parts
                    iso_size = "unknown"
                log_ok(f"ISO created: {iso_path} ({iso_size})")
            elif line.startswith("ISO_FAILED:"):
                log_err(line[11:].strip())
            elif "error" in line.lower() or "failed" in line.lower():
                log_warn(line)
            else:
                log_info(line)

        proc.wait()
        if proc.returncode != 0:
            log_err(f"ISO builder exited with code {proc.returncode}")
            return None, None

        return iso_path, iso_size

    except Exception as e:
        log_err(f"ISO builder exception: {e}")
        return None, None
    finally:
        try:
            os.remove(script_path)
        except OSError:
            pass


# ---------------------------------------------------------------
# MAIN BUILD PIPELINE
# ---------------------------------------------------------------
def build(args):
    work_dir    = args.workdir
    distro_name = args.name
    hostname    = args.hostname or get_current_hostname()
    cleanup     = not args.keep_remastered
    iso_name    = args.iso or f"{distro_name}.iso"
    system_name = args.system_name or distro_name
    volume_name = args.volume or coerce_volume(iso_name)
    new_user    = getattr(args, 'username', None)
    old_user    = get_current_username() if new_user else None

    if not iso_name.lower().endswith(".iso"):
        iso_name += ".iso"

    remastered   = os.path.join(work_dir, "remastered")
    live_dir     = os.path.join(work_dir, distro_name, "live")
    squashfs_out = os.path.join(live_dir, "filesystem.squashfs")
    iso_output   = os.path.join(work_dir, iso_name)

    do_rename = bool(new_user and old_user and new_user != old_user)
    total = 11 if do_rename else 10

    # -- Validate --
    if not os.path.isdir(work_dir):
        log_err(f"Working directory does not exist: {work_dir}")
        sys.exit(1)
    if not os.access(work_dir, os.W_OK):
        log_err(f"Working directory is not writable: {work_dir}")
        sys.exit(1)
    if re.search(r'[^a-zA-Z0-9_\-.]', distro_name):
        log_err("OS name can only contain letters, numbers, hyphens, underscores, and dots.")
        sys.exit(1)
    if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$', hostname):
        log_err("Invalid hostname. Use only letters, numbers, and hyphens.")
        sys.exit(1)

    # -- Summary --
    print(f"\n{C.BOLD}{'=' * 56}{C.RESET}")
    print(f"{C.BOLD}  Glitch Linux Live System Builder - CLI{C.RESET}")
    print(f"{'=' * 56}")
    print(f"  Working directory : {work_dir}")
    print(f"  Live OS name      : {distro_name}")
    print(f"  Hostname          : {hostname}")
    if do_rename:
        print(f"  Username          : {old_user} -> {new_user}")
    print(f"  ISO filename      : {iso_name}")
    print(f"  Boot menu name    : {system_name}")
    print(f"  Volume label      : {volume_name}")
    print(f"  Output ISO        : {iso_output}")
    print(f"  Cleanup remastered: {'Yes' if cleanup else 'No'}")

    free = get_disk_free(work_dir)
    root_used = get_root_used()
    needed = root_used + (root_used // 3)
    print(f"\n  Root used (approx): {human_size(root_used)}")
    print(f"  Free at target    : {human_size(free)}")
    print(f"  Estimated needed  : ~{human_size(needed)}")

    if free < needed:
        log_warn("Free space may be insufficient!")

    print(f"{'=' * 56}\n")

    if not args.yes:
        if not confirm("Proceed with build?"):
            print("Aborted.")
            sys.exit(0)

    # -- Pipeline --
    t0 = time.time()
    s = 0  # step counter

    s += 1
    log_step(s, total, "Checking and installing dependencies...")
    step_install_deps()
    check_cancelled()

    s += 1
    log_step(s, total, "Preparing working directories...")
    remastered, live_dir = step_prepare_dirs(work_dir, distro_name)
    check_cancelled()

    s += 1
    log_step(s, total, "Rsyncing system (this may take a while)...")
    step_rsync(remastered, work_dir)
    check_cancelled()

    s += 1
    log_step(s, total, "Configuring systemd for live boot...")
    step_fix_systemd(remastered, hostname)
    check_cancelled()

    if do_rename:
        s += 1
        log_step(s, total, f"Renaming user '{old_user}' -> '{new_user}'...")
        step_rename_user(remastered, old_user, new_user)
        check_cancelled()

    s += 1
    log_step(s, total, "Ensuring live-boot packages are functional...")
    step_ensure_live_boot(remastered)
    check_cancelled()

    s += 1
    log_step(s, total, "Cleaning up remastered system...")
    step_cleanup(remastered)
    check_cancelled()

    s += 1
    log_step(s, total, "Regenerating initramfs in chroot...")
    step_regenerate_initramfs(remastered)
    check_cancelled()

    s += 1
    log_step(s, total, "Creating filesystem.squashfs...")
    sq_size = step_squashfs(remastered, squashfs_out)
    check_cancelled()

    s += 1
    log_step(s, total, "Copying kernel and initrd to live/ directory...")
    step_copy_boot_files(remastered, live_dir)

    if cleanup:
        log_progress("Cleaning up remastered working directory...")
        shutil.rmtree(remastered, ignore_errors=True)
        log_ok("Remastered directory removed.")
    else:
        log_info(f"Remastered directory preserved at: {remastered}")

    s += 1
    log_step(s, total, "Building bootable ISO...")
    iso_path, iso_size = step_build_iso(
        parent_dir=os.path.join(work_dir, distro_name),
        iso_output=iso_output,
        system_name=system_name,
        volume_name=volume_name,
    )

    elapsed = time.time() - t0
    mins = int(elapsed // 60)
    secs = int(elapsed % 60)

    # -- Results --
    print(f"\n{'=' * 56}")
    print(f"{C.GREEN}{C.BOLD}  BUILD COMPLETE{C.RESET}  ({mins}m {secs}s)")
    print(f"{'=' * 56}")
    print(f"  Live boot files: {live_dir}/")
    print(f"    filesystem.squashfs  ({human_size(sq_size)})")

    for f in os.listdir(live_dir):
        if f != "filesystem.squashfs":
            fpath = os.path.join(live_dir, f)
            fsize = human_size(os.path.getsize(fpath)) if os.path.isfile(fpath) else ""
            print(f"    {f}  ({fsize})")

    if iso_path:
        print(f"\n  ISO: {iso_path} ({iso_size})")
        print(f"\n  Write to USB:")
        print(f"    dd if={iso_path} of=/dev/sdX bs=4M status=progress")
    else:
        log_warn("ISO build failed - squashfs files are intact.")

    print(f"{'=' * 56}\n")


def coerce_volume(iso_name):
    name = iso_name
    if name.lower().endswith(".iso"):
        name = name[:-4]
    return name.upper().translate(str.maketrans(" .", "--"))[:32]


# ---------------------------------------------------------------
# ENTRY POINT
# ---------------------------------------------------------------
def main():
    if os.geteuid() != 0:
        print(f"{C.RED}[ERROR]{C.RESET} This utility must be run as root.")
        print("Usage: sudo python3 Live-System-Builder-CLI.py [options]")
        sys.exit(1)

    parser = argparse.ArgumentParser(
        description="Glitch Linux Live System Builder - CLI Edition",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog=(
            "Examples:\n"
            "  sudo python3 Live-System-Builder-CLI.py\n"
            "  sudo python3 Live-System-Builder-CLI.py -w /mnt/build -n my-distro\n"
            "  sudo python3 Live-System-Builder-CLI.py -w /tmp -n glitch-live --iso glitch.iso -y\n"
            "  sudo python3 Live-System-Builder-CLI.py -u liveuser -H live-box -y\n"
        )
    )

    parser.add_argument("-w", "--workdir", default="/tmp",
                        help="Working directory for the build (default: interactive)")
    parser.add_argument("-n", "--name", default="glitch-live",
                        help="Name of live boot OS / output directory (default: glitch-live)")
    parser.add_argument("-H", "--hostname",
                        help="Hostname for the live system (default: current hostname)")
    parser.add_argument("-u", "--username",
                        help="Rename primary user to this in the live system (default: unchanged)")
    parser.add_argument("--iso",
                        help="ISO filename (default: <name>.iso)")
    parser.add_argument("--system-name",
                        help="Name shown in GRUB boot menu (default: same as --name)")
    parser.add_argument("--volume",
                        help="ISO volume label (default: derived from ISO name)")
    parser.add_argument("--keep-remastered", action="store_true",
                        help="Keep the remastered directory after build")
    parser.add_argument("-y", "--yes", action="store_true",
                        help="Skip interactive setup and confirmation prompts")

    args = parser.parse_args()

    # Track whether workdir was explicitly set via CLI
    args.workdir_set = "-w" in sys.argv or "--workdir" in sys.argv

    # Run interactive setup unless -y was passed with all needed args
    if not args.yes:
        args = interactive_setup(args)

    build(args)


if __name__ == "__main__":
    main()
