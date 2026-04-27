#!/usr/bin/env bash
#
# iso2disk.sh - Create a bootable FAT32 disk from an ISO file
#
# Workflow:
#   1. Prompts for source ISO file
#   2. Lists available disks and prompts for target
#   3. Asks MBR or GPT partition table
#   4. Shows confirmation dialog
#   5. Wipes target, creates partition (ISO size + 50MB padding)
#   6. Formats as FAT32, copies ISO contents
#   7. Installs syslinux/GRUB bootloader
#
# Requirements: parted, mkfs.vfat, rsync, 7z (or bsdtar), syslinux, grub2
#

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

# ─── Helpers ─────────────────────────────────────────────────────────────────
msg()   { echo -e "${CYAN}[*]${NC} $*"; }
ok()    { echo -e "${GREEN}[+]${NC} $*"; }
warn()  { echo -e "${YELLOW}[!]${NC} $*"; }
err()   { echo -e "${RED}[-]${NC} $*" >&2; }
die()   { err "$*"; exit 1; }

box() {
    local text="$1"
    local len=${#text}
    local line
    line=$(printf '─%.0s' $(seq 1 $((len + 2))))
    echo -e "${BOLD}╭${line}╮${NC}"
    echo -e "${BOLD}│ ${text} │${NC}"
    echo -e "${BOLD}╰${line}╯${NC}"
}

# ─── Pre-flight ──────────────────────────────────────────────────────────────
[[ $EUID -eq 0 ]] || die "This script must be run as root (use sudo)."

REQUIRED_TOOLS=(parted mkfs.vfat rsync lsblk wipefs blockdev partprobe)
for tool in "${REQUIRED_TOOLS[@]}"; do
    command -v "$tool" >/dev/null 2>&1 || die "Missing required tool: $tool"
done

# Need either 7z or bsdtar to extract ISO contents
EXTRACTOR=""
if command -v 7z >/dev/null 2>&1; then
    EXTRACTOR="7z"
elif command -v bsdtar >/dev/null 2>&1; then
    EXTRACTOR="bsdtar"
else
    die "Need either '7z' (p7zip-full) or 'bsdtar' (libarchive-tools) to extract ISO."
fi

# ─── Step 1: Source ISO ──────────────────────────────────────────────────────
clear
box "iso2disk - Bootable Disk Creator"
echo

while true; do
    read -e -r -p "Source ISO file path: " ISO_PATH
    ISO_PATH="${ISO_PATH/#\~/$HOME}"
    if [[ -z "$ISO_PATH" ]]; then
        warn "Path cannot be empty."
    elif [[ ! -f "$ISO_PATH" ]]; then
        err "File not found: $ISO_PATH"
    elif [[ "${ISO_PATH,,}" != *.iso ]]; then
        warn "File doesn't have .iso extension. Continue anyway? [y/N]"
        read -r ans
        [[ "${ans,,}" == "y" ]] && break
    else
        break
    fi
done

ISO_SIZE_BYTES=$(stat -c%s "$ISO_PATH")
ISO_SIZE_MB=$(( (ISO_SIZE_BYTES + 1048575) / 1048576 ))
# Add a small padding for filesystem overhead (FAT32 metadata, alignment)
PADDING_MB=50
PART_SIZE_MB=$(( ISO_SIZE_MB + PADDING_MB ))

ok "ISO selected: $ISO_PATH"
msg "ISO size: ${ISO_SIZE_MB} MB"
msg "Partition size will be: ${PART_SIZE_MB} MB (ISO + ${PADDING_MB}MB padding)"
echo

# ─── Step 2: Target disk ─────────────────────────────────────────────────────
echo -e "${BOLD}Available disks:${NC}"
lsblk -d -o NAME,SIZE,MODEL,TYPE,TRAN | grep -E 'disk' || true
echo

while true; do
    read -r -p "Target disk (e.g. /dev/sdb): " TARGET
    if [[ -z "$TARGET" ]]; then
        warn "Target cannot be empty."
    elif [[ ! -b "$TARGET" ]]; then
        err "Not a block device: $TARGET"
    elif [[ "$TARGET" =~ [0-9]+$ ]]; then
        warn "That looks like a partition. Provide the whole disk (e.g. /dev/sdb, not /dev/sdb1)."
    else
        # Sanity check - refuse to touch the running root disk
        ROOT_SRC=$(findmnt -no SOURCE /)
        ROOT_DISK=$(lsblk -no PKNAME "$ROOT_SRC" 2>/dev/null || echo "")
        if [[ -n "$ROOT_DISK" && "/dev/$ROOT_DISK" == "$TARGET" ]]; then
            die "Refusing to wipe the disk containing your root filesystem!"
        fi
        break
    fi
done

DISK_SIZE_BYTES=$(blockdev --getsize64 "$TARGET")
DISK_SIZE_MB=$(( DISK_SIZE_BYTES / 1048576 ))

if (( PART_SIZE_MB > DISK_SIZE_MB )); then
    die "Target disk (${DISK_SIZE_MB}MB) is smaller than required partition (${PART_SIZE_MB}MB)."
fi

ok "Target disk: $TARGET (${DISK_SIZE_MB} MB)"
echo

# ─── Step 3: Partition table type ────────────────────────────────────────────
echo -e "${BOLD}Partition table type:${NC}"
echo "  1) MBR  (msdos - widest BIOS compatibility)"
echo "  2) GPT  (modern UEFI systems)"
echo
while true; do
    read -r -p "Choice [1/2]: " PT_CHOICE
    case "$PT_CHOICE" in
        1) PART_TABLE="msdos"; PART_TABLE_LABEL="MBR"; break ;;
        2) PART_TABLE="gpt";   PART_TABLE_LABEL="GPT"; break ;;
        *) warn "Enter 1 or 2." ;;
    esac
