#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  gdiskboot.sh v0.2                                           ║
# ║  Prepares a Linux system inside a .gdisk virtual disk file   ║
# ║  for booting via Gdisk's GRUB2 bootloader.                   ║
# ║                                                              ║
# ║  Run this INSIDE the guest OS (chroot or booted normally).   ║
# ║  It installs initramfs hooks that create /dev/gdisk0 at      ║
# ║  early boot using device-mapper, with partition devices at   ║
# ║  /dev/gdisk0p1, /dev/gdisk0p2, etc.                          ║
# ║                                                              ║
# ║  License: GPLv3+                                             ║
# ║  https://github.com/GlitchLinux/Gdisk                        ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

GDISKBOOT_VERSION="0.2"

# ── Colors ──────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
NC='\033[0m'

info()  { echo -e "${CYAN}[gdiskboot]${NC} $*"; }
ok()    { echo -e "${GREEN}[gdiskboot]${NC} $*"; }
warn()  { echo -e "${YELLOW}[gdiskboot]${NC} $*"; }
err()   { echo -e "${RED}[gdiskboot]${NC} $*" >&2; }

# ── Root check ──────────────────────────────────────────────────
if [ "$(id -u)" -ne 0 ]; then
    err "Please run this script as root or with sudo"
    exit 1
fi

# ── Detect initramfs system ────────────────────────────────────
detect_initramfs_tool() {
    if command -v dracut >/dev/null 2>&1; then
        echo "dracut"
    elif [ -d /usr/share/initramfs-tools ] && command -v update-initramfs >/dev/null 2>&1; then
        echo "initramfs-tools"
    elif command -v mkinitcpio >/dev/null 2>&1; then
        echo "mkinitcpio"
    else
        echo "unknown"
    fi
}

INITRAMFS_TOOL=$(detect_initramfs_tool)
info "Detected initramfs tool: ${INITRAMFS_TOOL}"

if [ "${INITRAMFS_TOOL}" = "unknown" ]; then
    err "No supported initramfs tool found (need dracut, initramfs-tools, or mkinitcpio)"
    exit 1
fi

# ── Check required tools ──────────────────────────────────────
for tool in dmsetup blkid awk sed grep; do
    if ! command -v "${tool}" >/dev/null 2>&1; then
        err "Required tool '${tool}' not found. Install it first."
        exit 1
    fi
done

HAS_KPARTX=0
if command -v kpartx >/dev/null 2>&1; then
    HAS_KPARTX=1
else
    warn "kpartx not found - partition discovery will be limited"
    warn "Install kpartx: apt install kpartx / dnf install kpartx / pacman -S multipath-tools"
fi

HAS_FILEFRAG=0
if command -v filefrag >/dev/null 2>&1; then
    HAS_FILEFRAG=1
else
    warn "filefrag not found - will use loop device method (works fine)"
fi

# ════════════════════════════════════════════════════════════════
#  COMMON BOOT HOOK - runs at early boot in initramfs
# ════════════════════════════════════════════════════════════════

generate_common_hook() {
cat << 'GDISK_HOOK_EOF'
#!/bin/sh
# gdiskboot early-boot hook v0.2
# Creates /dev/gdisk0 and /dev/gdisk0pN from a .gdisk virtual disk file
#
# Kernel cmdline parameters (passed by Gdisk's GRUB2):
#   gdisk.dev=UUID=xxxx        host partition containing the .gdisk file
#   gdisk.file=/path.gdisk     path to .gdisk file on host partition
#   gdisk.root=2               which partition inside .gdisk is root (default: 1)
#   gdisk.method=auto|loop     mapping method (default: auto)

gdisk_log() {
    echo "gdiskboot: $*" > /dev/kmsg 2>/dev/null
    echo "$*" >> /run/gdisk-boot.log 2>/dev/null
}

gdisk_cmdline_val() {
    local key="$1"
    local val=""
    for param in $(cat /proc/cmdline); do
        case "${param}" in
            ${key}=*)
                val="${param#${key}=}"
                ;;
        esac
    done
    echo "${val}"
}

# ── Read cmdline parameters ────────────────────────────────────
GDISK_DEV=$(gdisk_cmdline_val "gdisk.dev")
GDISK_FILE=$(gdisk_cmdline_val "gdisk.file")
GDISK_ROOT=$(gdisk_cmdline_val "gdisk.root")
GDISK_METHOD=$(gdisk_cmdline_val "gdisk.method")

# If no gdisk params, exit silently (not a gdisk boot)
if [ -z "${GDISK_DEV}" ] || [ -z "${GDISK_FILE}" ]; then
    exit 0
