#!/bin/bash
# ╔══════════════════════════════════════════════════════════════╗
# ║  gdiskboot.sh v0.1                                          ║
# ║  Prepares a Linux system inside a .gdisk virtual disk file  ║
# ║  for booting via Gdisk's GRUB2 bootloader.                  ║
# ║                                                              ║
# ║  Run this INSIDE the guest OS (chroot or booted normally).   ║
# ║  It installs initramfs hooks that create /dev/gdisk0 at     ║
# ║  early boot using device-mapper, with partition devices at   ║
# ║  /dev/gdisk0p1, /dev/gdisk0p2, etc.                         ║
# ║                                                              ║
# ║  License: GPLv3+                                             ║
# ║  https://github.com/GlitchLinux/Gdisk                       ║
# ╚══════════════════════════════════════════════════════════════╝

set -e

GDISKBOOT_VERSION="0.1"

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

# kpartx is optional but recommended
HAS_KPARTX=0
if command -v kpartx >/dev/null 2>&1; then
    HAS_KPARTX=1
else
    warn "kpartx not found - will use dmsetup for partition discovery (less reliable)"
    warn "Install kpartx: apt install kpartx / dnf install kpartx / pacman -S multipath-tools"
fi

# filefrag needed for FIEMAP-based direct sector mapping
HAS_FILEFRAG=0
if command -v filefrag >/dev/null 2>&1; then
    HAS_FILEFRAG=1
else
    warn "filefrag not found - will fall back to losetup method"
    warn "Install e2fsprogs for best performance: apt install e2fsprogs"
fi

# ════════════════════════════════════════════════════════════════
#  COMMON BOOT HOOK (embedded in all three initramfs variants)
#
#  This is the core logic that runs at early boot in initramfs.
#  It reads gdisk.* parameters from /proc/cmdline, finds the
#  host partition, maps the .gdisk file as /dev/gdisk0, and
#  creates partition sub-devices.
# ════════════════════════════════════════════════════════════════

generate_common_hook() {
cat << 'GDISK_HOOK_EOF'
#!/bin/sh
# gdiskboot early-boot hook
# Creates /dev/gdisk0 and /dev/gdisk0pN from a .gdisk virtual disk file
# Parameters read from kernel cmdline:
#   gdisk.dev=UUID=xxxx   - host partition containing the .gdisk file
#   gdisk.file=/path.gdisk - path to .gdisk file on host partition
#   gdisk.root=1          - which partition inside .gdisk is root (default: 1)

gdisk_log() {
    echo "gdiskboot: $*" > /dev/kmsg 2>/dev/null
    echo "$*" >> /run/gdisk-boot.log 2>/dev/null
}

# Parse a single param from /proc/cmdline
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

# Default root partition is 1
[ -z "${GDISK_ROOT}" ] && GDISK_ROOT=1

# Default method: fiemap if filefrag available, else loop
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

# Load common storage drivers that might be needed for USB
for drv in usb-storage ehci-hcd ehci-pci ohci-hcd ohci-pci \
           xhci-hcd xhci-pci uhci-hcd uas nvme sd_mod; do
    modprobe -q "${drv}" 2>/dev/null || true
done

# ── Wait for host device ───────────────────────────────────────
gdisk_log "Waiting for host device: ${GDISK_DEV}"

HOST_BLKDEV=""
WAIT=0
while [ ${WAIT} -lt 30 ]; do
    # Support UUID=, LABEL=, PARTUUID=, or raw /dev/ path
    case "${GDISK_DEV}" in
        UUID=*)
            HOST_BLKDEV=$(blkid -t "${GDISK_DEV}" -o device 2>/dev/null | head -1)
            ;;
        LABEL=*)
            HOST_BLKDEV=$(blkid -t "${GDISK_DEV}" -o device 2>/dev/null | head -1)
            ;;
        PARTUUID=*)
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
    gdisk_log "ERROR: Host device ${GDISK_DEV} not found after 15s"
    exit 1
fi

gdisk_log "Host device found: ${HOST_BLKDEV}"