done
ok "Partition table: $PART_TABLE_LABEL"
echo

# ─── Step 4: Confirmation ────────────────────────────────────────────────────
clear
box "CONFIRMATION - REVIEW BEFORE PROCEEDING"
echo
echo -e "  ${BOLD}Source ISO:${NC}      $ISO_PATH"
echo -e "  ${BOLD}ISO size:${NC}        ${ISO_SIZE_MB} MB"
echo -e "  ${BOLD}Target disk:${NC}     $TARGET (${DISK_SIZE_MB} MB)"
echo -e "  ${BOLD}Partition table:${NC} $PART_TABLE_LABEL"
echo -e "  ${BOLD}Partition size:${NC}  ${PART_SIZE_MB} MB (FAT32)"
echo -e "  ${BOLD}Extractor:${NC}       $EXTRACTOR"
echo
echo -e "${RED}${BOLD}WARNING:${NC} ${RED}ALL DATA ON $TARGET WILL BE DESTROYED!${NC}"
echo
echo -e "Current contents of $TARGET:"
lsblk "$TARGET" || true
echo

read -r -p "Type 'YES' (uppercase) to proceed: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || die "Aborted by user."

# ─── Step 5: Unmount any existing partitions ─────────────────────────────────
msg "Unmounting any mounted partitions on $TARGET..."
for part in $(lsblk -ln -o NAME "$TARGET" | tail -n +2); do
    if mountpoint -q "/dev/$part" 2>/dev/null || mount | grep -q "/dev/$part "; then
        umount "/dev/$part" 2>/dev/null || true
    fi
done

# ─── Step 6: Wipe and create partition table ─────────────────────────────────
msg "Wiping existing signatures on $TARGET..."
wipefs -af "$TARGET"
# Zero the first and last few MB to nuke any lingering metadata
dd if=/dev/zero of="$TARGET" bs=1M count=10 conv=fsync status=none
dd if=/dev/zero of="$TARGET" bs=1M seek=$(( DISK_SIZE_MB - 10 )) count=10 conv=fsync status=none 2>/dev/null || true