fi

[ -z "${GDISK_ROOT}" ] && GDISK_ROOT=1
[ -z "${GDISK_METHOD}" ] && GDISK_METHOD="auto"

gdisk_log "Starting gdiskboot"
gdisk_log "  dev=${GDISK_DEV} file=${GDISK_FILE} root=p${GDISK_ROOT} method=${GDISK_METHOD}"

mkdir -p /run/gdisk

# ── Already done check ─────────────────────────────────────────
if [ -e /dev/mapper/gdisk0 ]; then
    gdisk_log "gdisk0 already exists, skipping"
    exit 0
fi

# ── Load required kernel modules ───────────────────────────────
modprobe -q dm-mod 2>/dev/null || true
modprobe -q loop 2>/dev/null || true

for drv in usb-storage ehci-hcd ehci-pci ohci-hcd ohci-pci \
           xhci-hcd xhci-pci uhci-hcd uas nvme sd_mod \
           ext4 xfs btrfs vfat ntfs3 exfat; do
    modprobe -q "${drv}" 2>/dev/null || true
done

# ── Wait for host device ───────────────────────────────────────
gdisk_log "Waiting for host device: ${GDISK_DEV}"

HOST_BLKDEV=""
WAIT=0
while [ ${WAIT} -lt 60 ]; do
    case "${GDISK_DEV}" in
        UUID=*|LABEL=*|PARTUUID=*)
            HOST_BLKDEV=$(blkid -t "${GDISK_DEV}" -o device 2>/dev/null | head -1)
            ;;
        /dev/*)
            [ -b "${GDISK_DEV}" ] && HOST_BLKDEV="${GDISK_DEV}"
            ;;
    esac

    if [ -n "${HOST_BLKDEV}" ] && [ -b "${HOST_BLKDEV}" ]; then
        break
    fi

    sleep 0.5
    WAIT=$((WAIT + 1))
done

if [ -z "${HOST_BLKDEV}" ] || [ ! -b "${HOST_BLKDEV}" ]; then
    gdisk_log "ERROR: Host device ${GDISK_DEV} not found after 30s"
    exit 1
fi

gdisk_log "Host device found: ${HOST_BLKDEV}"

# ── Detect host filesystem ─────────────────────────────────────
HOST_FS=$(blkid -s TYPE -o value "${HOST_BLKDEV}" 2>/dev/null)
gdisk_log "Host filesystem: ${HOST_FS}"

# Load filesystem module
case "${HOST_FS}" in
    ext2|ext3|ext4) modprobe -q ext4 2>/dev/null || true ;;
    xfs)            modprobe -q xfs 2>/dev/null || true ;;
    btrfs)          modprobe -q btrfs 2>/dev/null || true ;;
    ntfs|ntfs3)     modprobe -q ntfs3 2>/dev/null || true ;;
    vfat)           modprobe -q vfat 2>/dev/null || true ;;
    exfat)          modprobe -q exfat 2>/dev/null || true ;;
esac

# ── Mount host partition ───────────────────────────────────────
# Mount read-write: the guest OS needs write access to its .gdisk file
mkdir -p /run/gdisk/host

MOUNT_OK=0
# Try rw first, then ro as fallback
if mount "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null; then
    MOUNT_OK=1
    gdisk_log "Host mounted read-write"
elif mount -o ro "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null; then
    MOUNT_OK=1
    gdisk_log "Host mounted read-only (rw mount failed)"
fi

if [ "${MOUNT_OK}" = "0" ]; then
    gdisk_log "ERROR: Failed to mount ${HOST_BLKDEV}"
    exit 1
fi

# ── Verify .gdisk file exists ──────────────────────────────────
GDISK_FULLPATH="/run/gdisk/host${GDISK_FILE}"
if [ ! -f "${GDISK_FULLPATH}" ]; then
    gdisk_log "ERROR: ${GDISK_FILE} not found on ${HOST_BLKDEV}"
    umount /run/gdisk/host 2>/dev/null
    exit 1
fi

GDISK_SIZE_BYTES=$(stat -c '%s' "${GDISK_FULLPATH}")
GDISK_SIZE_SECTORS=$((GDISK_SIZE_BYTES / 512))
gdisk_log "Image: ${GDISK_FILE} size=${GDISK_SIZE_BYTES} bytes (${GDISK_SIZE_SECTORS} sectors)"

# ── Method selection ───────────────────────────────────────────
# FIEMAP: direct sector mapping, fastest, but unreliable on NTFS
# Loop:   losetup, always works, host fs stays mounted

USE_FIEMAP=0

# Skip FIEMAP entirely on NTFS - it doesn't report extents correctly
if [ "${GDISK_METHOD}" = "loop" ]; then
    USE_FIEMAP=0
    gdisk_log "Loop method forced via cmdline"
elif [ "${HOST_FS}" = "ntfs" ] || [ "${HOST_FS}" = "ntfs3" ]; then
    USE_FIEMAP=0
    gdisk_log "NTFS detected - using loop method (FIEMAP unreliable on NTFS)"
elif [ "${GDISK_METHOD}" = "fiemap" ] || [ "${GDISK_METHOD}" = "auto" ]; then
    if command -v filefrag >/dev/null 2>&1; then
        if filefrag -e -s "${GDISK_FULLPATH}" >/dev/null 2>&1; then
            USE_FIEMAP=1
        fi
    fi
fi

# ── Get parent disk from partition device ──────────────────────
get_parent_disk() {
    local part="$1"
    local short="${part#/dev/}"
    if [ -f "/sys/class/block/${short}/../dev" ]; then
        local parent
        parent=$(basename "$(readlink -f "/sys/class/block/${short}/..")")
        echo "/dev/${parent}"
    else
        echo "${part}" | sed -E 's/p?[0-9]+$//'
    fi
}

if [ "${USE_FIEMAP}" = "1" ]; then
    # ── FIEMAP method ──────────────────────────────────────────
    gdisk_log "Using FIEMAP direct sector mapping"

    PARENT_DISK=$(get_parent_disk "${HOST_BLKDEV}")
    PART_SHORT="${HOST_BLKDEV#/dev/}"
    PART_START=$(cat "/sys/class/block/${PART_SHORT}/start" 2>/dev/null || echo 0)

    gdisk_log "Parent disk: ${PARENT_DISK}, partition start: ${PART_START} sectors"

    # Parse filefrag into dmsetup table
    DM_LOGICAL=0
    filefrag -e -s "${GDISK_FULLPATH}" 2>/dev/null | \
    grep -E '^\s+[0-9]+:' | \
    while IFS= read -r line; do
        PHYS_START=$(echo "${line}" | awk -F: '{print $3}' | awk -F'.' '{print $1}' | tr -d ' ')
        EXTENT_LEN=$(echo "${line}" | awk -F: '{print $4}' | awk -F'.' '{print $1}' | tr -d ' ')

        if [ -n "${PHYS_START}" ] && [ -n "${EXTENT_LEN}" ] && [ "${EXTENT_LEN}" -gt 0 ] 2>/dev/null; then
            ABS_OFFSET=$((PHYS_START + PART_START))
            echo "${DM_LOGICAL} ${EXTENT_LEN} linear ${PARENT_DISK} ${ABS_OFFSET}"
            DM_LOGICAL=$((DM_LOGICAL + EXTENT_LEN))
        fi
    done > /run/gdisk/dm-table

    # Sanity check: total mapped sectors must match file size
    if [ -s /run/gdisk/dm-table ]; then
        TABLE_SECTORS=$(awk '{sum += $2} END {print int(sum)}' /run/gdisk/dm-table)
        EXPECTED=$((GDISK_SIZE_SECTORS))
        # Allow 1024 sector tolerance for rounding
        DIFF=$((EXPECTED - TABLE_SECTORS))
        if [ "${DIFF}" -lt 0 ]; then
            DIFF=$(( -DIFF ))
        fi

        if [ "${DIFF}" -gt 1024 ]; then
            gdisk_log "FIEMAP incomplete: mapped ${TABLE_SECTORS} sectors, expected ${EXPECTED} - falling back to loop"
            USE_FIEMAP=0
            rm -f /run/gdisk/dm-table
        else
            gdisk_log "FIEMAP OK: ${TABLE_SECTORS} sectors mapped ($(wc -l < /run/gdisk/dm-table) extents)"
        fi
    else
        gdisk_log "FIEMAP produced empty table - falling back to loop"
        USE_FIEMAP=0
    fi

    if [ "${USE_FIEMAP}" = "1" ]; then
        # Unmount host - direct sector access doesn't need it
        umount /run/gdisk/host 2>/dev/null || true

        if ! dmsetup create gdisk0 /run/gdisk/dm-table; then
            gdisk_log "ERROR: dmsetup create gdisk0 failed - falling back to loop"
            USE_FIEMAP=0
            mount "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null || \
            mount -o ro "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null
        else
            gdisk_log "gdisk0 created via FIEMAP direct mapping"
        fi
    fi
fi

if [ "${USE_FIEMAP}" = "0" ]; then
    # ── LOOP method ────────────────────────────────────────────
    gdisk_log "Using loop device method"

    # Set up loop device (read-write so the guest OS can write to its filesystem)
    LOOP_DEV=$(losetup -f --show "${GDISK_FULLPATH}" 2>/dev/null)
    if [ -z "${LOOP_DEV}" ]; then
        gdisk_log "ERROR: losetup failed for ${GDISK_FULLPATH}"
        umount /run/gdisk/host 2>/dev/null
        exit 1
    fi

    gdisk_log "Loop device: ${LOOP_DEV}"
    LOOP_SHORT="${LOOP_DEV#/dev/}"

    # Create dm device gdisk0 pointing at the whole loop device
    LOOP_SECTORS=$(cat "/sys/class/block/${LOOP_SHORT}/size" 2>/dev/null)
    if [ -z "${LOOP_SECTORS}" ] || [ "${LOOP_SECTORS}" = "0" ]; then
        LOOP_SECTORS=$((GDISK_SIZE_BYTES / 512))
    fi

    echo "0 ${LOOP_SECTORS} linear ${LOOP_DEV} 0" > /run/gdisk/dm-table

    if ! dmsetup create gdisk0 /run/gdisk/dm-table; then
        gdisk_log "ERROR: dmsetup create gdisk0 failed"
        losetup -d "${LOOP_DEV}" 2>/dev/null
        umount /run/gdisk/host 2>/dev/null
        exit 1
    fi

    gdisk_log "gdisk0 created via loop (host stays mounted at /run/gdisk/host)"
fi

# ── Wait for gdisk0 dm device ─────────────────────────────────
DEVGDISK="/dev/mapper/gdisk0"
WAIT=0
while [ ! -e "${DEVGDISK}" ] && [ ${WAIT} -lt 20 ]; do
    sleep 0.25
    WAIT=$((WAIT + 1))
done

if [ ! -e "${DEVGDISK}" ]; then
    gdisk_log "ERROR: ${DEVGDISK} did not appear"
    exit 1
fi

ln -sf "${DEVGDISK}" /dev/gdisk0 2>/dev/null || true

# ── Partition discovery ────────────────────────────────────────
gdisk_log "Discovering partitions..."

if command -v kpartx >/dev/null 2>&1; then
    gdisk_log "Using kpartx for partition discovery"

    # For loop method, run kpartx on the loop device directly
    # (kpartx on a dm-linear-on-loop can be flaky)
    if [ -n "${LOOP_DEV}" ] && [ -b "${LOOP_DEV}" ]; then
        KPARTX_TARGET="${LOOP_DEV}"
        KPARTX_PREFIX="${LOOP_SHORT}"
    else
        KPARTX_TARGET="${DEVGDISK}"
        KPARTX_PREFIX="gdisk0"
    fi

    kpartx -a "${KPARTX_TARGET}" 2>/dev/null
    sleep 0.5

    # Create gdisk0pN dm devices mapped from the kpartx output
    for dmpart in /dev/mapper/${KPARTX_PREFIX}p*; do
        if [ -b "${dmpart}" ]; then
            PNUM="${dmpart##*${KPARTX_PREFIX}p}"

            # If kpartx created loop0pN, we need to alias them as gdisk0pN
            if [ "${KPARTX_PREFIX}" != "gdisk0" ]; then
                # Read the kpartx partition's dm table and recreate as gdisk0pN
                PTABLE=$(dmsetup table "${KPARTX_PREFIX}p${PNUM}" 2>/dev/null)
                if [ -n "${PTABLE}" ]; then
                    echo "${PTABLE}" | dmsetup create "gdisk0p${PNUM}" 2>/dev/null && \
                        gdisk_log "Partition: /dev/gdisk0p${PNUM} (from ${KPARTX_PREFIX}p${PNUM})"
                fi
            else
                gdisk_log "Partition: /dev/gdisk0p${PNUM}"
            fi

            ln -sf "/dev/mapper/gdisk0p${PNUM}" "/dev/gdisk0p${PNUM}" 2>/dev/null || true
        fi
    done

elif command -v sfdisk >/dev/null 2>&1; then
    gdisk_log "Using sfdisk for partition discovery"

    PNUM=0
    sfdisk -d "${DEVGDISK}" 2>/dev/null | grep -E '^/dev/' | while IFS= read -r line; do
        PNUM=$((PNUM + 1))
        P_START=$(echo "${line}" | sed -n 's/.*start=\s*\([0-9]*\).*/\1/p')
        P_SIZE=$(echo "${line}" | sed -n 's/.*size=\s*\([0-9]*\).*/\1/p')

        if [ -n "${P_START}" ] && [ -n "${P_SIZE}" ] && [ "${P_SIZE}" -gt 0 ]; then
            echo "0 ${P_SIZE} linear ${DEVGDISK} ${P_START}" | \
                dmsetup create "gdisk0p${PNUM}" 2>/dev/null
            ln -sf "/dev/mapper/gdisk0p${PNUM}" "/dev/gdisk0p${PNUM}" 2>/dev/null || true
            gdisk_log "Partition: /dev/gdisk0p${PNUM} start=${P_START} size=${P_SIZE}"
        fi
    done