# ── Detect host filesystem and mount ───────────────────────────
HOST_FS=$(blkid -s TYPE -o value "${HOST_BLKDEV}" 2>/dev/null)
gdisk_log "Host filesystem: ${HOST_FS}"

# Load filesystem module
case "${HOST_FS}" in
    ext2|ext3|ext4) modprobe -q ext4 2>/dev/null || true ;;
    xfs)            modprobe -q xfs 2>/dev/null || true ;;
    btrfs)          modprobe -q btrfs 2>/dev/null || true ;;
    ntfs|ntfs3)     modprobe -q ntfs3 2>/dev/null || modprobe -q ntfs 2>/dev/null || true ;;
    vfat)           modprobe -q vfat 2>/dev/null || true ;;
    exfat)          modprobe -q exfat 2>/dev/null || true ;;
esac

mkdir -p /run/gdisk/host
if ! mount -o ro "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null; then
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
# fiemap: uses filefrag to get physical sector map, creates dm linear
#         table pointing directly at raw disk sectors. Fastest, no
#         host fs mount needed after setup. Requires non-fragmented
#         or lightly-fragmented file on a real block device.
#
# loop:   uses losetup to create /dev/loopN, then dm on top of that
#         with a gdisk0 name. Simpler, always works, slightly slower.
#         Host fs stays mounted.

USE_FIEMAP=0
if [ "${GDISK_METHOD}" = "fiemap" ]; then
    USE_FIEMAP=1
elif [ "${GDISK_METHOD}" = "loop" ]; then
    USE_FIEMAP=0
elif [ "${GDISK_METHOD}" = "auto" ]; then
    # Auto: use fiemap if filefrag is available and fs supports it
    if command -v filefrag >/dev/null 2>&1; then
        if filefrag -e -s "${GDISK_FULLPATH}" >/dev/null 2>&1; then
            USE_FIEMAP=1
        fi
    fi
fi

# ── Get the whole-disk device from the partition device ────────
# e.g. /dev/sda1 -> /dev/sda, /dev/nvme0n1p2 -> /dev/nvme0n1
get_parent_disk() {
    local part="$1"
    local short="${part#/dev/}"
    if [ -f "/sys/class/block/${short}/../dev" ]; then
        local parent
        parent=$(basename "$(readlink -f "/sys/class/block/${short}/..")")
        echo "/dev/${parent}"
    else
        # Fallback: strip trailing partition number
        echo "${part}" | sed -E 's/p?[0-9]+$//'
    fi
}

if [ "${USE_FIEMAP}" = "1" ]; then
    # ── FIEMAP method: direct sector mapping ───────────────────
    gdisk_log "Using FIEMAP direct sector mapping"

    PARENT_DISK=$(get_parent_disk "${HOST_BLKDEV}")

    # Get the partition start offset in 512-byte sectors
    PART_SHORT="${HOST_BLKDEV#/dev/}"
    PART_START=$(cat "/sys/class/block/${PART_SHORT}/start" 2>/dev/null || echo 0)

    gdisk_log "Parent disk: ${PARENT_DISK}, partition start: ${PART_START} sectors"

    # Parse filefrag output into dmsetup linear table
    # filefrag -e -s gives extents in 512-byte sectors:
    #   ext:  logical_offset:  physical_offset:  length:  expected:  flags:
    #   0:    0..2047:         73807872..73809919: 2048:
    DM_TABLE=""
    DM_LOGICAL=0

    filefrag -e -s "${GDISK_FULLPATH}" 2>/dev/null | \
    grep -E '^\s+[0-9]+:' | \
    while IFS= read -r line; do
        # Extract physical start and length
        PHYS_START=$(echo "${line}" | awk -F: '{print $3}' | awk -F'.' '{print $1}' | tr -d ' ')
        EXTENT_LEN=$(echo "${line}" | awk -F: '{print $4}' | awk -F'.' '{print $1}' | tr -d ' ')

        if [ -n "${PHYS_START}" ] && [ -n "${EXTENT_LEN}" ]; then
            # Add partition offset to get absolute disk offset
            ABS_OFFSET=$((PHYS_START + PART_START))
            echo "${DM_LOGICAL} ${EXTENT_LEN} linear ${PARENT_DISK} ${ABS_OFFSET}"
            DM_LOGICAL=$((DM_LOGICAL + EXTENT_LEN))
        fi
    done > /run/gdisk/dm-table

    # Unmount host - we don't need it anymore with direct sector access
    umount /run/gdisk/host 2>/dev/null || true

    if [ ! -s /run/gdisk/dm-table ]; then
        gdisk_log "ERROR: Failed to build FIEMAP sector table, falling back to loop"
        USE_FIEMAP=0
    else
        EXTENTS=$(wc -l < /run/gdisk/dm-table)
        gdisk_log "Sector table built: ${EXTENTS} extent(s)"

        if ! dmsetup create gdisk0 /run/gdisk/dm-table; then
            gdisk_log "ERROR: dmsetup create gdisk0 failed, falling back to loop"
            USE_FIEMAP=0
            # Re-mount for loop fallback
            mount -o ro "${HOST_BLKDEV}" /run/gdisk/host 2>/dev/null
        fi
    fi
