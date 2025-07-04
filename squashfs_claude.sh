#!/bin/bash

# Script to create a bootable filesystem.squashfs with maximum compression
# Output location: /home/filesystem.squashfs

set -e  # Exit on error

# Check if running as root
if [ "$EUID" -ne 0 ]; then 
    echo "Please run as root (use sudo)"
    exit 1
fi

# Variables
OUTPUT_FILE="/home/filesystem.squashfs"
WORK_DIR="/tmp/squashfs_work"
SOURCE_DIR="/"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}Starting SquashFS creation process...${NC}"

# Check if mksquashfs is installed
if ! command -v mksquashfs &> /dev/null; then
    echo -e "${RED}mksquashfs not found. Installing squashfs-tools...${NC}"
    apt-get update && apt-get install -y squashfs-tools
fi

# Create work directory
mkdir -p "$WORK_DIR"

# List of directories to exclude
EXCLUDE_DIRS=(
    "/proc"
    "/sys"
    "/dev"
    "/run"
    "/tmp"
    "/mnt"
    "/media"
    "/lost+found"
    "/home/*/.cache"
    "/home/*/.local/share/Trash"
    "/var/cache"
    "/var/tmp"
    "/var/log"
    "/var/run"
    "/var/lock"
    "/var/lib/apt/lists"
    "/var/lib/dpkg/info"
    "/snap"
    "/swapfile"
    "/swap.img"
    "*.tmp"
    "*.temp"
    "*.swp"
    "*.swo"
    "*/lost+found"
    "/boot/grub/grub.cfg"  # Will be regenerated
    "/etc/fstab"           # System specific
    "/etc/mtab"            # Dynamic mount info
    "/etc/machine-id"      # Should be unique per system
)

# Build exclude parameters for mksquashfs
EXCLUDE_PARAMS=""
for dir in "${EXCLUDE_DIRS[@]}"; do
    EXCLUDE_PARAMS="$EXCLUDE_PARAMS -e $dir"
done

# Additional wildcards to exclude
EXCLUDE_PARAMS="$EXCLUDE_PARAMS -wildcards"

echo -e "${YELLOW}Directories and files to be excluded:${NC}"
printf '%s\n' "${EXCLUDE_DIRS[@]}"

# Check available space
AVAILABLE_SPACE=$(df /home | awk 'NR==2 {print $4}')
echo -e "${YELLOW}Available space in /home: ${AVAILABLE_SPACE}KB${NC}"

# Remove old squashfs if exists
if [ -f "$OUTPUT_FILE" ]; then
    echo -e "${YELLOW}Removing existing $OUTPUT_FILE${NC}"
    rm -f "$OUTPUT_FILE"
fi

# Create the squashfs filesystem with maximum compression
echo -e "${GREEN}Creating SquashFS with maximum compression...${NC}"
echo "This may take a while depending on your system size..."

mksquashfs "$SOURCE_DIR" "$OUTPUT_FILE" \
    -comp xz \
    -Xbcj x86 \
    -Xdict-size 100% \
    -b 1048576 \
    -no-duplicates \
    -noappend \
    -always-use-fragments \
    -no-exports \
    $EXCLUDE_PARAMS \
    -processors $(nproc)

# Check if creation was successful
if [ $? -eq 0 ]; then
    echo -e "${GREEN}SquashFS created successfully!${NC}"
    
    # Show file information
    echo -e "\n${YELLOW}File Information:${NC}"
    ls -lh "$OUTPUT_FILE"
    
    # Show compression ratio
    SQUASH_SIZE=$(stat -c%s "$OUTPUT_FILE")
    SQUASH_SIZE_MB=$((SQUASH_SIZE / 1024 / 1024))
    echo -e "${GREEN}Compressed size: ${SQUASH_SIZE_MB}MB${NC}"
    
    # Verify the squashfs
    echo -e "\n${YELLOW}Verifying SquashFS integrity...${NC}"
    if unsquashfs -stat "$OUTPUT_FILE" &> /dev/null; then
        echo -e "${GREEN}Verification passed!${NC}"
        
        # Show filesystem info
        echo -e "\n${YELLOW}SquashFS Information:${NC}"
        unsquashfs -stat "$OUTPUT_FILE" | head -20
    else
        echo -e "${RED}Verification failed!${NC}"
        exit 1
    fi
else
    echo -e "${RED}Failed to create SquashFS!${NC}"
    exit 1
fi

# Create a simple bootloader configuration example
echo -e "\n${YELLOW}Creating example bootloader configuration...${NC}"
cat > /home/squashfs_boot_example.txt << 'EOF'
# Example GRUB configuration for booting the SquashFS
# Add this to your GRUB configuration:

menuentry "Boot SquashFS System" {
    set root=(hd0,1)  # Adjust to your partition
    linux /vmlinuz boot=live toram filesystem=/home/filesystem.squashfs
    initrd /initrd.img
}

# For isolinux/syslinux:
LABEL squashfs
    MENU LABEL Boot SquashFS System
    KERNEL /vmlinuz
    APPEND initrd=/initrd.img boot=live toram filesystem=/home/filesystem.squashfs

# Note: You'll need:
# 1. A kernel that supports SquashFS
# 2. An initramfs with live-boot support
# 3. Proper bootloader configuration
EOF

echo -e "${GREEN}Boot configuration example saved to: /home/squashfs_boot_example.txt${NC}"

# Cleanup
rm -rf "$WORK_DIR"

echo -e "\n${GREEN}Process completed successfully!${NC}"
echo -e "${YELLOW}SquashFS location: $OUTPUT_FILE${NC}"
echo -e "${YELLOW}To make it bootable, you'll need to:${NC}"
echo "1. Copy it to a bootable medium (USB/CD)"
echo "2. Add appropriate kernel and initramfs"
echo "3. Configure bootloader (GRUB/SYSLINUX)"
echo "4. Consider using tools like 'live-build' for complete live systems"