else
    gdisk_log "WARNING: No kpartx or sfdisk - cannot discover partitions"
fi

# ── Verify root partition ──────────────────────────────────────
ROOT_DEV="/dev/gdisk0p${GDISK_ROOT}"
ROOT_MAPPER="/dev/mapper/gdisk0p${GDISK_ROOT}"

FOUND_ROOT=0
if [ -b "${ROOT_MAPPER}" ]; then
    FOUND_ROOT=1
elif [ -L "${ROOT_DEV}" ] && [ -b "${ROOT_DEV}" ]; then
    FOUND_ROOT=1
fi

if [ "${FOUND_ROOT}" = "1" ]; then
    gdisk_log "Root device ready: ${ROOT_DEV}"
else
    gdisk_log "WARNING: Root partition ${ROOT_DEV} not found"
    gdisk_log "Available devices:"
    ls -la /dev/gdisk0* /dev/mapper/gdisk0* /dev/mapper/loop* 2>/dev/null | while read -r l; do
        gdisk_log "  ${l}"
    done
fi

gdisk_log "gdiskboot setup complete"
GDISK_HOOK_EOF
}


# ════════════════════════════════════════════════════════════════
#  INSTALL: DRACUT
# ════════════════════════════════════════════════════════════════

install_dracut() {
    info "Installing dracut module..."

    local MODDIR
    if [ -d /usr/lib/dracut/modules.d ]; then
        MODDIR=/usr/lib/dracut/modules.d/99gdisk
    elif [ -d /lib/dracut/modules.d ]; then
        MODDIR=/lib/dracut/modules.d/99gdisk
    else
        err "Cannot find dracut modules directory"
        return 1
    fi

    local CONFDIR
    if [ -d /etc/dracut.conf.d ]; then
        CONFDIR=/etc/dracut.conf.d
    else
        CONFDIR=/etc/dracut.conf.d
        mkdir -p "${CONFDIR}"
    fi

    rm -rf "${MODDIR}"
    mkdir -p "${MODDIR}"

    cat > "${MODDIR}/module-setup.sh" << 'DRACUT_SETUP_EOF'
#!/bin/bash
check() {
    require_binaries dmsetup blkid awk sed grep || return 1
    return 255
}

depends() {
    echo dm
    return 0
}

install() {
    inst_multiple dmsetup blkid awk sed grep dd stat losetup \
                  ln sleep cat mkdir mount umount modprobe

    for opt_tool in kpartx filefrag sfdisk partprobe blockdev; do
        if command -v "${opt_tool}" >/dev/null 2>&1; then
            inst_multiple "${opt_tool}"
        fi
    done

    inst_hook initqueue/settled 90 "$moddir/gdisk-settled.sh"
    inst_simple "$moddir/gdisk-udev.rules" /etc/udev/rules.d/99-gdisk.rules

    dracut_need_initqueue
}
DRACUT_SETUP_EOF
    chmod +x "${MODDIR}/module-setup.sh"

    generate_common_hook > "${MODDIR}/gdisk-settled.sh"
    chmod +x "${MODDIR}/gdisk-settled.sh"

    cat > "${MODDIR}/gdisk-udev.rules" << 'UDEV_EOF'
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0",   SYMLINK+="gdisk0",   OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p1",  SYMLINK+="gdisk0p1",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p2",  SYMLINK+="gdisk0p2",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p3",  SYMLINK+="gdisk0p3",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p4",  SYMLINK+="gdisk0p4",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p5",  SYMLINK+="gdisk0p5",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p6",  SYMLINK+="gdisk0p6",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p7",  SYMLINK+="gdisk0p7",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p8",  SYMLINK+="gdisk0p8",  OPTIONS+="link_priority=100"
UDEV_EOF

    cat > "${CONFDIR}/gdisk.conf" << 'DRACUT_CONF_EOF'
add_dracutmodules+=" gdisk "
force_drivers+=" dm-mod loop "
DRACUT_CONF_EOF

    ok "Dracut module installed at ${MODDIR}"
}