fi

if [ "${USE_FIEMAP}" = "0" ]; then
    # ── LOOP method: losetup + dm rename ───────────────────────
    gdisk_log "Using loop device method"

    LOOP_DEV=$(losetup -f --show -r "${GDISK_FULLPATH}" 2>/dev/null)
    if [ -z "${LOOP_DEV}" ]; then
        gdisk_log "ERROR: losetup failed for ${GDISK_FULLPATH}"
        umount /run/gdisk/host 2>/dev/null
        exit 1
    fi

    gdisk_log "Loop device: ${LOOP_DEV}"

    # Create a dm linear device named gdisk0 on top of the loop
    LOOP_SECTORS=$(blockdev --getsz "${LOOP_DEV}" 2>/dev/null)
    if [ -z "${LOOP_SECTORS}" ]; then
        LOOP_SECTORS=$((GDISK_SIZE_BYTES / 512))
    fi

    echo "0 ${LOOP_SECTORS} linear ${LOOP_DEV} 0" > /run/gdisk/dm-table

    if ! dmsetup create gdisk0 /run/gdisk/dm-table; then
        gdisk_log "ERROR: dmsetup create gdisk0 failed"
        losetup -d "${LOOP_DEV}" 2>/dev/null
        umount /run/gdisk/host 2>/dev/null
        exit 1
    fi

    # Note: host partition stays mounted at /run/gdisk/host
    # (loop device needs the underlying file accessible)
    gdisk_log "Host partition remains mounted (loop method)"
fi

# ── Wait for dm device ─────────────────────────────────────────
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

# ── Create symlink /dev/gdisk0 ─────────────────────────────────
ln -sf "${DEVGDISK}" /dev/gdisk0 2>/dev/null || true

# ── Discover partitions ────────────────────────────────────────
if command -v kpartx >/dev/null 2>&1; then
    gdisk_log "Using kpartx for partition discovery"
    kpartx -a "${DEVGDISK}" 2>/dev/null

    # kpartx creates /dev/mapper/gdisk0p1, gdisk0p2, etc.
    sleep 0.5
    for dmpart in /dev/mapper/gdisk0p*; do
        if [ -e "${dmpart}" ]; then
            PNUM="${dmpart##*gdisk0p}"
            ln -sf "${dmpart}" "/dev/gdisk0p${PNUM}" 2>/dev/null || true
            gdisk_log "Partition: /dev/gdisk0p${PNUM}"
        fi
    done
else
    # Manual partition discovery using sfdisk/partx-style parsing
    gdisk_log "Using manual partition table parsing"

    # Read the first sector to check MBR vs GPT
    dd if="${DEVGDISK}" bs=512 count=1 of=/run/gdisk/mbr 2>/dev/null

    # Try to use partprobe or manual reading
    if command -v partprobe >/dev/null 2>&1; then
        partprobe "${DEVGDISK}" 2>/dev/null
    fi

    # Use sfdisk to dump partition layout if available
    if command -v sfdisk >/dev/null 2>&1; then
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
        gdisk_log "WARNING: No kpartx or sfdisk available. Partition discovery limited."
        gdisk_log "Install kpartx or util-linux for reliable partition detection."
    fi
