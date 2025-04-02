#!/bin/bash

# Exit on error and unset variables
set -o errexit
set -o nounset
set -o pipefail

# Function to verify LUKS support
verify_luks_support() {
    if ! modprobe dm-crypt; then
        echo "ERROR: Kernel doesn't support dm-crypt (LUKS)"
        exit 1
    fi
    if ! command -v cryptsetup >/dev/null; then
        echo "ERROR: cryptsetup not installed"
        exit 1
    fi
}

# Quick dependency installation at start
echo "Updating and installing dependencies..."
apt-get update && apt-get install -y \
    gdisk dosfstools e2fsprogs \
    cryptsetup cryptsetup-initramfs \
    grub-efi-amd64 grub-efi-amd64-bin \
    parted rsync locales

# Ensure script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
fi

# Check if running in UEFI mode
if [[ ! -d /sys/firmware/efi ]]; then
    echo "This script requires UEFI boot mode."
    exit 1
fi

# Disk selection
lsblk
read -p "Enter target disk (e.g., /dev/sda): " TARGET_DISK
[[ ! -b "$TARGET_DISK" ]] && { echo "Invalid disk"; exit 1; }

read -p "WARNING: ALL DATA ON $TARGET_DISK WILL BE DESTROYED! Continue? (y/N): " confirm
[[ "${confirm,,}" != "y" ]] && { echo "Aborted"; exit 0; }

# LUKS setup
read -p "Enable LUKS encryption? (y/N): " USE_LUKS
USE_LUKS=${USE_LUKS,,}

[[ "$USE_LUKS" == "y" ]] && verify_luks_support

# Wipe and partition disk
echo "Creating new partition table..."
wipefs -a "$TARGET_DISK"
sgdisk --zap-all "$TARGET_DISK"
sgdisk --clear \
       --new=1:0:+100M --typecode=1:ef00 --change-name=1:EFI \
       --new=2:0:0 --typecode=2:8309 --change-name=2:cryptroot \
       "$TARGET_DISK"
partprobe "$TARGET_DISK"
sleep 2

# Format partitions
EFI_PART="${TARGET_DISK}1"
ROOT_PART="${TARGET_DISK}2"
mkfs.vfat -F32 -n EFI "$EFI_PART"

if [[ "$USE_LUKS" == "y" ]]; then
    echo "Setting up LUKS1 encryption (for GRUB compatibility)..."
    cryptsetup luksFormat --type luks1 \
              --hash sha512 \
              --iter-time 5000 \
              --key-size 512 \
              --pbkdf pbkdf2 \
              --verify-passphrase \
              "$ROOT_PART"
    
    echo "Opening encrypted container..."
    cryptsetup open "$ROOT_PART" cryptroot
    ROOT_DEVICE="/dev/mapper/cryptroot"
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
else
    ROOT_DEVICE="$ROOT_PART"
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
fi

mkfs.ext4 -L root "$ROOT_DEVICE"

# Mount filesystems
echo "Mounting filesystems..."
mount "$ROOT_DEVICE" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

echo "Copying system files..."
rsync -aAXH --info=progress2 \
      --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} \
      / /mnt/

# Generate fstab
echo "Generating fstab..."
mkdir -p /mnt/etc
{
    echo "# <file system> <mount point> <type> <options> <dump> <pass>"
    echo "UUID=$(blkid -s UUID -o value "$EFI_PART") /boot/efi vfat defaults,umask=0077 0 1"
    echo "UUID=$(blkid -s UUID -o value "$ROOT_DEVICE") / ext4 defaults 0 1"
} > /mnt/etc/fstab

# Add crypttab entry if LUKS is enabled
if [[ "$USE_LUKS" == "y" ]]; then
    echo "cryptroot UUID=$ROOT_UUID none luks" > /mnt/etc/crypttab
fi

# Prepare chroot environment
echo "Preparing chroot environment..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run

cat > /mnt/chroot_install.sh <<'EOF'
#!/bin/bash
set -e

# Basic system configuration
echo "Configuring system..."
ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc
locale-gen en_US.UTF-8
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Install GRUB
apt-get install -y grub-efi-amd64

# Enable cryptodisk
echo "GRUB_ENABLE_CRYPTODISK=y" > /etc/default/grub

# Install GRUB bootloader
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck

# Create GRUB config
ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
cat > /boot/grub/grub.cfg <<GRUB_CFG
insmod cryptodisk
insmod luks
insmod part_gpt
insmod ext2
insmod gzio

if [ -e \$prefix/grubenv ]; then
    load_env
fi

set default=0
set timeout=5

if [ -f /etc/crypttab ]; then
    cryptomount -u $ROOT_UUID
    set root=(crypto0)
fi

menuentry "Linux" {
    search --no-floppy --fs-uuid --set=root $ROOT_UUID
    linux /vmlinuz root=UUID=$ROOT_UUID ro
    initrd /initrd.img
}
GRUB_CFG

# Update initramfs
update-initramfs -u -k all

EOF

chmod +x /mnt/chroot_install.sh

echo -e "\nIMPORTANT: Now you must:"
echo "1. chroot into the new system:"
echo "   chroot /mnt /bin/bash"
echo "2. Execute the installation script:"
echo "   /chroot_install.sh"
echo "3. After completion, exit and reboot"

read -p "Press Enter after completing chroot steps..." dummy

# Clean up
umount -R /mnt
[[ "$USE_LUKS" == "y" ]] && cryptsetup close cryptroot

echo "Installation complete! Reboot into your new system."