# ════════════════════════════════════════════════════════════════
#  INSTALL: INITRAMFS-TOOLS (Debian/Ubuntu)
# ════════════════════════════════════════════════════════════════

install_initramfs_tools() {
    info "Installing initramfs-tools hooks..."

    cat > /usr/share/initramfs-tools/hooks/gdisk << 'HOOK_EOF'
#!/bin/sh
PREREQ="dmsetup"
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0 ;; esac

. /usr/share/initramfs-tools/hook-functions

# Required tools
for tool in dmsetup blkid awk sed grep dd stat losetup ln sleep \
            cat mkdir mount umount modprobe; do
    for p in /bin /sbin /usr/bin /usr/sbin; do
        if [ -f "${p}/${tool}" ]; then
            copy_exec "${p}/${tool}" /sbin
            break
        fi
    done
done

# Optional tools
for tool in kpartx filefrag sfdisk partprobe blockdev; do
    for p in /bin /sbin /usr/bin /usr/sbin; do
        if [ -f "${p}/${tool}" ]; then
            copy_exec "${p}/${tool}" /sbin
            break
        fi
    done
done

# Force-load required modules
force_load dm-mod
force_load loop

# Copy udev rule
if [ -f /etc/udev/rules.d/99-gdisk.rules ]; then
    mkdir -p "${DESTDIR}/etc/udev/rules.d"
    cp /etc/udev/rules.d/99-gdisk.rules "${DESTDIR}/etc/udev/rules.d/"
fi
HOOK_EOF
    chmod +x /usr/share/initramfs-tools/hooks/gdisk

    # Boot script
    generate_common_hook > /etc/initramfs-tools/scripts/local-top/gdisk
    chmod +x /etc/initramfs-tools/scripts/local-top/gdisk

    # Udev rule
    cat > /etc/udev/rules.d/99-gdisk.rules << 'UDEV_EOF'
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0",   SYMLINK+="gdisk0",   OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p1",  SYMLINK+="gdisk0p1",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p2",  SYMLINK+="gdisk0p2",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p3",  SYMLINK+="gdisk0p3",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p4",  SYMLINK+="gdisk0p4",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p5",  SYMLINK+="gdisk0p5",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p6",  SYMLINK+="gdisk0p6",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p7",  SYMLINK+="gdisk0p7",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p8",  SYMLINK+="gdisk0p8",  OPTIONS+="link_priority=100"
UDEV_EOF

    ok "initramfs-tools hooks installed"
}


