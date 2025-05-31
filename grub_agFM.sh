#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Set the USB device (change this to your USB device)
USB_DEVICE="/dev/sde"
USB_PARTITION="${USB_DEVICE}1"

# Check if the device exists
if [ ! -e "$USB_DEVICE" ]; then
    echo "Error: USB device $USB_DEVICE not found" >&2
    exit 1
fi

# Install required packages
echo "Installing required packages..."
apt-get update
apt-get install -y grub-efi-amd64-bin grub-pc-bin git wget unzip mtools

# Clone the grub2-filemanager repository
echo "Cloning grub2-filemanager repository..."
git clone https://github.com/a1ive/grub2-filemanager.git
cd grub2-filemanager || exit

# Build the project
echo "Building grub2-filemanager..."
./update_grub2.sh
./build.sh

# Prepare the USB drive
echo "Preparing USB drive..."

# Unmount any mounted partitions
umount "${USB_PARTITION}" 2>/dev/null

# Create partition table and filesystem
echo "Creating partition table and filesystem..."
parted "$USB_DEVICE" --script mklabel msdos
parted "$USB_DEVICE" --script mkpart primary fat32 1MiB 100%
parted "$USB_DEVICE" --script set 1 boot on

# Format the partition as FAT32
echo "Formatting partition as FAT32..."
mkfs.fat -F32 "$USB_PARTITION"

# Create mount point and mount the USB
echo "Mounting USB drive..."
MOUNT_POINT="/mnt/usb"
mkdir -p "$MOUNT_POINT"
mount "$USB_PARTITION" "$MOUNT_POINT"

# Install GRUB for BIOS
echo "Installing GRUB for BIOS..."
grub-install --target=i386-pc --boot-directory="$MOUNT_POINT/boot" "$USB_DEVICE"

# Install GRUB for UEFI
echo "Installing GRUB for UEFI..."
mkdir -p "$MOUNT_POINT/EFI/BOOT"
grub-mkimage -p /boot/grub -O x86_64-efi -o "$MOUNT_POINT/EFI/BOOT/bootx64.efi" \
    all_video boot btrfs cat chain configfile echo efifwsetup efinet ext2 fat font \
    gfxmenu gfxterm gzio halt hfsplus iso9660 jpeg keystatus loadenv loopback linux \
    lsefimmap lsefi lsefisystab lssal memdisk minicmd normal ntfs part_apple part_msdos \
    part_gpt password_pbkdf2 png probe reboot regexp search search_fs_uuid search_fs_file \
    search_label sleep smbios squash4 test true video xfs zstd

# Copy grub2-filemanager files
echo "Copying grub2-filemanager files..."
cp -r build/* "$MOUNT_POINT/boot/grub/"
cp grubfm.iso "$MOUNT_POINT/boot/grub/"

# Create GRUB configuration
echo "Creating GRUB configuration..."
cat > "$MOUNT_POINT/boot/grub/grub.cfg" << 'EOF'
set timeout=5
set default=0

menuentry "GRUB2 File Manager" {
    linux /boot/grub/loadfm
    initrd /boot/grub/grubfm.iso
}

menuentry "GRUB2 File Manager (x86_64 UEFI)" {
    chainloader /EFI/BOOT/bootx64.efi
}

menuentry "Reboot" {
    reboot
}

menuentry "Shutdown" {
    halt
}
EOF

# Clean up
echo "Cleaning up..."
umount "$MOUNT_POINT"
rm -rf "$MOUNT_POINT"
cd ..
rm -rf grub2-filemanager

echo "Done! USB drive is ready for both BIOS and UEFI booting."
