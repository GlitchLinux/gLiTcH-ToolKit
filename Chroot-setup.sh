#!/bin/bash

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Try with 'sudo'."
    exit 1
fi

# Detect UEFI or BIOS
if [ -d "/sys/firmware/efi" ]; then
    echo "UEFI system detected"
    BOOT_MODE="uefi"
else
    echo "BIOS system detected"
    BOOT_MODE="bios"
fi

# List available disks and partitions
echo "Available disks and partitions:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE

# Prompt for root partition
read -p "Enter the root partition (e.g., /dev/sda1): " ROOT_PART

# Verify root partition exists
if [ ! -b "$ROOT_PART" ]; then
    echo "Error: $ROOT_PART does not exist or is not a block device."
    exit 1
fi

# Mount root partition
echo "Mounting root partition..."
mount "$ROOT_PART" /mnt || { echo "Failed to mount root partition"; exit 1; }

# Handle boot partition
if [ "$BOOT_MODE" = "uefi" ]; then
    read -p "Enter the EFI system partition (e.g., /dev/sda2): " BOOT_PART
    if [ ! -b "$BOOT_PART" ]; then
        echo "Error: $BOOT_PART does not exist or is not a block device."
        exit 1
    fi
    
    # Create and mount EFI directory
    mkdir -p /mnt/boot/efi
    mount "$BOOT_PART" /mnt/boot/efi || { echo "Failed to mount EFI partition"; exit 1; }
else
    read -p "Enter the boot partition (e.g., /dev/sda2) or press Enter if none: " BOOT_PART
    if [ -n "$BOOT_PART" ]; then
        if [ ! -b "$BOOT_PART" ]; then
            echo "Error: $BOOT_PART does not exist or is not a block device."
            exit 1
        fi
        mkdir -p /mnt/boot
        mount "$BOOT_PART" /mnt/boot || { echo "Failed to mount boot partition"; exit 1; }
    fi
fi

# Mount necessary directories for chroot
echo "Mounting necessary directories..."
mount -t proc /proc /mnt/proc
mount --rbind /sys /mnt/sys
mount --rbind /dev /mnt/dev
mount --rbind /run /mnt/run

# Check if we should bind /tmp
read -p "Do you want to bind mount /tmp? (y/n): " BIND_TMP
if [ "$BIND_TMP" = "y" ] || [ "$BIND_TMP" = "Y" ]; then
    mount --rbind /tmp /mnt/tmp
fi

# Chroot instructions
echo ""
echo "Chroot environment is ready!"
echo "You can now chroot into the system with:"
echo "sudo chroot /mnt"
echo ""
echo "After chrooting, you may need to:"
echo "1. Set up your locale"
echo "2. Set your timezone"
echo "3. Configure your bootloader"
echo "4. Set root password"
echo "5. Perform other system maintenance"
echo ""
echo "When finished, exit the chroot and unmount with:"
echo "exit"
echo "umount -R /mnt"

exit 0