fi

# ── Set up root device ─────────────────────────────────────────
ROOT_DEV="/dev/gdisk0p${GDISK_ROOT}"
if [ -e "${ROOT_DEV}" ] || [ -e "/dev/mapper/gdisk0p${GDISK_ROOT}" ]; then
    gdisk_log "Root device: ${ROOT_DEV}"
    # For dracut: set the root device
    if [ -f /tmp/root.info ] || [ -d /run/initramfs ]; then
        echo "root=${ROOT_DEV}" > /tmp/gdisk-root.conf 2>/dev/null || true
    fi
else
    gdisk_log "WARNING: Root partition /dev/gdisk0p${GDISK_ROOT} not found"
    gdisk_log "Available gdisk devices:"
    ls -la /dev/gdisk0* /dev/mapper/gdisk0* 2>/dev/null | while read -r l; do
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
    elif [ -d /usr/lib/dracut/dracut.conf.d ]; then
        CONFDIR=/usr/lib/dracut/dracut.conf.d
    else
        CONFDIR=/etc/dracut.conf.d
        mkdir -p "${CONFDIR}"
    fi

    # Clean up any previous install
    rm -rf "${MODDIR}"
    mkdir -p "${MODDIR}"

    # module-setup.sh
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
    inst_multiple dmsetup blkid awk sed grep dd stat blockdev losetup \
                  ln sleep cat mkdir mount umount modprobe

    # Optional but recommended tools
    for opt_tool in kpartx filefrag sfdisk partprobe; do
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

    # The main boot hook
    generate_common_hook > "${MODDIR}/gdisk-settled.sh"
    chmod +x "${MODDIR}/gdisk-settled.sh"

    # Udev rule for /dev/gdisk0 symlinks
    cat > "${MODDIR}/gdisk-udev.rules" << 'UDEV_EOF'
# Gdisk virtual disk device naming
# Creates /dev/gdisk0, /dev/gdisk0p1, /dev/gdisk0p2, etc.
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0",  SYMLINK+="gdisk0", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p1", SYMLINK+="gdisk0p1", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p2", SYMLINK+="gdisk0p2", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p3", SYMLINK+="gdisk0p3", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p4", SYMLINK+="gdisk0p4", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p5", SYMLINK+="gdisk0p5", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p6", SYMLINK+="gdisk0p6", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p7", SYMLINK+="gdisk0p7", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p8", SYMLINK+="gdisk0p8", OPTIONS+="link_priority=100"
UDEV_EOF

    # dracut conf to force-include the module
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

    # Hook script (copies binaries into initramfs at build time)
    cat > /usr/share/initramfs-tools/hooks/gdisk-hook.sh << 'HOOK_EOF'
#!/bin/sh
PREREQ="dmsetup"
prereqs() { echo "$PREREQ"; }
case $1 in prereqs) prereqs; exit 0 ;; esac

. /usr/share/initramfs-tools/hook-functions

# Required tools
for tool in dmsetup blkid awk sed grep dd stat losetup blockdev \
            ln sleep cat mkdir mount umount modprobe; do
    for p in /bin /sbin /usr/bin /usr/sbin; do
        if [ -f "${p}/${tool}" ]; then
            copy_exec "${p}/${tool}" /sbin
            break
        fi
    done
done

# Optional tools
for tool in kpartx filefrag sfdisk partprobe; do
    for p in /bin /sbin /usr/bin /usr/sbin; do
        if [ -f "${p}/${tool}" ]; then
            copy_exec "${p}/${tool}" /sbin
            break
        fi
    done
done

# Force-load dm-mod and loop
force_load dm-mod
force_load loop

# Copy udev rule
if [ -f /etc/udev/rules.d/99-gdisk.rules ]; then
    mkdir -p "${DESTDIR}/etc/udev/rules.d"
    cp /etc/udev/rules.d/99-gdisk.rules "${DESTDIR}/etc/udev/rules.d/"
