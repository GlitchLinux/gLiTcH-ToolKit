#!/bin/bash

# Enhanced Debian to gLiTcH Linux Converter
# This script converts a running Debian installation to gLiTcH Linux KDE v27.0
# WARNING: This script modifies system files and should be used with caution

set -e  # Exit immediately if a command exits with a non-zero status
set -o pipefail  # Return value of a pipeline is the value of the last command to exit with non-zero status

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function for logging
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}"
}

# Function for warnings
warn() {
    echo -e "${YELLOW}[WARNING] $1${NC}" >&2
}

# Function for errors
error() {
    echo -e "${RED}[ERROR] $1${NC}" >&2
    exit 1
}

# Check if script is run as root
if [ "$(id -u)" != "0" ]; then
    error "This script must be run as root"
fi

# Install dependencies
log "Installing required dependencies..."
apt update && apt install -y sudo bash wget rsync mount util-linux squashfs-tools coreutils dpkg apt initramfs-tools grub-common grep sed tar pciutils mokutil cryptsetup git

# Check for required tools
for cmd in wget rsync mount umount mktemp unsquashfs md5sum dpkg apt update-initramfs update-grub git; do
    if ! command -v $cmd &> /dev/null; then
        error "$cmd is required but not installed. Please install it and try again."
    fi
done

# Configuration variables
SQUASHFS_URL="https://glitchlinux.wtf/ipxe/gLiTcH-KDE-v27/live/filesystem.squashfs"
SQUASHFS_FILE="/tmp/gLiTcH-filesystem-v27.squashfs"
ISO_MOUNT="/mnt/glitch-iso"
SQUASHFS_MOUNT="/mnt/glitch-squashfs"
TEMP_DIR=$(mktemp -d)
BACKUP_DIR="/root/debian-backup-$(date +%Y%m%d%H%M%S)"
PACKAGE_LIST_FILE="$TEMP_DIR/glitch-packages.list"
CURRENT_PACKAGE_LIST="$TEMP_DIR/current-packages.list"
NEW_USER="x"
NEW_HOSTNAME="gLiTcH"
LOGFILE="/var/log/glitch-conversion.log"

# Prompt for new password
read -sp "Enter new password for user '$NEW_USER': " NEW_PASSWORD
echo ""

# Create required directories
mkdir -p "$ISO_MOUNT" "$SQUASHFS_MOUNT" "$BACKUP_DIR"

# Start logging to file
exec &> >(tee -a "$LOGFILE")

# Function to clean up on exit
cleanup() {
    local exit_status=$?
    log "Cleaning up..."
    
    # Kill background processes
    if [ -n "$BACKUP_PID" ] && ps -p $BACKUP_PID > /dev/null; then
        kill $BACKUP_PID 2>/dev/null || true
    fi
    
    # Unmount filesystems if mounted
    if mountpoint -q "$SQUASHFS_MOUNT" 2>/dev/null; then
        umount "$SQUASHFS_MOUNT" || warn "Failed to unmount $SQUASHFS_MOUNT"
    fi
    if mountpoint -q "$ISO_MOUNT" 2>/dev/null; then
        umount "$ISO_MOUNT" || warn "Failed to unmount $ISO_MOUNT"
    fi
    
    # Remove temporary directory
    rm -rf "$TEMP_DIR"
    
    # Clean up downloaded squashfs
    if [ -f "$SQUASHFS_FILE" ]; then
        rm -f "$SQUASHFS_FILE"
    fi
    
    if [ $exit_status -ne 0 ]; then
        echo -e "${RED}Script execution failed. Check the log file at $LOGFILE for details.${NC}"
    fi
    
    log "Cleanup completed."
}

# Set trap for cleanup on script exit
trap cleanup EXIT INT TERM

# Function to backup a system file before modifying
backup_file() {
    local file="$1"
    if [ -f "$file" ] || [ -d "$file" ]; then
        local backup_path="$BACKUP_DIR$file"
        mkdir -p "$(dirname "$backup_path")"
        cp -a "$file" "$backup_path" || warn "Failed to backup $file"
        log "Backed up: $file"
    fi
}

# Function to check disk space
check_disk_space() {
    log "Checking disk space..."
    
    # Get available space in root partition (in KB)
    local available_space=$(df -k / | awk 'NR==2 {print $4}')
    # Required space in KB (8GB for extraction buffer)
    local required_space=8388608  # 8GB in KB
    
    if [ "$available_space" -lt "$required_space" ]; then
        error "Not enough disk space. At least 8GB required, but only $(($available_space / 1024))MB available."
    fi
    log "Disk space check passed."
}

