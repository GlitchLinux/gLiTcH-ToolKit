#!/bin/bash
# ╔═════════════════════════════════════════════════════════════════╗
# ║  vDiskChain Setup - Boot raw disk images as bare metal OS       ║
# ║  https://github.com/ventoy/vdiskchain                           ║
# ║                                                                 ║
# ║  Installs vdiskchain bootloader files into an existing GRUB     ║
# ║  installation and generates boot entries for .vtoy disk images. ║
# ║                                                                 ║
# ║  Usage: sudo ./vdiskchain-setup.sh /path/to/grub/directory      ║
# ║                                                                 ║
# ║  Example: sudo ./vdiskchain-setup.sh /mnt/usb/boot/grub         ║
# ║           sudo ./vdiskchain-setup.sh /boot/grub                 ║
# ╚═════════════════════════════════════════════════════════════════╝

set -e

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ── Borderize helper (falls back to echo if not installed) ──────────
msg() {
    if command -v borderize &>/dev/null; then
        echo -e "$1" | borderize
    else
        echo -e "$1"
    fi
}

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "\n${BOLD}${CYAN}── $1 ──${NC}"; }

# ── Root check ──────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)"
    exit 1
fi

# ── Argument parsing ────────────────────────────────────────────────
GRUB_DIR="${1}"

if [[ -z "$GRUB_DIR" ]]; then
    echo ""
    msg "${BOLD}vDiskChain Setup${NC}\nBoot raw disk images (.img.vtoy) as a full bare metal OS"
    echo ""
    echo "Usage: sudo $0 /path/to/boot/grub"
    echo ""
    echo "Examples:"
    echo "  sudo $0 /mnt/usb/boot/grub    # USB drive with GRUB"
    echo "  sudo $0 /boot/grub             # Local system GRUB"
    echo ""
    exit 1
fi

# ── Validate target ─────────────────────────────────────────────────
if [[ ! -d "$GRUB_DIR" ]]; then
    err "Directory not found: $GRUB_DIR"
    exit 1
fi

if [[ ! -f "$GRUB_DIR/grub.cfg" ]]; then
    err "No grub.cfg found in $GRUB_DIR — is this a valid GRUB directory?"
    exit 1
fi

# Resolve the boot partition root (parent of boot/grub or just parent of grub)
# e.g., /mnt/usb/boot/grub -> /mnt/usb
BOOT_ROOT=""
if [[ "$(basename "$(dirname "$GRUB_DIR")")" == "boot" ]]; then
    BOOT_ROOT="$(dirname "$(dirname "$GRUB_DIR")")"
else
    BOOT_ROOT="$(dirname "$GRUB_DIR")"
fi

step "vDiskChain Setup"
info "GRUB directory : $GRUB_DIR"
info "Boot root      : $BOOT_ROOT"

# ── Step 1: Download vdiskchain release ─────────────────────────────
step "Step 1/5 — Downloading vdiskchain"

TMPDIR=$(mktemp -d /tmp/vdiskchain-setup.XXXXXX)
trap "rm -rf $TMPDIR" EXIT

RELEASE_URL="https://github.com/ventoy/vdiskchain/releases/download/v1.3/vdiskchain-1.3.tar.gz"

info "Downloading vdiskchain v1.3 release..."
if command -v wget &>/dev/null; then
    wget -q --show-progress -O "$TMPDIR/vdiskchain-1.3.tar.gz" "$RELEASE_URL"
elif command -v curl &>/dev/null; then
    curl -sL -o "$TMPDIR/vdiskchain-1.3.tar.gz" "$RELEASE_URL"
else
    err "Neither wget nor curl found — cannot download"
    exit 1
fi

tar xzf "$TMPDIR/vdiskchain-1.3.tar.gz" -C "$TMPDIR"
ok "Release v1.3 downloaded and extracted"

# ── Locate binaries ─────────────────────────────────────────────────
EFI_BIN=""
BIOS_KRN=""

[[ -f "$TMPDIR/vdiskchain-1.3/vdiskchain" ]] && EFI_BIN="$TMPDIR/vdiskchain-1.3/vdiskchain"
[[ -f "$TMPDIR/vdiskchain-1.3/ipxe.krn" ]]   && BIOS_KRN="$TMPDIR/vdiskchain-1.3/ipxe.krn"

if [[ -z "$EFI_BIN" ]]; then
    err "Could not find vdiskchain EFI binary"
    err "Manually download from: https://github.com/ventoy/vdiskchain/releases"
    exit 1
fi

# Verify file types
if ! file "$EFI_BIN" | grep -q "PE32+.*EFI"; then
    err "vdiskchain binary is not a valid EFI application"
    exit 1
fi
ok "Found vdiskchain EFI binary: $(file -b "$EFI_BIN")"

if [[ -n "$BIOS_KRN" ]]; then
    ok "Found iPXE BIOS kernel:     $(file -b "$BIOS_KRN")"
else
    warn "iPXE BIOS kernel not found — BIOS boot entries will be skipped"
fi