fi
HOOK_EOF
    chmod +x /usr/share/initramfs-tools/hooks/gdisk-hook.sh

    # Boot script (runs at early boot in initramfs)
    generate_common_hook > /etc/initramfs-tools/scripts/local-top/gdisk-local-top.sh
    chmod +x /etc/initramfs-tools/scripts/local-top/gdisk-local-top.sh

    # Udev rule (installed on the live system, copied by hook)
    cat > /etc/udev/rules.d/99-gdisk.rules << 'UDEV_EOF'
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0",  SYMLINK+="gdisk0", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p1", SYMLINK+="gdisk0p1", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p2", SYMLINK+="gdisk0p2", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p3", SYMLINK+="gdisk0p3", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p4", SYMLINK+="gdisk0p4", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p5", SYMLINK+="gdisk0p5", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p6", SYMLINK+="gdisk0p6", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p7", SYMLINK+="gdisk0p7", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p8", SYMLINK+="gdisk0p8", OPTIONS+="link_priority=100"
UDEV_EOF

    ok "initramfs-tools hooks installed"
}


# ════════════════════════════════════════════════════════════════
#  INSTALL: MKINITCPIO (Arch/Manjaro)
# ════════════════════════════════════════════════════════════════

install_mkinitcpio() {
    info "Installing mkinitcpio hooks..."

    # Install hook (copies binaries at build time)
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
    add_binary "blockdev"
    add_binary "losetup"
    add_binary "ln"
    add_binary "sleep"
    add_binary "cat"
    add_binary "mkdir"
    add_binary "mount"
    add_binary "umount"
    add_binary "modprobe"

    # Optional tools
    for opt_tool in kpartx filefrag sfdisk partprobe; do
        if command -v "${opt_tool}" >/dev/null 2>&1; then
            add_binary "${opt_tool}"
        fi
    done

    add_module "dm-mod"
    add_module "loop"

    # Copy udev rule
    add_file "/etc/udev/rules.d/99-gdisk.rules"

    add_runscript
}

help() {
    cat << HELPEOF
Gdisk virtual disk boot support.
Enables booting a Linux system from a .gdisk disk image file.
HELPEOF
}
INSTALL_EOF
    chmod +x /usr/lib/initcpio/install/gdisk

    # Runtime hook
    generate_common_hook > /usr/lib/initcpio/hooks/gdisk
    chmod +x /usr/lib/initcpio/hooks/gdisk

    # Udev rule
    cat > /etc/udev/rules.d/99-gdisk.rules << 'UDEV_EOF'
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0",  SYMLINK+="gdisk0", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p1", SYMLINK+="gdisk0p1", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p2", SYMLINK+="gdisk0p2", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p3", SYMLINK+="gdisk0p3", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p4", SYMLINK+="gdisk0p4", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p5", SYMLINK+="gdisk0p5", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p6", SYMLINK+="gdisk0p6", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p7", SYMLINK+="gdisk0p7", OPTIONS+="link_priority=100"
SUBSYSTEM=="block", ENV{DM_NAME}=="gdisk0p8", SYMLINK+="gdisk0p8", OPTIONS+="link_priority=100"
UDEV_EOF

    # Check if gdisk is in mkinitcpio.conf HOOKS
    if [ -f /etc/mkinitcpio.conf ]; then
        if ! grep -q 'gdisk' /etc/mkinitcpio.conf; then
            warn "Add 'gdisk' to HOOKS in /etc/mkinitcpio.conf"
            warn "It should come after 'block' and before 'filesystems'"
            warn "Example: HOOKS=(base udev autodetect block gdisk filesystems)"
        fi
    fi

    ok "mkinitcpio hooks installed"
}


# ════════════════════════════════════════════════════════════════
#  GRUB FIXUP
#  When booted from /dev/gdisk0, grub-probe can't resolve the
#  device back to a GRUB disk. We wrap grub-probe to handle this.
# ════════════════════════════════════════════════════════════════