# ════════════════════════════════════════════════════════════════
#  INSTALL: MKINITCPIO (Arch/Manjaro)
# ════════════════════════════════════════════════════════════════

install_mkinitcpio() {
    info "Installing mkinitcpio hooks..."

    cat > /usr/lib/initcpio/install/gdisk << 'INSTALL_EOF'
#!/bin/bash
build() {
    add_binary "dmsetup"
    add_binary "blkid"
    add_binary "awk"
    add_binary "sed"
    add_binary "grep"
    add_binary "dd"
    add_binary "stat"
    add_binary "losetup"
    add_binary "ln"
    add_binary "sleep"
    add_binary "cat"
    add_binary "mkdir"
    add_binary "mount"
    add_binary "umount"
    add_binary "modprobe"

    for opt_tool in kpartx filefrag sfdisk partprobe blockdev; do
        if command -v "${opt_tool}" >/dev/null 2>&1; then
            add_binary "${opt_tool}"
        fi
    done

    add_module "dm-mod"
    add_module "loop"

    add_file "/etc/udev/rules.d/99-gdisk.rules"

    add_runscript
}

help() {
    cat << HELPEOF
Gdisk virtual disk boot support.
Enables booting from a .gdisk disk image file.
HELPEOF
}
INSTALL_EOF
    chmod +x /usr/lib/initcpio/install/gdisk

    generate_common_hook > /usr/lib/initcpio/hooks/gdisk
    chmod +x /usr/lib/initcpio/hooks/gdisk

    cat > /etc/udev/rules.d/99-gdisk.rules << 'UDEV_EOF'
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0",   SYMLINK+="gdisk0",   OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p1",  SYMLINK+="gdisk0p1",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p2",  SYMLINK+="gdisk0p2",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p3",  SYMLINK+="gdisk0p3",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p4",  SYMLINK+="gdisk0p4",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p5",  SYMLINK+="gdisk0p5",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p6",  SYMLINK+="gdisk0p6",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p7",  SYMLINK+="gdisk0p7",  OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p8",  SYMLINK+="gdisk0p8",  OPTIONS+="link_priority=100"
UDEV_EOF

    if [ -f /etc/mkinitcpio.conf ]; then
        if ! grep -q 'gdisk' /etc/mkinitcpio.conf; then
            warn "Add 'gdisk' to HOOKS in /etc/mkinitcpio.conf"
            warn "Example: HOOKS=(base udev autodetect block gdisk filesystems)"
        fi
    fi

    ok "mkinitcpio hooks installed"
}


