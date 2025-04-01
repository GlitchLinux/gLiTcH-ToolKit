#!/bin/bash

# Enhanced Debian Installation Script with Chroot Setup
# This script automates disk partitioning, filesystem setup, system copying, and prepares a chroot configuration script

# ========== CONFIGURATION ==========
# Set strict mode for better error handling
set -o errexit  # Exit on error
set -o nounset  # Exit on unset variables
set -o pipefail # Catch pipe failures

# Define colors for output
COLOR_RED='\033[0;31m'
COLOR_GREEN='\033[0;32m'
COLOR_YELLOW='\033[1;33m'
COLOR_NC='\033[0m'

# ========== DEPENDENCY CHECK ==========
echo "Checking for required packages..."
REQUIRED_PKGS=("rsync" "gdisk" "dosfstools" "cryptsetup" "coreutils" "util-linux")
MISSING_PKGS=()

for pkg in "${REQUIRED_PKGS[@]}"; do
    if ! dpkg -s "$pkg" &> /dev/null; then
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo "The following required packages are missing:"
    printf '%s\n' "${MISSING_PKGS[@]}"
    read -p "Would you like to install them now? (y/N): " INSTALL_MISSING
    if [[ "${INSTALL_MISSING,,}" == "y" ]]; then
        apt-get update
        apt-get install -y "${MISSING_PKGS[@]}"
    else
        echo "Cannot proceed without required packages. Exiting."
        exit 1
    fi
fi

# ========== PRIVILEGE CHECK ==========
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root. Use sudo or log in as root."
    exit 1
fi

# ========== UEFI CHECK ==========
if [[ ! -d /sys/firmware/efi ]]; then
    echo "ERROR: This script requires UEFI boot mode. Legacy BIOS is not supported."
    exit 1
fi

# ========== CLEANUP FUNCTION ==========
cleanup() {
    echo "Performing cleanup..."
    umount -R /mnt/boot/efi 2>/dev/null || true
    umount -R /mnt 2>/dev/null || true
    cryptsetup close cryptroot 2>/dev/null || true
    echo "Cleanup complete."
}

# ========== DISK SELECTION ==========
echo "Available disks:"
lsblk -o NAME,SIZE,TYPE,MOUNTPOINTS
read -p "Enter the target disk (e.g., /dev/nvme0n1): " TARGET_DISK

# Verify disk exists
if [[ ! -b "$TARGET_DISK" ]]; then
    echo "ERROR: $TARGET_DISK is not a valid block device."
    exit 1
fi

# Confirm disk selection
echo -e "\nWARNING: ALL DATA ON $TARGET_DISK WILL BE PERMANENTLY ERASED!"
read -p "Are you absolutely sure you want to continue? (type 'YES' to confirm): " confirm
if [[ "${confirm}" != "YES" ]]; then
    echo "Installation aborted by user."
    exit 0
fi

# ========== PARTITION CONFIGURATION ==========
read -p "Enter a name for the root partition (default: 'root'): " PART_NAME
PART_NAME=${PART_NAME:-root}

read -p "Enable LUKS encryption for the root partition? [y/N]: " USE_LUKS
USE_LUKS=${USE_LUKS,,}

# ========== PARTITIONING ==========
echo -e "\n=== PARTITIONING $TARGET_DISK ==="
echo "Creating GPT partition table and partitions..."

# Clear existing partitions and create new ones
sgdisk --zap-all "$TARGET_DISK"
sgdisk --clear \
       --new=1:0:+512M --typecode=1:ef00 --change-name=1:EFI \
       --new=2:0:0 --typecode=2:8300 --change-name=2:"$PART_NAME" \
       "$TARGET_DISK"

# Refresh partition table
partprobe "$TARGET_DISK"
sleep 2  # Allow time for partition table to update

# ========== FILESYSTEM SETUP ==========
echo -e "\n=== CREATING FILESYSTEMS ==="

# EFI Partition
EFI_PART="${TARGET_DISK}1"
echo "Formatting EFI partition ($EFI_PART) as FAT32..."
mkfs.vfat -F32 -n EFI "$EFI_PART"