# Function to verify system compatibility
check_compatibility() {
    log "Checking system compatibility..."
    
    # Check if running on Debian or derivative
    if [ ! -f /etc/debian_version ]; then
        error "This script is designed to run on Debian-based systems only."
    fi
    
    # Check kernel version
    local kernel_version=$(uname -r)
    log "Current kernel version: $kernel_version"
    
    # Check architecture
    local arch=$(dpkg --print-architecture)
    if [ "$arch" != "amd64" ]; then
        warn "This script is designed for 64-bit systems. Your system is $arch. Proceeding anyway, but this might cause issues."
    fi
    
    # Check if system is encrypted
    if grep -q "cryptroot" /proc/cmdline; then
        warn "Encrypted system detected. Extra care will be taken with crypttab and initramfs."
        touch "$TEMP_DIR/encrypted_system"
    fi
    
    log "System compatibility check completed."
}

# Function to create a recovery script
create_recovery_script() {
    local recovery_script="$BACKUP_DIR/recovery.sh"
    
    cat > "$recovery_script" << 'EOL'
#!/bin/bash
# Recovery script for gLiTcH Linux conversion
# This script can be used to restore the system to its pre-conversion state

echo "gLiTcH Linux Conversion Recovery Script"
echo "========================================"
echo ""
echo "This script will restore your system to its pre-conversion state."
echo "WARNING: This will undo all changes made by the gLiTcH Linux conversion script."
echo ""

read -p "Are you sure you want to restore your system? (yes/no): " response
if [ "$response" != "yes" ]; then
    echo "Recovery cancelled."
    exit 0
fi

BACKUP_DIR="$(dirname "$(readlink -f "$0")")"

# Restore /etc
if [ -d "$BACKUP_DIR/etc" ]; then
    echo "Restoring /etc..."
    rsync -av --delete "$BACKUP_DIR/etc/" /etc/
fi

# Restore /usr/local
if [ -d "$BACKUP_DIR/usr/local" ]; then
    echo "Restoring /usr/local..."
    rsync -av --delete "$BACKUP_DIR/usr/local/" /usr/local/
fi

# Restore /var
if [ -d "$BACKUP_DIR/var" ]; then
    echo "Restoring /var..."
    rsync -av --delete "$BACKUP_DIR/var/" /var/
fi

# Restore /root
if [ -d "$BACKUP_DIR/root" ]; then
    echo "Restoring /root..."
    rsync -av --delete "$BACKUP_DIR/root/" /root/
fi

# Update GRUB
echo "Updating GRUB..."
update-grub

# Update initramfs
echo "Updating initramfs..."
update-initramfs -u -k all

echo ""
echo "Recovery complete. Please reboot your system."
echo "It's recommended to boot from the backup of /etc before making any critical changes."

EOL
    
    chmod +x "$recovery_script"
    log "Recovery script created: $recovery_script"
}

# Function to update boot configuration
update_boot_configuration() {
    log "Updating boot configuration..."
    
    # Update initramfs
    if ! update-initramfs -v -u -k all 2>&1 | tee -a "$LOGFILE"; then
        warn "Initramfs update encountered issues. Marking for retry."
        touch "$TEMP_DIR/initramfs_issues"
    fi
    
    # Update GRUB
    if ! update-grub 2>&1 | tee -a "$LOGFILE"; then
        warn "GRUB update encountered issues. Marking for retry."
        touch "$TEMP_DIR/grub_update_needed"
    fi
    
    log "Boot configuration update completed."
}

# Function to get package list from squashfs
get_package_list_from_squashfs() {
    log "Extracting package list from gLiTcH Linux..."
    
    if [ -f "$SQUASHFS_MOUNT/var/lib/dpkg/status" ]; then
        grep "^Package:" "$SQUASHFS_MOUNT/var/lib/dpkg/status" | awk '{print $2}' > "$PACKAGE_LIST_FILE"
        log "Extracted $(wc -l < "$PACKAGE_LIST_FILE") packages from gLiTcH Linux"
    else
        warn "Could not find package list in squashfs mount"
        touch "$PACKAGE_LIST_FILE"
    fi
}