# ════════════════════════════════════════════════════════════════
#  GRUB FIXUP
# ════════════════════════════════════════════════════════════════

install_grub_fixup() {
    info "Installing GRUB fixup..."

    local PROBE_PATH=""
    if command -v grub-probe >/dev/null 2>&1; then
        PROBE_PATH=$(command -v grub-probe)
    elif command -v grub2-probe >/dev/null 2>&1; then
        PROBE_PATH=$(command -v grub2-probe)
    fi

    if [ -z "${PROBE_PATH}" ]; then
        warn "grub-probe not found - skipping GRUB fixup"
        return 0
    fi

    if [ -f "${PROBE_PATH}-bk" ] && grep -q 'gdiskboot' "${PROBE_PATH}" 2>/dev/null; then
        info "GRUB probe wrapper already installed"
        return 0
    fi

    [ -f "${PROBE_PATH}-bk" ] && mv "${PROBE_PATH}-bk" "${PROBE_PATH}"

    cp -a "${PROBE_PATH}" "${PROBE_PATH}-bk"

    cat > "${PROBE_PATH}" << 'GRUB_WRAPPER_EOF'
#!/bin/sh
# gdiskboot grub-probe wrapper
REAL_PROBE="${0}-bk"

OUTPUT=$("${REAL_PROBE}" "$@" 2>/tmp/gdisk-grub-probe-err)
EXITCODE=$?

if [ ${EXITCODE} -eq 0 ]; then
    echo "${OUTPUT}"
    exit 0
fi

if echo "$@" | grep -q '/dev/gdisk0\|/dev/mapper/gdisk0'; then
    case "$@" in
        *--target=device*)
            echo "/dev/gdisk0"
            exit 0 ;;
        *--target=fs*)
            for part in /dev/gdisk0p1 /dev/mapper/gdisk0p1 /dev/gdisk0; do
                if [ -b "${part}" ]; then
                    FS=$(blkid -s TYPE -o value "${part}" 2>/dev/null)
                    [ -n "${FS}" ] && echo "${FS}" && exit 0
                fi
            done
            echo "ext2"
            exit 0 ;;
        *--target=fs_uuid*)
            for part in /dev/gdisk0p1 /dev/mapper/gdisk0p1 /dev/gdisk0; do
                if [ -b "${part}" ]; then
                    UUID=$(blkid -s UUID -o value "${part}" 2>/dev/null)
                    [ -n "${UUID}" ] && echo "${UUID}" && exit 0
                fi
            done ;;
        *--target=drive*)
            echo "(gdisk0)"
            exit 0 ;;
        *--target=abstraction*)
            echo ""
            exit 0 ;;
        *--target=partmap*)
            echo "msdos"
            exit 0 ;;
    esac