# ── Step 2: Copy binaries to boot partition ─────────────────────────
step "Step 2/5 — Installing boot files"

cp "$EFI_BIN" "$BOOT_ROOT/vdiskchain"
chmod 644 "$BOOT_ROOT/vdiskchain"
ok "Installed: $BOOT_ROOT/vdiskchain (EFI chainloader)"

if [[ -n "$BIOS_KRN" ]]; then
    cp "$BIOS_KRN" "$BOOT_ROOT/ipxe.krn"
    chmod 644 "$BOOT_ROOT/ipxe.krn"
    ok "Installed: $BOOT_ROOT/ipxe.krn (BIOS boot kernel)"
fi

# ── Step 3: Scan for .vtoy disk images ──────────────────────────────
step "Step 3/5 — Scanning for .vtoy disk images"

# Find the mount point of the partition containing GRUB
GRUB_MOUNT=$(df "$GRUB_DIR" --output=target | tail -1)
GRUB_DEV=$(df "$GRUB_DIR" --output=source | tail -1)
info "GRUB partition: $GRUB_DEV mounted at $GRUB_MOUNT"

# Get the parent disk of the GRUB partition
PARENT_DISK=$(lsblk -no PKNAME "$GRUB_DEV" 2>/dev/null | head -1)
if [[ -z "$PARENT_DISK" ]]; then
    PARENT_DISK=$(echo "$GRUB_DEV" | sed 's/[0-9]*$//')
fi

info "Scanning all partitions on /dev/$PARENT_DISK for .vtoy files..."

declare -a VTOY_FILES=()
declare -a VTOY_MOUNTS=()
declare -a VTOY_PARTS=()

