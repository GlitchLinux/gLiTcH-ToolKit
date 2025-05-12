#!/bin/bash

# Create temporary directory
TMP_DIR="/tmp/gLiTcH-Ventoy"
mkdir -p "$TMP_DIR"
cd "$TMP_DIR" || exit 1

# Download files
echo "Downloading files..."
wget -q "https://github.com/GlitchLinux/gLiTcH-Ventoy/raw/refs/heads/main/ventoy-1.1.05-linux.tar.gz"
wget -q "https://github.com/GlitchLinux/gLiTcH-Ventoy/raw/refs/heads/main/GLITCH-VENTOY-v1.0.tar.lzma"

# Extract Ventoy
echo "Extracting Ventoy..."
tar -xzf ventoy-1.1.05-linux.tar.gz
cd ventoy-1.1.05 || exit 1

# List available disks
echo -e "\nAvailable disks:"
lsblk -d -o NAME,SIZE,MODEL,TRAN,TYPE
echo ""

# Prompt for disk selection
while true; do
    read -rp "Enter the disk to install Ventoy to (e.g. sdb, loop1): " DISK
    DISK="/dev/${DISK}"
    if [ -b "$DISK" ]; then
        break
    else
        echo "Error: $DISK is not a valid block device. Please try again."
    fi
done

# Determine if this is a loop device
IS_LOOP=false
if [[ "$DISK" =~ /dev/loop ]]; then
    IS_LOOP=true
    echo "Detected loop device installation."
fi

# Prompt for partition style
read -rp "Partition style (MBR/GPT) [Default: MBR]: " PART_STYLE
PART_STYLE=${PART_STYLE:-MBR}
if [[ "${PART_STYLE^^}" == "GPT" ]]; then
    PART_OPT="-g"
else
    PART_OPT=""
fi

# Prompt for reserved space
while true; do
    read -rp "Reserved space (e.g. 50M, 50G or FULL) [Default: FULL]: " RESERVED_SPACE
    RESERVED_SPACE=${RESERVED_SPACE:-FULL}
    if [[ "${RESERVED_SPACE^^}" == "FULL" ]]; then
        RESERVE_OPT=""
        break
    elif [[ "$RESERVED_SPACE" =~ ^([0-9]+)([MG])$ ]]; then
        SIZE=${BASH_REMATCH[1]}
        UNIT=${BASH_REMATCH[2]}
        if [[ "$UNIT" == "G" ]]; then
            SIZE=$((SIZE * 1024))
        fi
        RESERVE_OPT="-r $SIZE"
        break
    else
        echo "Invalid format. Please use format like 50M, 50G or FULL."
    fi
done

# Prompt for filesystem
read -rp "Filesystem for data partition (vfat,exfat,ntfs) [Default: ntfs]: " FS_TYPE
FS_TYPE=${FS_TYPE:-ntfs}

# Confirm before proceeding
echo -e "\nAbout to install Ventoy with these settings:"
echo "Disk: $DISK"
echo "Partition style: ${PART_STYLE^^}"
echo "Reserved space: ${RESERVED_SPACE^^}"
echo "Filesystem: ${FS_TYPE,,}"
read -rp "Continue? (y/n) [Default: y]: " CONFIRM
CONFIRM=${CONFIRM:-y}
if [[ "${CONFIRM,,}" != "y" ]]; then
    echo "Installation cancelled."
    exit 0
fi

# Install Ventoy with default settings first
echo "Installing Ventoy to $DISK..."
sudo bash Ventoy2Disk.sh -I $PART_OPT $RESERVE_OPT "$DISK"

# Handle partition naming differently for loop devices vs regular disks
if $IS_LOOP; then
    VENTOY_PART="${DISK}p1"  # Loop devices typically use p1, p2 suffix
else
    VENTOY_PART="${DISK}1"   # Regular disks use 1, 2 suffix
fi

# Wait a moment for partitions to settle
sleep 2

# Verify partition exists
if [ ! -b "$VENTOY_PART" ]; then
    echo "Error: Partition $VENTOY_PART not found!"
    echo "Trying alternative partition naming..."
    # Try alternative naming scheme
    if [ -b "${DISK}1" ]; then
        VENTOY_PART="${DISK}1"
    elif [ -b "${DISK}p1" ]; then
        VENTOY_PART="${DISK}p1"
    else
        echo "Could not find Ventoy data partition. Installation may have failed."
        exit 1
    fi
    echo "Found partition at $VENTOY_PART"
fi

# Unmount if already mounted
MOUNT_POINT="/mnt/ventoy"
sudo umount "$VENTOY_PART" 2>/dev/null

# Format the partition with selected filesystem
echo "Formatting partition with ${FS_TYPE^^} filesystem..."
case "${FS_TYPE,,}" in
    vfat|fat|fat32)
        sudo mkfs.vfat -n "gLiTcH-VENTOY" "$VENTOY_PART"
        ;;
    exfat)
        sudo mkfs.exfat -n "gLiTcH-VENTOY" "$VENTOY_PART"
        ;;
    ntfs)
        sudo mkfs.ntfs -f -L "gLiTcH-VENTOY" "$VENTOY_PART"
        ;;
    *)
        echo "Unknown filesystem, using NTFS as default"
        sudo mkfs.ntfs -f -L "gLiTcH-VENTOY" "$VENTOY_PART"
        ;;
esac

# Mount the partition
mkdir -p "$MOUNT_POINT"
echo "Mounting $VENTOY_PART to $MOUNT_POINT..."

case "${FS_TYPE,,}" in
    vfat|fat|fat32)
        sudo mount -o umask=000 "$VENTOY_PART" "$MOUNT_POINT"
        ;;
    *)
        sudo mount "$VENTOY_PART" "$MOUNT_POINT"
        ;;
esac

# Verify mount was successful
if ! mountpoint -q "$MOUNT_POINT"; then
    echo "Error: Failed to mount $VENTOY_PART"
    exit 1
fi

# Copy and extract Glitch files
echo "Copying GLITCH-VENTOY files..."
cp "$TMP_DIR/GLITCH-VENTOY-v1.0.tar.lzma" "$MOUNT_POINT/"
cd "$MOUNT_POINT" || exit 1
echo "Extracting GLITCH-VENTOY files..."
sudo tar --xattrs --xattrs-include='*' -xf "GLITCH-VENTOY-v1.0.tar.lzma" 2>/dev/null || \
sudo tar -xf "GLITCH-VENTOY-v1.0.tar.lzma"  # Fallback without xattrs if first attempt fails

sudo rm "GLITCH-VENTOY-v1.0.tar.lzma"

# Clean up
echo "Cleaning up..."
sync  # Ensure all data is written
cd /
sudo umount "$MOUNT_POINT" 2>/dev/null
rm -rf "$TMP_DIR"

echo -e "\nVentoy installation with gLiTcH customization complete!"
echo "You can now add ISO files to the gLiTcH-VENTOY partition."
