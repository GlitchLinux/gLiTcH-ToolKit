#!/bin/bash

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Try with 'sudo'."
    exit 1
fi

# Function to check if binary exists in chroot
check_chroot_binaries() {
    local root_path=$1
    local binaries=("/bin/bash" "/bin/sh")
    
    for bin in "${binaries[@]}"; do
        if [ ! -e "${root_path}${bin}" ]; then
            echo "Warning: ${bin} does not exist in the chroot"
            return 1
        fi
    done
    return 0
}

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
lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,LABEL

# Prompt for root partition
while true; do
    read -p "Enter the root partition (e.g., /dev/nvme0n1p2): " ROOT_PART
    if [ -b "$ROOT_PART" ]; then
        break
    else
        echo "Error: $ROOT_PART does not exist or is not a block device. Please try again."
    fi
done

# Mount root partition
echo "Mounting root partition..."
mount "$ROOT_PART" /mnt || { echo "Failed to mount root partition"; exit 1; }

# Verify basic directory structure exists
for dir in /bin /lib /lib64 /usr /etc; do
    if [ ! -d "/mnt$dir" ]; then
        echo "Warning: /mnt$dir does not exist - this may not be a valid Linux root filesystem"
    fi
done

# Check for essential binaries before proceeding
if ! check_chroot_binaries "/mnt"; then
    read -p "Essential binaries are missing in the chroot. Continue anyway? (y/N) " CONTINUE
    if [[ ! "$CONTINUE" =~ ^[Yy]$ ]]; then
        umount /mnt
        exit 1
    fi
fi

# Handle boot partition
if [ "$BOOT_MODE" = "uefi" ]; then
    while true; do
        read -p "Enter the EFI system partition (e.g., /dev/nvme0n1p1): " BOOT_PART
        if [ -b "$BOOT_PART" ]; then
            break
        else
            echo "Error: $BOOT_PART does not exist or is not a block device. Please try again."
        fi
    done
    
    # Create and mount EFI directory
    mkdir -p /mnt/boot/efi
    mount "$BOOT_PART" /mnt/boot/efi || { echo "Failed to mount EFI partition"; exit 1; }
else
    read -p "Enter the boot partition (e.g., /dev/nvme0n1p1) or press Enter if none: " BOOT_PART
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

# Check if we should copy resolv.conf for networking
read -p "Do you want to copy /etc/resolv.conf for DNS resolution? (y/n): " COPY_RESOLV
if [ "$COPY_RESOLV" = "y" ] || [ "$COPY_RESOLV" = "Y" ]; then
    cp /etc/resolv.conf /mnt/etc/resolv.conf
fi

# Verify we can chroot
echo "Testing chroot environment..."
if chroot /mnt /bin/bash -c "echo 'Chroot test successful!'"; then
    echo ""
    echo "Chroot environment is ready!"
    echo "You can now chroot into the system with:"
    echo "sudo chroot /mnt"
else
    echo ""
    echo "Chroot setup completed but test failed. You can try:"
    echo "sudo chroot /mnt /bin/sh (if available)"
    echo "Or investigate missing components in the target filesystem"
fi

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
echo "umount -R /mnt""

echo "GRUB_PURGE_PACKAGES.txt is saved here, use it to fully remove grub before re-install"
echo "GOOD LUCK!"
echo "dpkg --force-all --purge grub-common grub-pc grub-efi grub-efi-amd64 grub-efi-amd64-signed grub-efi-amd64-bin grub-efi-amd64-unsigned grub-pc-bin grub2-common penguins-eggs grub-imageboot" > GRUB_PURGE_PACKAGES.txt
