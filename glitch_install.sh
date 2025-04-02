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

# Main script
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
fi

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

# Wipe and partition disk (100MB EFI partition)
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
    echo -e "\nWARNING: You'll need to enter your encryption passphrase twice for verification."
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

# Mount filesystems in correct order
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

# Prepare chroot environment
echo "Preparing chroot environment..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run

cat > /mnt/chroot_install.sh <<'EOF'
#!/bin/bash

# Exit on error
set -e

# Basic system configuration
echo "Configuring system..."
[ -f /etc/localtime ] || ln -sf /usr/share/zoneinfo/UTC /etc/localtime
hwclock --systohc || true
locale-gen en_US.UTF-8
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Install GRUB
apt-get install -y grub-efi-amd64

echo "GRUB_ENABLE_CRYPTODISK=y" > /etc/default/grub

# Create minimal EFI bootloader that chainloads
mkdir -p /boot/efi/EFI/BOOT
grub-mkimage -p /efi/boot -O x86_64-efi -o /boot/efi/EFI/BOOT/BOOTX64.EFI \
    part_gpt fat ext2 chain configfile

# Create chainloading config
mkdir -p /boot/efi/efi/boot
cat > /boot/efi/efi/boot/grub.cfg <<'GRUB_CFG'
set timeout=5
menuentry "Chainload GRUB" {
    search --file --set=root /boot/grub/grub.cfg
    configfile /boot/grub/grub.cfg
}
GRUB_CFG

# Main GRUB config on root partition
ROOT_UUID=$(blkid -s UUID -o value ${USE_LUKS:+"/dev/mapper/cryptroot"} || echo "/dev/root")
cat > /boot/grub/grub.cfg <<'ROOT_GRUB'
if [ -e $prefix/grubenv ]; then load_env; fi
set default=0
set timeout=5

if [ -f /etc/crypttab ]; then
    if cryptomount -u $(blkid -s UUID -o value ${ROOT_PART}); then
        set root=(crypto0)
        configfile /boot/grub/grub.cfg
    else
        echo "Failed to unlock disk! Trying again..."
        sleep 5
        configfile ${prefix}/grub.cfg
    fi
fi

menuentry "Linux" {
    linux /vmlinuz root=UUID=${ROOT_UUID} ro
    initrd /initrd.img
}
ROOT_GRUB

# Install GRUB to both locations
grub-install --target=x86_64-efi \
             --efi-directory=/boot/efi \
             --bootloader-id=GRUB \
             --modules="part_gpt fat ext2 chain crypto luks" \
             --no-nvram

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
echo -e "\nNOTE: For LUKS, you'll need to enter your passphrase once during boot."

read -p "Press Enter after completing chroot steps..." dummy

# Clean up
umount -R /mnt
[[ "$USE_LUKS" == "y" ]] && cryptsetup close cryptroot

echo "Installation complete! Reboot into your new system."