msg "Creating $PART_TABLE_LABEL partition table..."
parted -s "$TARGET" mklabel "$PART_TABLE"

msg "Creating ${PART_SIZE_MB}MB FAT32 partition..."
parted -s -a optimal "$TARGET" mkpart primary fat32 1MiB "${PART_SIZE_MB}MiB"

# Set bootable flags
if [[ "$PART_TABLE" == "msdos" ]]; then
    parted -s "$TARGET" set 1 boot on
else
    parted -s "$TARGET" set 1 esp on
    parted -s "$TARGET" set 1 boot on
fi

partprobe "$TARGET"
sleep 2

# Determine partition device name (handles /dev/sdb1 vs /dev/nvme0n1p1)
if [[ "$TARGET" =~ [0-9]$ ]]; then
    PART="${TARGET}p1"
else
    PART="${TARGET}1"
fi

[[ -b "$PART" ]] || die "Partition $PART did not appear after creation."

# ─── Step 7: Format FAT32 ────────────────────────────────────────────────────
msg "Formatting $PART as FAT32..."
mkfs.vfat -F 32 -n "BOOTISO" "$PART"

# ─── Step 8: Copy ISO contents ───────────────────────────────────────────────
MOUNT_POINT=$(mktemp -d /tmp/iso2disk.XXXXXX)
trap 'umount "$MOUNT_POINT" 2>/dev/null || true; rmdir "$MOUNT_POINT" 2>/dev/null || true' EXIT

msg "Mounting $PART at $MOUNT_POINT..."
mount "$PART" "$MOUNT_POINT"

msg "Extracting ISO contents to partition (this may take a while)..."
if [[ "$EXTRACTOR" == "7z" ]]; then
    7z x -y -o"$MOUNT_POINT" "$ISO_PATH" >/dev/null
else
    bsdtar -xpf "$ISO_PATH" -C "$MOUNT_POINT"
fi

msg "Syncing writes to disk..."
sync

# ─── Step 9: Optional bootloader install ─────────────────────────────────────
echo
if [[ "$PART_TABLE" == "msdos" ]] && command -v syslinux >/dev/null 2>&1; then
    read -r -p "Install syslinux MBR bootloader for BIOS boot? [Y/n]: " INSTALL_SYS
    if [[ "${INSTALL_SYS,,}" != "n" ]]; then
        msg "Installing syslinux..."
        syslinux -i "$PART" 2>/dev/null || warn "syslinux install reported issues (may still work)."
        if [[ -f /usr/lib/syslinux/mbr/mbr.bin ]]; then
            dd if=/usr/lib/syslinux/mbr/mbr.bin of="$TARGET" bs=440 count=1 conv=notrunc status=none
        elif [[ -f /usr/lib/SYSLINUX/mbr.bin ]]; then
            dd if=/usr/lib/SYSLINUX/mbr.bin of="$TARGET" bs=440 count=1 conv=notrunc status=none
        else
            warn "syslinux MBR binary not found - boot may not work without manual setup."
        fi
    fi
fi

umount "$MOUNT_POINT"
rmdir "$MOUNT_POINT"
trap - EXIT

sync
sleep 1

# ─── Done ────────────────────────────────────────────────────────────────────
echo
box "SUCCESS - Bootable disk created"
echo
ok "Target:         $TARGET"
ok "Partition:      $PART (FAT32, label BOOTISO)"
ok "Partition size: ${PART_SIZE_MB} MB"
ok "Table type:     $PART_TABLE_LABEL"
echo
msg "Final layout:"
lsblk "$TARGET"
echo
warn "If the ISO uses isolinux, you may need to rename isolinux/ -> syslinux/ for booting."
warn "For UEFI boot, the ISO must contain an EFI/BOOT/BOOTx64.EFI loader."
echo
