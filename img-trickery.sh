#!/bin/bash
# Ultimate Physical Disk Emulator - Fixed Version
# Creates writable virtual disk that appears as physical device

set -euo pipefail

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}ERROR: This script must be run as root${NC}" >&2
    exit 1
fi

# Cleanup function
cleanup() {
    echo -e "\n${YELLOW}Cleaning up...${NC}"
    
    # Unmount any mounted partitions
    if [ -n "${NBD_DEVICE:-}" ] && [ -b "$NBD_DEVICE" ]; then
        echo -e "Unmounting partitions..."
        for part in ${NBD_DEVICE}p*; do
            if [ -b "$part" ]; then
                umount "$part" 2>/dev/null || true
            fi
        done
        
        echo -e "Removing device mappings..."
        kpartx -d "$NBD_DEVICE" 2>/dev/null || true
        
        echo -e "Disconnecting NBD device..."
        qemu-nbd -d "$NBD_DEVICE" 2>/dev/null || true
    fi
    
    # Remove all symlinks
    if [ -n "${PHYSICAL_DEVICE:-}" ]; then
        echo -e "Removing symlinks..."
        rm -f "${PHYSICAL_DEVICE}"* 2>/dev/null || true
    fi
    
    # Flush writes
    sync
    echo -e "${GREEN}Cleanup completed${NC}"
}

# Register cleanup
trap cleanup EXIT

# Interactive image selection
echo -e "${BLUE}=== Virtual Disk Emulator ===${NC}"
read -rp "Enter path to disk image file: " IMAGE_FILE
IMAGE_FILE=$(realpath -e "$IMAGE_FILE" 2>/dev/null || {
    echo -e "${RED}Error: Invalid image path${NC}" >&2
    exit 1
})

# Verify image exists and get size
if [ ! -f "$IMAGE_FILE" ]; then
    echo -e "${RED}Error: $IMAGE_FILE does not exist${NC}" >&2
    exit 1
fi

IMAGE_SIZE=$(du -h "$IMAGE_FILE" | cut -f1)
echo -e "${GREEN}Image file: $IMAGE_FILE ($IMAGE_SIZE)${NC}"

# Load necessary modules
echo -e "${GREEN}Loading kernel modules...${NC}"
modprobe nbd max_part=16 2>/dev/null || {
    echo -e "${RED}Error: Could not load NBD module${NC}" >&2
    exit 1
}
modprobe dm_mod 2>/dev/null || true

# Find next available physical device name
echo -e "${GREEN}Finding physical device name...${NC}"
for letter in {a..z}; do
    if [ ! -b "/dev/sd$letter" ]; then
        PHYSICAL_DEVICE="/dev/sd$letter"
        break
    fi
done

if [ -z "$PHYSICAL_DEVICE" ]; then
    echo -e "${RED}Error: Could not find available physical device name${NC}" >&2
    exit 1
fi

# Find available NBD device
echo -e "${GREEN}Acquiring NBD device...${NC}"
for i in {0..15}; do
    if [ -b "/dev/nbd$i" ] && ! qemu-nbd -c /dev/nbd$i -n >/dev/null 2>&1; then
        NBD_DEVICE="/dev/nbd$i"
        break
    fi
done

if [ -z "$NBD_DEVICE" ]; then
    echo -e "${RED}Error: No available NBD devices${NC}" >&2
    exit 1
fi

# Choose performance mode
echo -e "\n${BLUE}Choose performance mode:${NC}"
echo -e "1) Safe mode (writeback cache)"
echo -e "2) Performance mode (direct I/O)"
read -rp "Enter choice [1-2]: " MODE_CHOICE

case "$MODE_CHOICE" in
    1)
        echo -e "${GREEN}Using safe mode with writeback cache...${NC}"
        qemu-nbd \
            --format=raw \
            --cache=writeback \
            --discard=unmap \
            --detect-zeroes=unmap \
            --connect="$NBD_DEVICE" \
            "$IMAGE_FILE"
        ;;
    2)
        echo -e "${GREEN}Using performance mode with direct I/O...${NC}"
        qemu-nbd \
            --format=raw \
            --cache=none \
            --aio=native \
            --discard=unmap \
            --detect-zeroes=unmap \
            --connect="$NBD_DEVICE" \
            "$IMAGE_FILE"
        ;;
    *)
        echo -e "${YELLOW}Invalid choice, using safe mode...${NC}"
        qemu-nbd \
            --format=raw \
            --cache=writeback \
            --discard=unmap \
            --detect-zeroes=unmap \
            --connect="$NBD_DEVICE" \
            "$IMAGE_FILE"
        ;;
esac

# Wait for device to be ready
sleep 1

# Force partition table rescan
echo -e "${GREEN}Scanning partitions...${NC}"
partx -u "$NBD_DEVICE" 2>/dev/null || true
kpartx -a "$NBD_DEVICE" 2>/dev/null || true
partprobe "$NBD_DEVICE" 2>/dev/null || true
sleep 2

# Create physical device symlink
echo -e "${GREEN}Creating physical device symlink...${NC}"
ln -sf "$NBD_DEVICE" "$PHYSICAL_DEVICE"

# Create partition symlinks if they exist
part_count=0
for part in ${NBD_DEVICE}p*; do
    if [ -b "$part" ]; then
        part_num=${part##*p}
        ln -sf "$part" "${PHYSICAL_DEVICE}$part_num"
        ((part_count++))
    fi
done 2>/dev/null || true

# Final device information
echo -e "\n${GREEN}=== SUCCESS! Virtual disk is now accessible ===${NC}"
echo -e "  ${BLUE}Physical device:${NC} $PHYSICAL_DEVICE"
echo -e "  ${BLUE}Actual device:${NC} $NBD_DEVICE"
echo -e "  ${BLUE}Partitions found:${NC} $part_count"
echo -e "\n${BLUE}Partition layout:${NC}"
lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT "$NBD_DEVICE" | sed 's/^/  /'

echo -e "\n${BLUE}You can now:${NC}"
echo -e "  • Use GParted on $PHYSICAL_DEVICE"
echo -e "  • Mount partitions: sudo mount ${PHYSICAL_DEVICE}1 /mnt"
echo -e "  • Use fdisk: sudo fdisk $PHYSICAL_DEVICE"
echo -e "  • Use dd: sudo dd if=/dev/zero of=${PHYSICAL_DEVICE}1 count=1"

echo -e "\n${YELLOW}WARNING: All writes are immediate and permanent!${NC}"
echo -e "${YELLOW}To safely unmount:${NC}"
echo -e "  1. Unmount all partitions: sudo umount ${PHYSICAL_DEVICE}*"
echo -e "  2. Press Ctrl+C to run cleanup"

# Keep alive with status updates
echo -e "\n${GREEN}Device is active. Press Ctrl+C when done...${NC}"
while true; do
    sleep 60
    if [ -b "$NBD_DEVICE" ]; then
        echo -e "${GREEN}[$(date '+%H:%M:%S')] Device $PHYSICAL_DEVICE active${NC}"
    else
        echo -e "${RED}[$(date '+%H:%M:%S')] Device disconnected!${NC}"
        break
    fi
done
