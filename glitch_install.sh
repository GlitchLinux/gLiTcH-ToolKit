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

# Enhanced dependency installation
install_dependencies() {
    REQUIRED_PKGS=(
        "gdisk" "dosfstools" "e2fsprogs" 
        "cryptsetup" "cryptsetup-initramfs"
        "grub-efi-amd64" "grub-efi-amd64-bin"
        "parted" "rsync"
    )
    
    echo "Installing required packages..."
    apt-get update
    for pkg in "${REQUIRED_PKGS[@]}"; do
        if ! dpkg -l | grep -q "^ii  $pkg "; then
            apt-get install -y "$pkg"
        fi
    done
}

# Manual fstab generation (fixed version)
generate_fstab() {
    echo "Generating fstab..."
    mkdir -p /mnt/etc
    
    # Get UUIDs after mounting
    EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
    if [[ "$USE_LUKS" == "y" ]]; then
        ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEVICE")
    else
        ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
    fi
    
    {
        echo "# <file system> <mount point> <type> <options> <dump> <pass>"
        echo "UUID=$EFI_UUID /boot/efi vfat defaults,umask=0077 0 1"
        echo "UUID=$ROOT_UUID / ext4 defaults 0 1"
    } > /mnt/etc/fstab
    
    echo "Generated fstab:"
    cat /mnt/etc/fstab
}

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

install_dependencies
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

# Generate fstab after mounting
generate_fstab

# Prepare chroot environment
echo "Preparing chroot environment..."
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /run /mnt/run

cat > /mnt/chroot_install.sh <<EOF
#!/bin/bash

# Basic setup
export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# Fix systemd bus connection
mkdir -p /run/systemd
ln -fs /proc/self/mounts /etc/mtab

# Fix EFI variables support
mount -t efivarfs efivarfs /sys/firmware/efi/efivars 2>/dev/null || true

# Fix locale issues
export LANG=C.UTF-8
export LC_ALL=C.UTF-8
apt-get install -y locales
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf

# Timezone setup
ln -sf /usr/share/zoneinfo/$(timedatectl | grep "Time zone" | awk '{print $3}') /etc/localtime 2>/dev/null || true
hwclock --systohc

# LUKS specific setup
if [[ "$USE_LUKS" == "y" ]]; then
    echo "Configuring encrypted boot..."
    
    # Install necessary packages
    apt-get update
    apt-get install -y cryptsetup-initramfs grub-efi-amd64-bin
    
    # Create keyfile for automatic unlock
    mkdir -p /etc/cryptsetup-keys.d
    dd if=/dev/urandom bs=512 count=4 of=/etc/cryptsetup-keys.d/cryptroot.key
    chmod 0400 /etc/cryptsetup-keys.d/cryptroot.key
    
    # Add key to LUKS container
    while ! cryptsetup luksAddKey "$ROOT_PART" /etc/cryptsetup-keys.d/cryptroot.key; do
        echo "Failed to add key, trying again..."
        sleep 1
    done
    
    # Configure crypttab
    echo "cryptroot UUID=$ROOT_UUID /etc/cryptsetup-keys.d/cryptroot.key luks,discard" > /etc/crypttab
    
    # Configure initramfs
    echo "KEYFILE_PATTERN=\"/etc/cryptsetup-keys.d/*.key\"" >> /etc/cryptsetup-initramfs/conf-hook
    echo "UMASK=0077" >> /etc/initramfs-tools/initramfs.conf
    
    # Configure GRUB
    echo "GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=\`lsb_release -i -s 2> /dev/null || echo Debian\`
GRUB_CMDLINE_LINUX_DEFAULT=\"quiet\"
GRUB_CMDLINE_LINUX=\"cryptdevice=UUID=$ROOT_UUID:cryptroot root=/dev/mapper/cryptroot\"
GRUB_ENABLE_CRYPTODISK=y
GRUB_PRELOAD_MODULES=\"part_gpt cryptodisk luks\"" > /etc/default/grub
    
    # Update initramfs
    update-initramfs -v -u -k all
else
    # Non-LUKS GRUB configuration
    echo "GRUB_DEFAULT=0
GRUB_TIMEOUT=5
GRUB_DISTRIBUTOR=\`lsb_release -i -s 2> /dev/null || echo Debian\`
GRUB_CMDLINE_LINUX_DEFAULT=\"quiet\"
GRUB_CMDLINE_LINUX=\"root=UUID=$ROOT_UUID\"
GRUB_ENABLE_CRYPTODISK=n" > /etc/default/grub
fi

# Install and configure GRUB with crypto modules
grub-install --target=x86_64-efi \
             --efi-directory=/boot/efi \
             --bootloader-id=GRUB \
             --modules="part_gpt cryptodisk luks" \
             --recheck

update-grub
update-initramfs -v -u -k all

# Create manual EFI boot entry if needed
if [ -d /sys/firmware/efi ]; then
    efibootmgr --create --disk $(echo $ROOT_PART | sed 's/[0-9]*$//') \
               --part ${ROOT_PART: -1} \
               --loader /EFI/GRUB/grubx64.efi \
               --label "GRUB" 2>/dev/null || true
fi

# Set root password
echo "Set root password:"
passwd

# Clean up
[ -f /chroot_install.sh ] && rm /chroot_install.sh
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

# Clean up mounts
umount -R /mnt
[[ "$USE_LUKS" == "y" ]] && cryptsetup close cryptroot

echo "Installation complete! Reboot into your new system."
