#!/bin/bash
# cable-test.sh - USB-C cable speed test via external SSD
# Formats target drive to ext4, runs read/write benchmarks, logs results
# Author: Marcus (glitchlinux)

set -u

LOG="/home/$USER/cable-test.log"
MOUNT="/mnt/cable-test"
TESTFILE_SIZE_MB=4096   # 4 GB test file for sustained transfer

# -----------------------------------------------------------------------------
# Sanity checks
# -----------------------------------------------------------------------------
if [[ $EUID -ne 0 ]]; then
    echo "Run with sudo (needs format/mount/hdparm)." >&2
    exit 1
fi

command -v hdparm >/dev/null || { echo "hdparm not installed. sudo apt install hdparm"; exit 1; }
command -v fio    >/dev/null || echo "NOTE: fio not installed. sudo apt install fio  (optional, richer test)"

# -----------------------------------------------------------------------------
# Prompt for target drive
# -----------------------------------------------------------------------------
echo
echo "Available block devices:"
lsblk -o NAME,SIZE,MODEL,TRAN,VENDOR | grep -Ev "^loop|^sr"
echo
read -rp "Target device to WIPE and test (e.g. /dev/sdb): " TARGET

[[ -b "$TARGET" ]] || { echo "Not a block device: $TARGET"; exit 1; }

# Refuse system disk
ROOT_DEV=$(findmnt -no SOURCE / | sed 's/[0-9]*$//')
if [[ "$TARGET" == "$ROOT_DEV"* ]]; then
    echo "REFUSING to touch root disk $ROOT_DEV" >&2
    exit 1
fi

echo
echo "About to WIPE: $TARGET"
lsblk "$TARGET"
echo
read -rp "Type 'YES' to continue: " CONFIRM
[[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 1; }

# -----------------------------------------------------------------------------
# Session header
# -----------------------------------------------------------------------------
SESSION_ID=$(date +%Y%m%d-%H%M%S)
CABLE_LABEL=""
read -rp "Cable label / description (e.g. 'Anker 240W 1m'): " CABLE_LABEL

{
echo ""
echo "################################################################################"
echo "# CABLE TEST SESSION  $SESSION_ID"
echo "# Cable:   ${CABLE_LABEL:-unspecified}"
echo "# Target:  $TARGET"
echo "# Host:    $(hostname)  ($(uname -r))"
echo "# Date:    $(date -Iseconds)"
echo "################################################################################"
} | tee -a "$LOG"

# -----------------------------------------------------------------------------
# USB link negotiation info (the important part)
# -----------------------------------------------------------------------------
{
echo ""
echo "=== USB LINK NEGOTIATION ==="
echo ""
echo "--- lsusb -t (tree with negotiated speeds) ---"
lsusb -t
echo ""
echo "--- dmesg (last USB enumeration events) ---"
dmesg | grep -iE "usb|superspeed" | tail -20
echo ""
echo "--- Device details ---"
DEV_NAME=$(basename "$TARGET")
if [[ -d "/sys/block/$DEV_NAME" ]]; then
    SYSPATH=$(readlink -f "/sys/block/$DEV_NAME")
    # Walk up to find USB device node
    USB_PATH="$SYSPATH"
    while [[ "$USB_PATH" != "/" && ! -f "$USB_PATH/speed" ]]; do
        USB_PATH=$(dirname "$USB_PATH")
    done
    if [[ -f "$USB_PATH/speed" ]]; then
        SPEED=$(cat "$USB_PATH/speed")
        echo "Negotiated USB speed: ${SPEED} Mbps"
        case "$SPEED" in
            480)   echo "  -> USB 2.0 (Hi-Speed) - cable is data-limited or USB2-only" ;;
            5000)  echo "  -> USB 3.0 / 3.2 Gen 1 (SuperSpeed, 5 Gbps)" ;;
            10000) echo "  -> USB 3.1 Gen 2 / 3.2 Gen 2 (SuperSpeedPlus, 10 Gbps)" ;;
            20000) echo "  -> USB 3.2 Gen 2x2 (20 Gbps)" ;;
            40000) echo "  -> USB4 / Thunderbolt (40 Gbps)" ;;
            *)     echo "  -> Unknown/unusual speed value" ;;
        esac
    else
        echo "Could not locate USB speed sysfs node for $TARGET"
    fi
fi
} | tee -a "$LOG"

# -----------------------------------------------------------------------------
# Unmount anything on target
# -----------------------------------------------------------------------------
umount "${TARGET}"* 2>/dev/null || true

