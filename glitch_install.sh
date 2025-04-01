#!/bin/bash

# Exit on error and unset variables
set -o errexit
set -o nounset
set -o pipefail

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root" 
    exit 1
fi

# Check for UEFI
if [[ ! -d /sys/firmware/efi ]]; then
    echo "This script requires UEFI boot mode. Legacy BIOS is not supported."
    exit 1
fi

# Select disk
lsblk
read -p "Enter the target disk (e.g., /dev/sda): " TARGET_DISK

# Verify disk exists
if [[ ! -b "$TARGET_DISK" ]]; then
    echo "Error: $TARGET_DISK is not a valid block device."
    exit 1
fi

# Confirm disk selection
read -p "WARNING: ALL DATA ON $TARGET_DISK WILL BE DESTROYED! Continue? (y/N): " confirm
if [[ "${confirm,,}" != "y" ]]; then
    echo "Aborted by user."
    exit 0
fi

# Partition name
read -p "Enter a name for the root partition (default: root): " PART_NAME
PART_NAME=${PART_NAME:-root}

# Encryption choice
read -p "Enable LUKS encryption for the root partition? (y/N): " USE_LUKS
USE_LUKS=${USE_LUKS,,}

# Partitioning
echo "Partitioning $TARGET_DISK..."
sgdisk --zap-all "$TARGET_DISK"
sgdisk --clear \
       --new=1:0:+100M --typecode=1:ef00 --change-name=1:EFI \
       --new=2:0:0 --typecode=2:8300 --change-name=2:"$PART_NAME" \
       "$TARGET_DISK"

# Refresh partition table
partprobe "$TARGET_DISK"

# Format EFI partition
EFI_PART="${TARGET_DISK}1"
mkfs.vfat -F32 "$EFI_PART"

# Format root partition
ROOT_PART="${TARGET_DISK}2"

if [[ "$USE_LUKS" == "y" ]]; then
    echo "Setting up LUKS encryption..."
    cryptsetup luksFormat --type luks2 "$ROOT_PART"
    cryptsetup open "$ROOT_PART" cryptroot
    ROOT_DEVICE="/dev/mapper/cryptroot"
else
    ROOT_DEVICE="$ROOT_PART"
fi

mkfs.ext4 -L "$PART_NAME" "$ROOT_DEVICE"

# Mount partitions
echo "Mounting partitions..."
mount "$ROOT_DEVICE" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

# Rsync system
echo "Copying system to target disk..."
rsync -aAXH --info=progress2 --exclude={"/dev/*","/proc/*","/sys/*","/tmp/*","/run/*","/mnt/*","/media/*","/lost+found"} / /mnt/

# Generate fstab manually
echo "Generating fstab..."
blkid | grep -E "$EFI_PART|$ROOT_PART" | awk '{print $2, $3, $4, "defaults 0 1"}' > /mnt/etc/fstab
findmnt -R -n /mnt >> /mnt/etc/fstab

# Chroot setup
echo "Setting up chroot..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys

# Prepare chroot script
cat > /mnt/chroot_install.sh <<EOF
#!/bin/bash

# Set up basic system
echo "Setting up system..."
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Set up locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Set up crypttab if encrypted
if [[ "$USE_LUKS" == "y" ]]; then
    echo "Setting up crypttab..."
    echo "cryptroot UUID=$(blkid -s UUID -o value $ROOT_PART) none luks" >> /etc/crypttab
fi

# Install GRUB
echo "Installing GRUB..."
grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Debian
update-grub

# Set root password
echo "Set root password:"
passwd

EOF

chmod +x /mnt/chroot_install.sh

echo ""
echo "-----------------------------------------------------------"
echo "Initial setup complete. Now you need to:"
echo "1. Open another terminal"
echo "2. Run: chroot /mnt /bin/bash"
echo "3. Execute: /chroot_install.sh"
echo "4. Follow the instructions in the chroot environment"
echo "5. After completion, exit the chroot and return here"
echo "-----------------------------------------------------------"
echo ""

read -p "Press Enter when you've completed the chroot steps to finish the installation..." dummy

echo "Installation complete! You can now reboot into your new system."
