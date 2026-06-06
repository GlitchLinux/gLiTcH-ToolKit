#!/bin/bash
# vtoy-ext4-fix - Reformat an ext4 partition with vdiskchain-compatible flags
# and write vtoy/krn files with guaranteed 1-extent contiguity.
# Usage: sudo bash vtoy-ext4-fix.sh

set -e

RED='\033[0;31m'; GRN='\033[0;32m'; YLW='\033[1;33m'; CYN='\033[0;36m'; RST='\033[0m'

echo -e "${CYN}"
echo "  vtoy-ext4-fix"
echo "  Fix ext4 partition for vdiskchain .vtoy disk file booting"
echo -e "${RST}"

# Root check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}  Error: must run as root (sudo)${RST}"; exit 1
fi

# List available partitions
echo -e "  Available partitions:\n"
lsblk -o NAME,FSTYPE,SIZE,LABEL,MOUNTPOINT | grep -v "loop\|sr0" | sed 's/^/    /'
echo ""

read -p "  Enter partition to fix (e.g. /dev/sdb3 or /dev/nvme0n1p3): " PARTITION

if [ ! -b "$PARTITION" ]; then
    echo -e "${RED}  Error: $PARTITION is not a block device${RST}"; exit 1
fi

# Extract parent disk
if echo "$PARTITION" | grep -qP 'nvme|mmcblk'; then
    DISK=$(echo "$PARTITION" | sed 's/p[0-9]*$//')
    PART_NUM=$(echo "$PARTITION" | grep -oP 'p\K[0-9]+$')
else
    DISK=$(echo "$PARTITION" | sed 's/[0-9]*$//')
    PART_NUM=$(echo "$PARTITION" | grep -oP '[0-9]+$')
fi

echo ""
echo -e "  Disk: ${YLW}$DISK${RST}   Partition: ${YLW}$PARTITION${RST} (part $PART_NUM)"
echo ""

# Check current features
echo -e "  Current ext4 features:"
tune2fs -l "$PARTITION" 2>/dev/null | grep "Filesystem features" | sed 's/^/    /' || echo "    (not ext4 or unreadable)"
echo ""

# Check for vtoy files to preserve
MOUNT_TMP=$(mktemp -d)
VTOY_SRC=""
KRN_SRC=""
BOOT_SRC=""