install_grub_fixup() {
    info "Installing GRUB fixup..."

    # Find grub-probe
    local PROBE_PATH=""
    if command -v grub-probe >/dev/null 2>&1; then
        PROBE_PATH=$(command -v grub-probe)
    elif command -v grub2-probe >/dev/null 2>&1; then
        PROBE_PATH=$(command -v grub2-probe)
    fi

    if [ -z "${PROBE_PATH}" ]; then
        warn "grub-probe not found - skipping GRUB fixup"
        warn "If this system uses GRUB, update-grub may fail."
        return 0
    fi

    # Only wrap if not already wrapped
    if [ -f "${PROBE_PATH}-bk" ]; then
        if grep -q 'gdiskboot' "${PROBE_PATH}" 2>/dev/null; then
            info "GRUB probe wrapper already installed"
            return 0
        else
            # Old non-gdisk wrapper, restore first
            mv "${PROBE_PATH}-bk" "${PROBE_PATH}"
        fi
    fi

    # Back up the original
    cp -a "${PROBE_PATH}" "${PROBE_PATH}-bk"

    # Write wrapper
    cat > "${PROBE_PATH}" << 'GRUB_WRAPPER_EOF'
#!/bin/sh
# gdiskboot grub-probe wrapper
# When running on /dev/gdisk0 (dm device backed by a .gdisk file),
# grub-probe cannot resolve the device. This wrapper intercepts
# the call and returns sane values.

REAL_PROBE="${0}-bk"

# Run the real probe first
OUTPUT=$("${REAL_PROBE}" "$@" 2>/tmp/gdisk-grub-probe-err)
EXITCODE=$?

if [ ${EXITCODE} -eq 0 ]; then
    echo "${OUTPUT}"
    exit 0
fi

# If it failed and we're on a gdisk device, provide fallback answers
if echo "$@" | grep -q '/dev/gdisk0\|/dev/mapper/gdisk0'; then
    case "$@" in
        *--target=device*)
            echo "/dev/gdisk0"
            exit 0
            ;;
        *--target=fs*)
            # Try to detect filesystem on the partition
            for part in /dev/gdisk0p1 /dev/mapper/gdisk0p1 /dev/gdisk0; do
                if [ -b "${part}" ]; then
                    FS=$(blkid -s TYPE -o value "${part}" 2>/dev/null)
                    if [ -n "${FS}" ]; then
                        echo "${FS}"
                        exit 0
                    fi
                fi
            done
            echo "ext2"
            exit 0
            ;;
        *--target=fs_uuid*)
            for part in /dev/gdisk0p1 /dev/mapper/gdisk0p1 /dev/gdisk0; do
                if [ -b "${part}" ]; then
                    UUID=$(blkid -s UUID -o value "${part}" 2>/dev/null)
                    if [ -n "${UUID}" ]; then
                        echo "${UUID}"
                        exit 0
                    fi
                fi
            done
            ;;
        *--target=drive*)
            echo "(gdisk0)"
            exit 0
            ;;
        *--target=abstraction*)
            echo ""
            exit 0
            ;;
        *--target=partmap*)
            echo "msdos"
            exit 0
            ;;
    esac
fi

# Not a gdisk device, pass through the original error
cat /tmp/gdisk-grub-probe-err >&2
exit ${EXITCODE}
GRUB_WRAPPER_EOF

    chmod +x "${PROBE_PATH}"
    ok "GRUB probe wrapper installed (original backed up as ${PROBE_PATH}-bk)"
}


# ════════════════════════════════════════════════════════════════
#  UNINSTALL
# ════════════════════════════════════════════════════════════════