# -----------------------------------------------------------------------------
# Format drive
# -----------------------------------------------------------------------------
{
echo ""
echo "=== FORMAT ==="
} | tee -a "$LOG"

wipefs -a "$TARGET" | tee -a "$LOG"
parted -s "$TARGET" mklabel gpt mkpart primary ext4 1MiB 100% | tee -a "$LOG"
sleep 2
partprobe "$TARGET"
sleep 1

PART="${TARGET}1"
[[ -b "${TARGET}p1" ]] && PART="${TARGET}p1"  # NVMe naming

mkfs.ext4 -F -L CABLETEST "$PART" 2>&1 | tee -a "$LOG"

mkdir -p "$MOUNT"
mount "$PART" "$MOUNT"

# -----------------------------------------------------------------------------
# Test 1: hdparm - raw read speed from device (bypasses filesystem)
# -----------------------------------------------------------------------------
{
echo ""
echo "=== TEST 1: hdparm (cached + buffered read) ==="
} | tee -a "$LOG"

# Run 3 times, keep them all
for i in 1 2 3; do
    echo "--- run $i ---" | tee -a "$LOG"
    hdparm -tT --direct "$TARGET" 2>&1 | tee -a "$LOG"
done

# -----------------------------------------------------------------------------
# Test 2: dd sequential write (raw)
# -----------------------------------------------------------------------------
{
echo ""
echo "=== TEST 2: dd sequential WRITE to filesystem (${TESTFILE_SIZE_MB} MB) ==="
} | tee -a "$LOG"

sync
dd if=/dev/zero of="$MOUNT/testfile.bin" bs=1M count=$TESTFILE_SIZE_MB \
   oflag=direct status=progress 2>&1 | tee -a "$LOG"
sync

# -----------------------------------------------------------------------------
# Test 3: dd sequential read (raw)
# -----------------------------------------------------------------------------
{
echo ""
echo "=== TEST 3: dd sequential READ from filesystem (${TESTFILE_SIZE_MB} MB) ==="
} | tee -a "$LOG"

# Drop caches to force real read from device
echo 3 > /proc/sys/vm/drop_caches

dd if="$MOUNT/testfile.bin" of=/dev/null bs=1M \
   iflag=direct status=progress 2>&1 | tee -a "$LOG"

# -----------------------------------------------------------------------------
# Test 4: fio mixed load (if installed)
# -----------------------------------------------------------------------------
if command -v fio >/dev/null; then
    {
    echo ""
    echo "=== TEST 4: fio - sequential write, sequential read, random 4k read ==="
    } | tee -a "$LOG"

    rm -f "$MOUNT/testfile.bin"

    echo "--- seq write (1M blocks, 2 GB, direct) ---" | tee -a "$LOG"
    fio --name=seqwrite --filename="$MOUNT/fio.bin" --size=2G --bs=1M \
        --rw=write --direct=1 --numjobs=1 --group_reporting \
        --minimal=0 2>&1 | tee -a "$LOG"

    echo "--- seq read (1M blocks, 2 GB, direct) ---" | tee -a "$LOG"
    echo 3 > /proc/sys/vm/drop_caches
    fio --name=seqread --filename="$MOUNT/fio.bin" --size=2G --bs=1M \
        --rw=read --direct=1 --numjobs=1 --group_reporting \
        --minimal=0 2>&1 | tee -a "$LOG"

    echo "--- random 4k read (queue depth 32) ---" | tee -a "$LOG"
    echo 3 > /proc/sys/vm/drop_caches
    fio --name=randread --filename="$MOUNT/fio.bin" --size=2G --bs=4k \
        --rw=randread --direct=1 --numjobs=1 --iodepth=32 --group_reporting \
        --minimal=0 2>&1 | tee -a "$LOG"

    rm -f "$MOUNT/fio.bin"
else
    echo "" | tee -a "$LOG"
    echo "=== TEST 4: fio SKIPPED (not installed) ===" | tee -a "$LOG"
fi

# -----------------------------------------------------------------------------
# Cleanup
# -----------------------------------------------------------------------------
rm -f "$MOUNT/testfile.bin"
umount "$MOUNT"
rmdir "$MOUNT"

{
echo ""
echo "=== SESSION $SESSION_ID COMPLETE ==="
echo ""
} | tee -a "$LOG"

# Make sure the log stays owned by the invoking user, not root
chown "$SUDO_USER:$SUDO_USER" "$LOG" 2>/dev/null || true

echo ""
echo "Done. Log: $LOG"
echo "To compare cables:  grep -A2 'Cable:' $LOG"