echo -e "  Scanning for existing content to preserve..."
if mount "$PARTITION" "$MOUNT_TMP" 2>/dev/null; then
    if ls "$MOUNT_TMP"/boot/grub/images/*.vtoy 2>/dev/null | head -1 | grep -q vtoy; then
        VTOY_SRC=$(ls "$MOUNT_TMP"/boot/grub/images/*.vtoy 2>/dev/null | head -1)
        KRN_SRC=$(ls "$MOUNT_TMP"/boot/grub/images/*.krn 2>/dev/null | head -1)
        echo -e "    Found vtoy: ${GRN}$(basename $VTOY_SRC)${RST} ($(du -h $VTOY_SRC | cut -f1))"
        [ -n "$KRN_SRC" ] && echo -e "    Found krn:  ${GRN}$(basename $KRN_SRC)${RST}"
    fi

    # Rsync everything except vtoy/krn to a temp backup
    BACKUP_DIR=$(mktemp -d)
    echo -e "    Backing up non-vtoy content to $BACKUP_DIR ..."
    rsync -a \
        --exclude='boot/grub/images/*.vtoy' \
        --exclude='boot/grub/images/*.krn' \
        "$MOUNT_TMP/" "$BACKUP_DIR/"

    # Also preserve vtoy/krn files to temp
    if [ -n "$VTOY_SRC" ]; then
        VTOY_TMP=$(mktemp --suffix=.vtoy)
        cp "$VTOY_SRC" "$VTOY_TMP"
        [ -n "$KRN_SRC" ] && KRN_TMP=$(mktemp --suffix=.krn) && cp "$KRN_SRC" "$KRN_TMP"
    fi
    umount "$MOUNT_TMP"
fi
rmdir "$MOUNT_TMP" 2>/dev/null

echo ""
echo -e "${YLW}  WARNING: This will reformat $PARTITION.${RST}"
echo -e "  The following ext4 flags will be applied:"
echo -e "    ${GRN}^64bit ^metadata_csum ^extent ^flex_bg${RST} -b 4096"
echo -e "  These are required for vdiskchain .vtoy boot compatibility."
echo ""
read -p "  Continue? [y/N]: " CONFIRM
[[ "$CONFIRM" =~ ^[Yy]$ ]] || { echo "  Aborted."; exit 0; }

# Step 1: mkfs with correct flags
echo ""
echo -e "  [1/5] Formatting $PARTITION ..."
mkfs.ext4 -L "gdisk-ext4" \
    -O ^64bit,^metadata_csum,^extent,^flex_bg \
    -b 4096 \
    -E lazy_itable_init=0,lazy_journal_init=0 \
    "$PARTITION" 2>&1 | tail -4
echo -e "  ${GRN}mkfs done${RST}"

# Step 2: Mount and restore non-vtoy content
MOUNT_TMP=$(mktemp -d)
mount "$PARTITION" "$MOUNT_TMP"

if [ -n "$BACKUP_DIR" ] && [ -d "$BACKUP_DIR" ]; then
    echo -e "  [2/5] Restoring content (excluding vtoy/krn) ..."
    rsync -a "$BACKUP_DIR/" "$MOUNT_TMP/"
    rm -rf "$BACKUP_DIR"
    echo -e "  ${GRN}restore done${RST}"
else
    echo -e "  [2/5] No existing content to restore - partition was empty"
fi

# Step 3: grub-install BEFORE vtoy files
echo -e "  [3/5] Running grub-install (BIOS) ..."
grub-install --target=i386-pc \
    --boot-directory="$MOUNT_TMP/boot" \
    --modules="ext2 fat part_gpt biosdisk search search_fs_uuid normal configfile echo" \
    "$DISK" 2>&1
echo -e "  ${GRN}grub-install done${RST}"

# Step 4: Write vtoy/krn LAST for guaranteed 1-extent contiguity
if [ -n "$VTOY_TMP" ] && [ -f "$VTOY_TMP" ]; then
    VTOY_DEST="$MOUNT_TMP/boot/grub/images/$(basename $VTOY_SRC)"
    KRN_DEST="$MOUNT_TMP/boot/grub/images/$(basename $KRN_SRC)"

    echo -e "  [4/5] Writing vtoy file (fallocate+dd for contiguity) ..."
    fallocate -l $(stat -c%s "$VTOY_TMP") "$VTOY_DEST"
    dd if="$VTOY_TMP" of="$VTOY_DEST" conv=notrunc bs=4M 2>/dev/null
    rm -f "$VTOY_TMP"

    if [ -n "$KRN_TMP" ] && [ -f "$KRN_TMP" ]; then
        fallocate -l $(stat -c%s "$KRN_TMP") "$KRN_DEST"
        dd if="$KRN_TMP" of="$KRN_DEST" conv=notrunc bs=4M 2>/dev/null
        rm -f "$KRN_TMP"
    fi

    echo -e "  ${GRN}vtoy write done${RST}"

    # Verify fragmentation
    echo ""
    echo -e "  Fragmentation check:"
    filefrag "$VTOY_DEST" 2>/dev/null | sed 's/^/    /'
    [ -n "$KRN_SRC" ] && filefrag "$KRN_DEST" 2>/dev/null | sed 's/^/    /'
else
    echo -e "  [4/5] No vtoy files found - skipping vtoy write"
    echo -e "  ${YLW}  Note: when you add .vtoy files later, use fallocate+dd:${RST}"
    echo -e "    fallocate -l \$(stat -c%s source.vtoy) /mnt/dest.vtoy"
    echo -e "    dd if=source.vtoy of=/mnt/dest.vtoy conv=notrunc bs=4M"
fi

# Step 5: Final report
sync
echo ""
echo -e "  [5/5] Final filesystem state:"
tune2fs -l "$PARTITION" | grep "Filesystem features" | sed 's/^/    /'
df -h "$MOUNT_TMP" | awk 'NR==2{print "    Used: "$3"  Free: "$4"  ("$5" full)"}' 
umount "$MOUNT_TMP"
rmdir "$MOUNT_TMP"

echo ""
echo -e "${GRN}  Done. $PARTITION is now vdiskchain-compatible.${RST}"
echo -e "  .vtoy disk files on this partition will boot correctly via vdiskchain."
echo ""
