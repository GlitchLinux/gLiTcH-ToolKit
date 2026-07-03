#!/bin/bash
# vfat-uuid.sh - Set volume serial (UUID) on a FAT32/FAT16/FAT12 partition
# Usage: sudo ./vfat-uuid.sh [partition] [uuid]
#        or run interactively with no arguments

set -u

RED='\033[1;31m'; GRN='\033[1;32m'; YLW='\033[1;33m'; CYN='\033[1;36m'; NC='\033[0m'

msg()  { echo -e "${CYN}>${NC} $*"; }
ok()   { echo -e "${GRN}>${NC} $*"; }
warn() { echo -e "${YLW}>${NC} $*"; }
die()  { echo -e "${RED}> ERROR:${NC} $*" >&2; exit 1; }

# --- Root check ---
[[ $EUID -eq 0 ]] || die "Run as root: sudo $0"

# --- Input: partition ---
PART="${1:-}"
if [[ -z "$PART" ]]; then
    echo ""
    lsblk -o NAME,SIZE,FSTYPE,UUID,MOUNTPOINT | grep -Ei 'name|vfat|fat32|fat16' || true
    echo ""
    read -rp "> enter partition: " PART
fi

[[ -b "$PART" ]] || die "$PART is not a block device"

# --- Verify filesystem is FAT ---
FSTYPE=$(blkid -s TYPE -o value "$PART" 2>/dev/null)
[[ "$FSTYPE" == "vfat" ]] || die "$PART is '$FSTYPE', not vfat"

# Determine FAT variant (FAT32 vs FAT16/12) for correct serial offset
FATVER=$(blkid -s VERSION -o value "$PART" 2>/dev/null)
case "$FATVER" in
    FAT32) OFFSET=67 ;;
    FAT16|FAT12) OFFSET=39 ;;
    *) warn "Could not detect FAT version, assuming FAT32 (offset 67)"
       OFFSET=67 ;;
esac

# --- Input: UUID ---
UUID_IN="${2:-}"
if [[ -z "$UUID_IN" ]]; then
    read -rp "> enter uuid: " UUID_IN
fi

# Normalize: strip dash, uppercase, validate 8 hex chars
UUID=$(echo "$UUID_IN" | tr -d '-' | tr '[:lower:]' '[:upper:]')
[[ "$UUID" =~ ^[0-9A-F]{8}$ ]] || die "Invalid UUID '$UUID_IN' (expected format: XXXX-XXXX hex)"
UUID_FMT="${UUID:0:4}-${UUID:4:4}"

CUR_UUID=$(blkid -s UUID -o value "$PART" 2>/dev/null)
msg "current UUID: ${CUR_UUID:-none}  ->  target: $UUID_FMT"

# --- Unmount if mounted ---
if findmnt -rn "$PART" >/dev/null 2>&1; then
    msg "unmounting $PART ..."
    umount "$PART" || die "Failed to unmount $PART"
else
    msg "$PART not mounted, skipping unmount"
fi

# --- Set UUID ---
msg "setting UUID to $UUID_FMT"

if command -v mlabel >/dev/null 2>&1; then
    # Preferred: mtools handles offsets internally
    mlabel -i "$PART" -N "$UUID" :: || die "mlabel failed"
else
    # Fallback: write serial little-endian via dd
    warn "mtools not found, using dd fallback (offset $OFFSET)"
    B1=${UUID:0:2}; B2=${UUID:2:2}; B3=${UUID:4:2}; B4=${UUID:6:2}
    printf "\\x$B4\\x$B3\\x$B2\\x$B1" | \
        dd of="$PART" bs=1 seek="$OFFSET" count=4 conv=notrunc status=none \
        || die "dd write failed"
fi

# --- Verify ---
msg "Verifying UUID..."
sync
udevadm trigger "$PART" 2>/dev/null; udevadm settle 2>/dev/null
NEW_UUID=$(blkid -p -s UUID -o value "$PART" 2>/dev/null)

if [[ "$NEW_UUID" == "$UUID_FMT" ]]; then
    ok "SUCCESS: $PART UUID is now $NEW_UUID"
else
    die "Verification failed: expected $UUID_FMT, got '${NEW_UUID:-none}'"
fi