# Scan each partition on the same disk
for part in /dev/${PARENT_DISK}*; do
    [[ "$part" == "/dev/$PARENT_DISK" ]] && continue
    [[ -b "$part" ]] || continue

    # Check if already mounted
    mount_point=$(findmnt -n -o TARGET "$part" 2>/dev/null || true)
    tmp_mounted=false

    if [[ -z "$mount_point" ]]; then
        mount_point=$(mktemp -d /tmp/vdisk-scan.XXXXXX)
        if mount -o ro "$part" "$mount_point" 2>/dev/null; then
            tmp_mounted=true
        else
            rmdir "$mount_point" 2>/dev/null
            continue
        fi
    fi

    # Search for .vtoy files
    while IFS= read -r -d '' vtoy_file; do
        rel_path="${vtoy_file#$mount_point}"
        file_size=$(stat -c%s "$vtoy_file" 2>/dev/null || echo 0)
        file_size_human=$(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B")

        VTOY_FILES+=("$rel_path")
        VTOY_MOUNTS+=("$mount_point")
        VTOY_PARTS+=("$part")

        ok "Found: $part:$rel_path ($file_size_human)"
    done < <(find "$mount_point" -maxdepth 3 -name "*.vtoy" -type f -print0 2>/dev/null)

    if $tmp_mounted; then
        umount "$mount_point" 2>/dev/null
        rmdir "$mount_point" 2>/dev/null
    fi
done

if [[ ${#VTOY_FILES[@]} -eq 0 ]]; then
    warn "No .vtoy disk images found on /dev/$PARENT_DISK"
    warn ""
    warn "To create a bootable disk image:"
    warn "  1. Create a raw disk image:  dd if=/dev/zero of=mylinux.img bs=1M count=25000"
    warn "  2. Install Linux into it using a VM (VirtualBox/QEMU)"
    warn "  3. Rename with .vtoy extension:  mv mylinux.img mylinux.img.vtoy"
    warn "  4. Place it on any partition (FAT32/NTFS/exFAT/ext4/XFS)"
    warn "  5. Re-run this script to generate boot entries"
    echo ""
    info "Creating empty vdiskchain.cfg with instructions..."
fi

# ── Step 4: Generate vdiskchain.cfg ─────────────────────────────────
step "Step 4/5 — Generating vdiskchain.cfg"

VDISK_CFG="$GRUB_DIR/vdiskchain.cfg"

# Build the config
{
    cat <<'HEADER'
# ╔══════════════════════════════════════════════════════════════════╗
# ║  vDiskChain Boot Menu                                           ║
# ║  Auto-generated - edit manually or re-run vdiskchain-setup.sh   ║
# ║                                                                 ║
# ║  Boot raw disk images (.vtoy) as bare metal operating systems   ║
# ║  https://github.com/ventoy/vdiskchain                          ║
# ╚══════════════════════════════════════════════════════════════════╝

if loadfont /boot/grub/font.pf2 ; then
    set gfxmode=auto
    insmod gfxterm
    terminal_output gfxterm
fi
set timeout=10
set default=0

HEADER

    if [[ ${#VTOY_FILES[@]} -eq 0 ]]; then
        cat <<'EMPTY'
### No .vtoy images found — add entries manually below ###
# Example UEFI entry:
#   if [ "${grub_platform}" = "efi" ]; then
#       menuentry "My Linux vDisk" {
#           insmod chain
#           chainloader /vdiskchain vdisk=/path/to/image.img.vtoy
#           boot
#       }
#   fi
#
# Example BIOS entry:
#   if [ "${grub_platform}" = "pc" ]; then
#       menuentry "My Linux vDisk" {
#           linux16 /ipxe.krn vdisk=/path/to/image.img.vtoy
#           initrd16 /vdiskchain
#           boot
#       }
#   fi

EMPTY
    else
        for i in "${!VTOY_FILES[@]}"; do
            vtoy_path="${VTOY_FILES[$i]}"
            vtoy_part="${VTOY_PARTS[$i]}"
            vtoy_name=$(basename "$vtoy_path" .vtoy)
            vtoy_name=$(basename "$vtoy_name" .img)

            # Clean up the display name
            display_name=$(echo "$vtoy_name" | sed 's/[-_]/ /g')

            echo "### $display_name ($vtoy_part) ###"

            # UEFI entry
            cat <<EOF
if [ "\${grub_platform}" = "efi" ]; then
    menuentry "${display_name} - vDiskChain" {
        insmod part_msdos
        insmod part_gpt
        insmod chain
        insmod fat
        insmod ntfs
        insmod ext2
        insmod exfat
        chainloader /vdiskchain vdisk=${vtoy_path}
        boot
    }
fi
EOF

            # BIOS entry (only if ipxe.krn was found)
            if [[ -n "$BIOS_KRN" ]]; then
                cat <<EOF
if [ "\${grub_platform}" = "pc" ]; then
    menuentry "${display_name} - vDiskChain" {
        insmod part_msdos
        insmod part_gpt
        insmod fat
        insmod ntfs
        insmod ext2
        insmod exfat
        linux16 /ipxe.krn vdisk=${vtoy_path}
        initrd16 /vdiskchain
        boot
    }
fi
EOF
            fi
            echo ""
        done
    fi

    # Return to main menu entry
    cat <<'FOOTER'
menuentry "← Back to Main Menu" {
    configfile /boot/grub/grub.cfg
}
FOOTER

} > "$VDISK_CFG"

ok "Generated: $VDISK_CFG"
if [[ ${#VTOY_FILES[@]} -gt 0 ]]; then
    info "  → ${#VTOY_FILES[@]} disk image(s) configured"
fi

# ── Step 5: Hook into main grub.cfg ────────────────────────────────
step "Step 5/5 — Adding submenu to grub.cfg"

GRUB_CFG="$GRUB_DIR/grub.cfg"

# Check if vdiskchain entry already exists
if grep -q "vdiskchain.cfg" "$GRUB_CFG" 2>/dev/null; then
    warn "vDiskChain submenu entry already exists in grub.cfg — skipping"
    info "To update, remove the existing vDiskChain menuentry and re-run"
else
    # Find a good insertion point — before "Shutdown" or at end of file
    # We append before the system controls section if it exists
    if grep -q 'menuentry "Shutdown"' "$GRUB_CFG" 2>/dev/null; then
        # Insert before Shutdown entry
        sed -i '/menuentry "Shutdown"/i \
### vDiskChain - Boot disk images as bare metal OS ###\
menuentry "vDiskChain - Disk Image Booting" {\
    configfile /boot/grub/vdiskchain.cfg\
}\
' "$GRUB_CFG"
        ok "Inserted vDiskChain submenu before Shutdown entry"
    else
        # Append to end
        {
            echo ''
            echo '### vDiskChain - Boot disk images as bare metal OS ###'
            echo 'menuentry "vDiskChain - Disk Image Booting" {'
            echo '    configfile /boot/grub/vdiskchain.cfg'
            echo '}'
        } >> "$GRUB_CFG"
        ok "Appended vDiskChain submenu to grub.cfg"
    fi
fi

# ── Summary ─────────────────────────────────────────────────────────
echo ""
step "Setup Complete"
echo ""
info "Installed files:"
info "  $BOOT_ROOT/vdiskchain          (EFI chainloader)"
[[ -n "$BIOS_KRN" ]] && \
info "  $BOOT_ROOT/ipxe.krn            (BIOS boot kernel)"
info "  $VDISK_CFG     (boot menu config)"
info "  $GRUB_CFG      (submenu entry added)"
echo ""
if [[ ${#VTOY_FILES[@]} -gt 0 ]]; then
    info "Configured disk images:"
    for i in "${!VTOY_FILES[@]}"; do
        info "  ${VTOY_PARTS[$i]}:${VTOY_FILES[$i]}"
    done
else
    info "No .vtoy images found yet."
    info "Place .img.vtoy files on any partition and re-run to generate entries."
fi
echo ""
info "IMPORTANT: Disk image files MUST have the .vtoy extension!"
info "  Example: mylinux.img.vtoy  or  debian-12.vhd.vtoy"
echo ""
info "To add more images later, re-run:"
info "  sudo $0 $GRUB_DIR"
echo ""
ok "Ready to boot! Select 'vDiskChain - Disk Image Booting' from GRUB menu."