# Root Partition
ROOT_PART="${TARGET_DISK}2"
if [[ "$USE_LUKS" == "y" ]]; then
    echo -e "\n=== LUKS ENCRYPTION SETUP ==="
    echo "Encrypting root partition ($ROOT_PART)..."
    cryptsetup luksFormat --type luks2 --verify-passphrase "$ROOT_PART"
    cryptsetup open "$ROOT_PART" cryptroot
    ROOT_DEVICE="/dev/mapper/cryptroot"
    # Create crypttab entry
    echo "cryptroot UUID=$(blkid -s UUID -o value "$ROOT_PART") none luks,discard" > /mnt/etc/crypttab
else
    ROOT_DEVICE="$ROOT_PART"
fi

echo "Formatting root partition ($ROOT_DEVICE) as ext4..."
mkfs.ext4 -L "$PART_NAME" "$ROOT_DEVICE"

# ========== MOUNTING ==========
echo -e "\n=== MOUNTING PARTITIONS ==="
mount "$ROOT_DEVICE" /mnt
mkdir -p /mnt/boot/efi
mount "$EFI_PART" /mnt/boot/efi

# ========== SYSTEM COPY ==========
echo -e "\n=== COPYING SYSTEM TO TARGET ==="
rsync -aAXH --info=progress2 \
      --exclude="/dev/*" --exclude="/proc/*" --exclude="/sys/*" --exclude="/tmp/*" \
      --exclude="/run/*" --exclude="/mnt/*" --exclude="/media/*" --exclude="/lost+found" \
      / /mnt/

# ========== GENERATE FSTAB ==========
echo -e "\nGenerating /etc/fstab..."
{
    echo "# /etc/fstab: static file system information"
    echo "#"
    echo "# Systemd mounts some paths by default. See:"
    echo "#   man 5 systemd.mount"
    echo "#   man 7 file-hierarchy"
    echo "#"
    echo "# <file system> <mount point> <type> <options> <dump> <pass>"
    
    # Root partition
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_DEVICE")
    echo "UUID=$ROOT_UUID / ext4 defaults,noatime 0 1"
    
    # EFI partition
    EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
    echo "UUID=$EFI_UUID /boot/efi vfat umask=0077 0 1"
} > /mnt/etc/fstab

echo -e "\nGenerated /etc/fstab:"
cat /mnt/etc/fstab

# ========== CHROOT SETUP SCRIPT ==========
echo -e "\n=== CREATING CHROOT SETUP SCRIPT ==="
cat > /mnt/chroot_setup.sh <<EOF
#!/bin/bash
set -euo pipefail

# Use the predefined colors
RED='${COLOR_RED}'
GREEN='${COLOR_GREEN}'
YELLOW='${COLOR_YELLOW}'
NC='${COLOR_NC}'

echo -e "\${GREEN}=== CHROOT CONFIGURATION SCRIPT ===\${NC}"
echo "This script will help configure your newly installed system."

# Basic system configuration
configure_system() {
    echo -e "\n\${YELLOW}=== SYSTEM CONFIGURATION ===\${NC}"
    
    # Set hostname
    read -p "Enter hostname for this system: " hostname
    echo "\$hostname" > /etc/hostname
    
    # Set timezone
    echo -e "\nSetting timezone..."
    dpkg-reconfigure tzdata
    
    # Configure locales
    echo -e "\nConfiguring locales..."
    dpkg-reconfigure locales
    
    # Configure keyboard
    echo -e "\nConfiguring keyboard..."
    dpkg-reconfigure keyboard-configuration
}

# Install and configure bootloader
configure_bootloader() {
    echo -e "\n\${YELLOW}=== BOOTLOADER CONFIGURATION ===\${NC}"
    
    # Check if GRUB is installed
    if ! command -v grub-install &> /dev/null; then
        echo -e "\${RED}GRUB not found! Installing...\${NC}"
        apt-get update
        apt-get install -y grub-efi
    fi
    
    # Install GRUB
    echo -e "\nInstalling GRUB bootloader..."
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Debian --recheck
    
    # Update GRUB configuration
    echo -e "\nUpdating GRUB configuration..."
    update-grub
    
    # If using LUKS, add cryptsetup to initramfs
    if grep -q 'cryptroot' /etc/crypttab 2>/dev/null; then
        echo -e "\n\${YELLOW}Configuring encrypted boot...\${NC}"
        apt-get install -y cryptsetup-initramfs
        update-initramfs -u -k all
    fi
}