fi

cat /tmp/gdisk-grub-probe-err >&2
exit ${EXITCODE}
GRUB_WRAPPER_EOF

    chmod +x "${PROBE_PATH}"
    ok "GRUB probe wrapper installed (original: ${PROBE_PATH}-bk)"
}


# ════════════════════════════════════════════════════════════════
#  UNINSTALL
# ════════════════════════════════════════════════════════════════

uninstall_gdiskboot() {
    info "Uninstalling gdiskboot..."

    for d in /usr/lib/dracut/modules.d/99gdisk /lib/dracut/modules.d/99gdisk; do
        [ -d "${d}" ] && rm -rf "${d}" && info "Removed ${d}"
    done
    for f in /etc/dracut.conf.d/gdisk.conf; do
        [ -f "${f}" ] && rm -f "${f}" && info "Removed ${f}"
    done

    for f in /usr/share/initramfs-tools/hooks/gdisk \
             /etc/initramfs-tools/scripts/local-top/gdisk; do
        [ -f "${f}" ] && rm -f "${f}" && info "Removed ${f}"
    done

    for f in /usr/lib/initcpio/install/gdisk /usr/lib/initcpio/hooks/gdisk; do
        [ -f "${f}" ] && rm -f "${f}" && info "Removed ${f}"
    done

    [ -f /etc/udev/rules.d/99-gdisk.rules ] && rm -f /etc/udev/rules.d/99-gdisk.rules && info "Removed udev rule"

    for probe in grub-probe grub2-probe; do
        local p
        p=$(command -v "${probe}" 2>/dev/null)
        if [ -n "${p}" ] && [ -f "${p}-bk" ] && grep -q 'gdiskboot' "${p}" 2>/dev/null; then
            mv "${p}-bk" "${p}"
            info "Restored original ${probe}"
        fi
    done

    ok "gdiskboot uninstalled"
    info "Rebuild initramfs to remove hooks:"
    info "  dracut -f  /  update-initramfs -u  /  mkinitcpio -P"
}