uninstall_gdiskboot() {
    info "Uninstalling gdiskboot..."

    # Dracut
    for d in /usr/lib/dracut/modules.d/99gdisk /lib/dracut/modules.d/99gdisk; do
        [ -d "${d}" ] && rm -rf "${d}" && info "Removed ${d}"
    done
    for f in /etc/dracut.conf.d/gdisk.conf /usr/lib/dracut/dracut.conf.d/gdisk.conf; do
        [ -f "${f}" ] && rm -f "${f}" && info "Removed ${f}"
    done

    # initramfs-tools
    for f in /usr/share/initramfs-tools/hooks/gdisk-hook.sh \
             /etc/initramfs-tools/scripts/local-top/gdisk-local-top.sh; do
        [ -f "${f}" ] && rm -f "${f}" && info "Removed ${f}"
    done

    # mkinitcpio
    for f in /usr/lib/initcpio/install/gdisk /usr/lib/initcpio/hooks/gdisk; do
        [ -f "${f}" ] && rm -f "${f}" && info "Removed ${f}"
    done

    # Udev rule
    [ -f /etc/udev/rules.d/99-gdisk.rules ] && rm -f /etc/udev/rules.d/99-gdisk.rules && info "Removed udev rule"

    # GRUB wrapper
    for probe in grub-probe grub2-probe; do
        local p
        p=$(command -v "${probe}" 2>/dev/null)
        if [ -n "${p}" ] && [ -f "${p}-bk" ]; then
            if grep -q 'gdiskboot' "${p}" 2>/dev/null; then
                mv "${p}-bk" "${p}"
                info "Restored original ${probe}"
            fi
        fi
    done

    ok "gdiskboot uninstalled"
    info "Run your initramfs rebuild command to remove the hooks from the initramfs:"
    info "  Dracut:          dracut -f"
    info "  initramfs-tools: update-initramfs -u"
    info "  mkinitcpio:      mkinitcpio -P"
}


# ════════════════════════════════════════════════════════════════
#  REBUILD INITRAMFS
# ════════════════════════════════════════════════════════════════

rebuild_initramfs() {
    info "Rebuilding initramfs..."

    case "${INITRAMFS_TOOL}" in
        dracut)
            dracut -f --no-hostonly
            # Also rebuild for other installed kernels
            KV=$(uname -r)
            for k in /lib/modules/*/; do
                local kname
                kname=$(basename "${k}")
                if [ "${kname}" != "${KV}" ] && [ -d "/lib/modules/${kname}/kernel" ]; then
                    info "Rebuilding initramfs for kernel ${kname}..."
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
        echo "file to install the boot hooks needed by Gdisk's bootloader."
        echo ""
        echo "Options:"
        echo "  -u, --uninstall   Remove gdiskboot hooks and restore originals"
        echo "  -s, --skip-grub   Skip GRUB fixup (if not using GRUB inside guest)"
        echo "  -h, --help        Show this help"
        echo ""
        echo "Kernel cmdline parameters (passed by Gdisk's GRUB2):"
        echo "  gdisk.dev=UUID=xxxx      Host partition with the .gdisk file"
        echo "  gdisk.file=/path.gdisk   Path to .gdisk file on host partition"
        echo "  gdisk.root=1             Partition number inside .gdisk for root"
        echo "  gdisk.method=auto        Mapping method: auto, fiemap, or loop"
        echo ""
        echo "Device naming after boot:"
        echo "  /dev/gdisk0              Whole virtual disk"
        echo "  /dev/gdisk0p1            Partition 1"
        echo "  /dev/gdisk0p2            Partition 2"
        echo "  ...etc"
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

# Install the appropriate hooks
case "${INITRAMFS_TOOL}" in
    dracut)          install_dracut ;;
    initramfs-tools) install_initramfs_tools ;;
    mkinitcpio)      install_mkinitcpio ;;
esac

# Install GRUB fixup unless skipped
if [ "${SKIP_GRUB}" -eq 0 ]; then
    install_grub_fixup
fi

# Rebuild initramfs
rebuild_initramfs

echo ""
ok "gdiskboot installation complete!"
echo ""
info "This system can now boot from a .gdisk virtual disk file via Gdisk."
info ""
info "GRUB2 will pass these kernel parameters:"
info "  gdisk.dev=UUID=<host-partition-uuid>"
info "  gdisk.file=/path/to/this-system.gdisk"
info "  root=/dev/gdisk0p1"
info ""
info "Inside the booted system, devices will appear as:"
info "  /dev/gdisk0     - the virtual disk"
info "  /dev/gdisk0p1   - partition 1 (root)"
info "  /dev/gdisk0p2   - partition 2"
info ""