# User management
configure_users() {
    echo -e "\n\${YELLOW}=== USER CONFIGURATION ===\${NC}"
    
    # Set root password
    echo -e "\nSetting root password:"
    passwd
    
    # Create regular user
    read -p "Would you like to create a regular user? [y/N]: " create_user
    if [[ "\${create_user,,}" == "y" ]]; then
        read -p "Enter username: " username
        adduser "\$username"
        
        # Add to sudo group if exists
        if grep -q '^sudo:' /etc/group; then
            usermod -aG sudo "\$username"
            echo -e "\${GREEN}User \$username created and added to sudo group.\${NC}"
        else
            echo -e "\${YELLOW}Warning: sudo group not found. User created without sudo privileges.\${NC}"
        fi
    fi
}

# Network configuration
configure_network() {
    echo -e "\n\${YELLOW}=== NETWORK CONFIGURATION ===\${NC}"
    
    # Check if system uses NetworkManager
    if systemctl list-unit-files | grep -q NetworkManager; then
        echo -e "NetworkManager detected. Would you like to configure networking now?"
        echo -e "You can configure networking later with 'nmtui' or 'nmcli'."
    else
        echo -e "Would you like to install and configure NetworkManager for easier networking?"
        read -p "Install NetworkManager? [y/N]: " install_nm
        if [[ "\${install_nm,,}" == "y" ]]; then
            apt-get install -y network-manager
            systemctl enable NetworkManager
            systemctl start NetworkManager
        fi
    fi
}

# Main execution
main() {
    configure_system
    configure_bootloader
    configure_users
    configure_network
    
    echo -e "\n\${GREEN}=== CHROOT CONFIGURATION COMPLETE ===\${NC}"
    echo -e "You can now exit the chroot environment with 'exit' or Ctrl+D"
    echo -e "After exiting, don't forget to reboot your system."
}

main
EOF

chmod +x /mnt/chroot_setup.sh

# ========== FINAL INSTRUCTIONS ==========
# Copy DNS configuration to ensure internet access in chroot
cp -L /etc/resolv.conf /mnt/etc/resolv.conf

# Mount necessary filesystems for chroot
mount --bind /dev /mnt/dev
mount --bind /proc /mnt/proc
mount --bind /sys /mnt/sys
mount --bind /dev/pts /mnt/dev/pts

echo -e "\n${COLOR_GREEN}=== INSTALLATION COMPLETE ===${COLOR_NC}"
echo -e "The system has been copied to the target disk and is ready for configuration."
echo -e "\nTo complete the setup:"
echo -e "1. Enter the chroot environment with:"
echo -e "   ${COLOR_YELLOW}chroot /mnt /bin/bash${COLOR_NC}"
echo -e "2. Run the configuration script:"
echo -e "   ${COLOR_YELLOW}/chroot_setup.sh${COLOR_NC}"
echo -e "3. Follow the interactive prompts to configure your system"
echo -e "4. When finished, exit the chroot with 'exit' or Ctrl+D"
echo -e "\nAfter exiting chroot, you may need to manually clean up:"
echo -e "  ${COLOR_YELLOW}umount -R /mnt/dev /mnt/proc /mnt/sys${COLOR_NC}"
echo -e "  ${COLOR_YELLOW}umount -R /mnt/boot/efi${COLOR_NC}"
echo -e "  ${COLOR_YELLOW}umount /mnt${COLOR_NC}"
[[ "$USE_LUKS" == "y" ]] && echo -e "  ${COLOR_YELLOW}cryptsetup close cryptroot${COLOR_NC}"
echo -e "  ${COLOR_YELLOW}reboot${COLOR_NC}"
echo -e "\nAfter rebooting, remove the installation media to boot into your new system."