# ════════════════════════════════════════════════════════════════
#  REBUILD INITRAMFS
# ════════════════════════════════════════════════════════════════

rebuild_initramfs() {
    info "Rebuilding initramfs..."

    case "${INITRAMFS_TOOL}" in
        dracut)
            dracut -f --no-hostonly
            for k in /lib/modules/*/; do
                local kname
                kname=$(basename "${k}")
                if [ "${kname}" != "$(uname -r)" ] && [ -d "/lib/modules/${kname}/kernel" ]; then
                    info "Rebuilding for kernel ${kname}..."
                    dracut -f --no-hostonly --kver "${kname}"
                fi
            done
            ;;
        initramfs-tools)
            update-initramfs -u -k all
            ;;
        mkinitcpio)
            mkinitcpio -P
            ;;
    esac

    ok "Initramfs rebuilt"
}


# ════════════════════════════════════════════════════════════════
#  MAIN
# ════════════════════════════════════════════════════════════════

echo ""
echo "  ╔═════════════════════════════════════╗"
echo "  ║  gdiskboot v${GDISKBOOT_VERSION}                     ║"
echo "  ║  Gdisk Virtual Disk Boot Installer  ║"
echo "  ║  github.com/GlitchLinux/Gdisk       ║"
echo "  ╚═════════════════════════════════════╝"
echo ""

case "${1}" in
    -u|--uninstall)
        uninstall_gdiskboot
        rebuild_initramfs
        exit 0
        ;;
    -h|--help)
        echo "Usage: gdiskboot.sh [OPTIONS]"
        echo ""
        echo "Run inside a Linux system that lives in a .gdisk virtual disk"
        echo "file to install boot hooks needed by Gdisk's bootloader."
        echo ""
        echo "Options:"
        echo "  -u, --uninstall   Remove gdiskboot hooks and restore originals"
        echo "  -s, --skip-grub   Skip GRUB fixup"
        echo "  -h, --help        Show this help"
        echo ""
        echo "Kernel cmdline params (passed by Gdisk GRUB2):"
        echo "  gdisk.dev=UUID=xxxx      Host partition with the .gdisk file"
        echo "  gdisk.file=/path.gdisk   Path to .gdisk file on host partition"
        echo "  gdisk.root=1             Partition number for root (default: 1)"
        echo "  gdisk.method=auto        auto, fiemap, or loop"
        echo ""
        echo "Devices after boot:"
        echo "  /dev/gdisk0              Whole virtual disk"
        echo "  /dev/gdisk0p1            Partition 1"
        echo "  /dev/gdisk0p2            Partition 2 (etc)"
        echo ""
        exit 0
        ;;
esac

SKIP_GRUB=0
for arg in "$@"; do
    case "${arg}" in
        -s|--skip-grub) SKIP_GRUB=1 ;;
    esac
done

case "${INITRAMFS_TOOL}" in
    dracut)          install_dracut ;;
    initramfs-tools) install_initramfs_tools ;;
    mkinitcpio)      install_mkinitcpio ;;
esac

if [ "${SKIP_GRUB}" -eq 0 ]; then
    install_grub_fixup
fi

rebuild_initramfs

echo ""
ok "gdiskboot v${GDISKBOOT_VERSION} installation complete!"
echo ""
info "This system can now boot from a .gdisk file via Gdisk."
info ""
info "Devices after boot:"
info "  /dev/gdisk0     - the virtual disk"
info "  /dev/gdisk0p1   - partition 1"
info "  /dev/gdisk0p2   - partition 2 (etc)"
echo ""