# Function to install packages
install_packages() {
    log "Installing gLiTcH Linux packages..."
    
    local total_packages=$(wc -l < "$PACKAGE_LIST_FILE")
    local installed=0
    local failed=0
    
    while IFS= read -r package; do
        ((installed++))
        # Show progress
        if [ $((installed % 50)) -eq 0 ]; then
            log "Progress: $installed/$total_packages packages processed"
        fi
        
        # Check if package is available in current repos
        if apt-cache search "^$package$" &>/dev/null; then
            # Install silently, continue on failure
            apt-get install -y "$package" &>/dev/null || ((failed++))
        fi
    done < "$PACKAGE_LIST_FILE"
    
    log "Package installation completed. Installed: $((total_packages - failed)), Failed: $failed"
}

# Main conversion process
main() {
    log "=== Starting gLiTcH Linux Conversion ==="
    
    # Run compatibility checks
    check_compatibility
    check_disk_space
    
    # Create recovery script
    create_recovery_script
    
    # Backup critical system files
    log "Backing up system files..."
    backup_file "/etc/hostname"
    backup_file "/etc/hosts"
    backup_file "/etc/fstab"
    backup_file "/etc/default/grub"
    backup_file "/etc/skel"
    backup_file "/root/.bashrc"
    backup_file "/root/.bash_profile"
    
    # Download squashfs
    log "Downloading gLiTcH Linux v27 squashfs..."
    if ! wget -q --show-progress "$SQUASHFS_URL" -O "$SQUASHFS_FILE"; then
        error "Failed to download squashfs. Check your internet connection."
    fi
    
    if [ ! -f "$SQUASHFS_FILE" ]; then
        error "Squashfs file not found after download"
    fi
    
    log "Downloaded: $SQUASHFS_FILE ($(du -h "$SQUASHFS_FILE" | cut -f1))"
    
    # Mount squashfs
    log "Mounting squashfs..."
    if ! mount -t squashfs "$SQUASHFS_FILE" "$SQUASHFS_MOUNT"; then
        error "Failed to mount squashfs"
    fi
    
    # Extract package list
    get_package_list_from_squashfs
    
    # Install packages
    log "Installing packages from gLiTcH Linux v27..."
    install_packages
    
    # Set hostname
    log "Setting hostname to $NEW_HOSTNAME..."
    echo "$NEW_HOSTNAME" > /etc/hostname
    sed -i "s/127.0.1.1.*/127.0.1.1\t$NEW_HOSTNAME/" /etc/hosts
    
    # Create or update user
    log "Setting up user $NEW_USER..."
    if id "$NEW_USER" &>/dev/null; then
        # User exists, update password
        echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
    else
        # Create new user
        useradd -m -s /bin/bash "$NEW_USER"
        echo "$NEW_USER:$NEW_PASSWORD" | chpasswd
        # Add user to sudo group and other important groups
        usermod -aG sudo,adm,audio,video,plugdev,netdev "$NEW_USER"
    fi
    
    # Enhanced KDE Plasma configuration
    if [ -d "$SQUASHFS_MOUNT/usr/share/plasma" ] || [ -d "$SQUASHFS_MOUNT/usr/share/kde" ]; then
        log "Setting up KDE Plasma environment..."
        
        # 1. Copy system-wide KDE configurations
        if [ -d "$SQUASHFS_MOUNT/etc/skel" ]; then
            log "Copying system-wide KDE configurations..."
            rsync -a "$SQUASHFS_MOUNT/etc/skel/." "/etc/skel/"
        fi
        
        # 2. Copy user-specific configurations
        log "Setting up user $NEW_USER's KDE environment..."
        mkdir -p "/home/$NEW_USER/.config"
        mkdir -p "/home/$NEW_USER/.local/share"
        
        if [ -d "$SQUASHFS_MOUNT/etc/skel/.config" ]; then
            rsync -a "$SQUASHFS_MOUNT/etc/skel/.config/." "/home/$NEW_USER/.config/"
        fi
        
        if [ -d "$SQUASHFS_MOUNT/etc/skel/.local/share" ]; then
            rsync -a "$SQUASHFS_MOUNT/etc/skel/.local/share/." "/home/$NEW_USER/.local/share/"
        fi
        
        # 3. Copy global KDE settings
        if [ -d "$SQUASHFS_MOUNT/usr/share/plasma" ]; then
            log "Copying global Plasma settings..."
            rsync -a "$SQUASHFS_MOUNT/usr/share/plasma/." "/usr/share/plasma/"
        fi
        
        if [ -d "$SQUASHFS_MOUNT/usr/share/kde" ]; then
            log "Copying KDE resources..."
            rsync -a "$SQUASHFS_MOUNT/usr/share/kde/." "/usr/share/kde/"
        fi
        
        # 4. Copy wallpapers and themes
        if [ -d "$SQUASHFS_MOUNT/usr/share/wallpapers" ]; then
            log "Copying wallpapers..."
            rsync -a "$SQUASHFS_MOUNT/usr/share/wallpapers/." "/usr/share/wallpapers/"
        fi
        
        if [ -d "$SQUASHFS_MOUNT/usr/share/themes" ]; then
            log "Copying themes..."
            rsync -a "$SQUASHFS_MOUNT/usr/share/themes/." "/usr/share/themes/"
        fi
        
        # 5. Copy icons
        if [ -d "$SQUASHFS_MOUNT/usr/share/icons" ]; then
            log "Copying icons..."
            rsync -a "$SQUASHFS_MOUNT/usr/share/icons/." "/usr/share/icons/"
        fi
        
        # 6. Fix permissions
        chown -R "$NEW_USER:$NEW_USER" "/home/$NEW_USER"
        log "KDE Plasma environment setup completed."
    fi
    
    # Manually apply gLiTcH theme if lookandfeeltool isn't available
    if [ -f "/usr/share/plasma/look-and-feel/org.gLiTcH.desktop/contents/defaults" ]; then
        log "Manually applying gLiTcH theme..."
        
        # Create plasma config file if it doesn't exist
        PLASMA_CONFIG="/home/$NEW_USER/.config/plasmarc"
        mkdir -p "/home/$NEW_USER/.config"
        
        cat > "$PLASMA_CONFIG" << EOF
[Theme]
name=org.gLiTcH.desktop
EOF
        
        # Also set in kdeglobals
        KDE_GLOBALS="/home/$NEW_USER/.config/kdeglobals"
        if [ -f "$KDE_GLOBALS" ]; then
            sed -i 's/^Name=.*/Name=org.gLiTcH.desktop/' "$KDE_GLOBALS"
        else
            echo "[KDE]" > "$KDE_GLOBALS"
            echo "LookAndFeelPackage=org.gLiTcH.desktop" >> "$KDE_GLOBALS"
        fi
        
        chown "$NEW_USER:$NEW_USER" "$PLASMA_CONFIG" "$KDE_GLOBALS"
    fi
    
    # Update boot configuration
    update_boot_configuration
    
    # Fix any known issues
    log "Performing final system fixes..."
    
    # Fix permissions on critical directories
    chmod 755 /
    chmod 755 /usr
    chmod 755 /etc
    chmod 1777 /tmp
    
    # Update system cache
    log "Updating system cache..."
    ldconfig
    
    # Re-run any pending operations marked earlier
    if [ -f "$TEMP_DIR/grub_update_needed" ]; then
        log "Re-running GRUB update..."
        update-grub || warn "GRUB update failed again. You may need to fix this manually after reboot."
    fi
    
    if [ -f "$TEMP_DIR/initramfs_issues" ]; then
        log "Attempting additional initramfs fixes..."
        update-initramfs -v -u -k all || warn "Initramfs update is still having issues. Check the log for details."
    fi
    
    # Create a post-installation script that runs on first boot
    log "Creating post-installation script..."
    cat > /usr/local/sbin/glitch-post-install.sh << "EOF"
#!/bin/bash
# gLiTcH Linux post-installation script
# This will run on first boot to fix any remaining issues

# Update package database
apt-get update

# Fix any broken dependencies
apt-get -f install

# Update the system
apt-get upgrade

# Remove this script so it doesn't run again
rm -f /etc/rc.local
rm -f /usr/local/sbin/glitch-post-install.sh
EOF
    
    chmod +x /usr/local/sbin/glitch-post-install.sh
    
    # Create rc.local to run the post-install script if it doesn't exist
    if [ ! -f "/etc/rc.local" ]; then
        cat > /etc/rc.local << "EOF"
#!/bin/bash
/usr/local/sbin/glitch-post-install.sh &
exit 0
EOF
        chmod +x /etc/rc.local
    fi
    
    log "=== Installation Complete ==="
    log "Your system has been converted to gLiTcH Linux KDE v27"
    log "A backup of critical system files has been saved to $BACKUP_DIR"
    log "A recovery script has been created at $BACKUP_DIR/recovery.sh"
    echo -e "${GREEN}  ${NC}"
    echo -e "${GREEN}  ${NC}"
    echo -e "${GREEN}  ${NC}"
    echo -e "${GREEN}      _____     ____         ____  _________________       _____    ____   ____${NC}"
    echo -e "${GREEN}  ___|\    \   |    |       |    |/                 \  ___|\    \  |    | |    |${NC}"
    echo -e "${GREEN} /    /\    \  |    |       |    |\______     ______/ /    /\    \ |    | |    |${NC}"
    echo -e "${GREEN}|    |  |____| |    |       |    |   \( /    /  )/   |    |  |    ||    |_|    |${NC}"
    echo -e "${GREEN}|    |    ____ |    |  ____ |    |    ' |   |   '    |    |  |____||    .-.    |${NC}"
    echo -e "${GREEN}|    |   |    ||    | |    ||    |      |   |        |    |   ____ |    | |    |${NC}"
    echo -e "${GREEN}|    |   |_,  ||    | |    ||    |     /   //        |    |  |    ||    | |    |${NC}"
    echo -e "${GREEN}|\ ___\___/  /||____|/____/||____|    /___//         |\ ___\/    /||____| |____|${NC}"
    echo -e "${GREEN}| |   /____ / ||    |     |||    |   |    |          | |   /____/ ||    | |    |${NC}"
    echo -e "${GREEN} \|___|    | / |____|_____|/|____|   |____|           \|___|    | /|____| |____|${NC}"
    echo -e "${GREEN}   \( |____|/    \(    )/     \(       \(               \( |____|/   \(     )/${NC}"  
    echo -e "${GREEN}    '   )/        '    '       '        '                '   )/       '     '${NC}"                     
    echo -e "${GREEN}       ____         ____  _____   ______    ____   ____ ____        _____  ${NC}"                         
    echo -e "${GREEN}      |    |       |    ||\    \ |\     \  |    | |    |    \      /    /${NC}"        
    echo -e "${GREEN}      |    |       |    | \\    \| \     \ |    | |    |\    \    /    /${NC}"        
    echo -e "${GREEN}      |    |       |    |  \|    \  \     ||    | |    | \    \  /    /${NC}"         
    echo -e "${GREEN}      |    |  ____ |    |   |     \  |    ||    | |    |  \--  \/  --/${NC}"          
    echo -e "${GREEN}      |    | |    ||    |   |      \ |    ||    | |    |  /    /\    \ ${NC}"          
    echo -e "${GREEN}      |    | |    ||    |   |    |\ \|    ||    | |    | /    /  \    \ ${NC}"         
    echo -e "${GREEN}      |____|/____/||____|   |____||\_____/||\___\_|____|/____/ /\ \____\ ${NC}"        
    echo -e "${GREEN}      |    |     |||    |   |    |/ \|   ||| |    |    ||    |/  \|    |${NC}"        
    echo -e "${GREEN}      |____|_____|/|____|   |____|   |___|/ \|____|____||____|    |____|${NC}"        
    echo -e "${GREEN}        \(    )/     \(       \(       )/      \(   )/    \(        )/${NC}"          
    echo -e "${GREEN}         '    '       '        '       '        '   '      '        '${NC}"           
    echo -e "${GREEN}                                                                   ${NC}"
    echo -e "${YELLOW}                   |  SYSTEM HAS BEEN CONVERTED! |${NC}"
    echo -e "${YELLOW}                   | https://www.glitchlinux.com | ${NC}"
    echo -e "${YELLOW}                   |         REBOOT NOW          | ${NC}"
    echo -e "${GREEN}  ${NC}"
    echo -e "${GREEN}  ${NC}"
    echo -e "${YELLOW}It's recommended to reboot your system to complete the installation.${NC}"
    echo -e "${YELLOW}If something goes wrong on boot, you can use a live CD/USB to run the recovery script.${NC}"
    read -p "Do you want to reboot now? (y/n): " reboot_confirm
    if [[ "$reboot_confirm" == "y" || "$reboot_confirm" == "Y" ]]; then
        log "Rebooting..."
        sleep 3
        reboot
    fi
}

# Run main function
main

exit 0
