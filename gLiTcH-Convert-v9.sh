
#!/bin/bash

# Enhanced Debian to gLiTcH Linux Converter
# This script converts a running Debian installation to gLiTcH Linux KDE v9.0
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

#Install "sudo" - required if its a fresh debian netinstall.
apt update && apt install sudo

#Install dependencies
sudo apt install -y bash wget rsync mount util-linux squashfs-tools coreutils dpkg apt initramfs-tools grub-common grep sed tar pciutils mokutil cryptsetup

# Check for required tools
for cmd in wget rsync mount umount mktemp unsquashfs md5sum dpkg apt update-initramfs update-grub; do
    if ! command -v $cmd &> /dev/null; then
        error "$cmd is required but not installed. Please install it and try again."
    fi
done

# Configuration variables
ISO_URL="https://glitchlinux.wtf/gLiTcH-Linux-KDE-v9.0.iso"
ISO_FILE="/tmp/glitch-linux.iso"
ISO_MOUNT="/mnt/glitch-iso"
SQUASHFS_MOUNT="/mnt/glitch-squashfs"
TEMP_DIR=$(mktemp -d)
BACKUP_DIR="/root/debian-backup-$(date +%Y%m%d%H%M%S)"
PACKAGE_LIST_FILE="$TEMP_DIR/glitch-packages.list"
CURRENT_PACKAGE_LIST="$TEMP_DIR/current-packages.list"
NEW_USER="x"
NEW_PASSWORD="9880"
NEW_HOSTNAME="gLiTcH"
LOGFILE="/var/log/glitch-conversion.log"

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
    # ISO size in KB (assuming 4GB max)
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
    
    cat > "$recovery_script" << EOL
#!/bin/bash
# Recovery script for gLiTcH Linux conversion
# This script will attempt to restore your system to its previous state

if [ "\$(id -u)" != "0" ]; then
    echo "This script must be run as root" 1>&2
    exit 1
fi

echo "Restoring system files from backup at $BACKUP_DIR..."
cp -a $BACKUP_DIR/etc/fstab /etc/fstab
cp -a $BACKUP_DIR/etc/crypttab /etc/crypttab 2>/dev/null || true
cp -a $BACKUP_DIR/etc/passwd /etc/passwd
cp -a $BACKUP_DIR/etc/shadow /etc/shadow
cp -a $BACKUP_DIR/etc/group /etc/group
cp -a $BACKUP_DIR/etc/hostname /etc/hostname
cp -a $BACKUP_DIR/etc/hosts /etc/hosts

echo "Restoring GRUB configuration..."
if [ -d $BACKUP_DIR/etc/default/grub ]; then
    cp -a $BACKUP_DIR/etc/default/grub /etc/default/
    update-grub
fi

echo "Updating initramfs..."
update-initramfs -u

echo "Recovery completed. Please reboot your system."
EOL

    chmod +x "$recovery_script"
    log "Created recovery script at $recovery_script"
}

# Function to handle package management
handle_packages() {
    log "Starting package management process..."
    
    # Create a list of currently installed packages
    dpkg --get-selections > "$CURRENT_PACKAGE_LIST"
    
    # Create a list of packages from gLiTcH Linux
    if [ -d "$SQUASHFS_MOUNT/var/lib/dpkg" ]; then
        DPKG_ADMINDIR="$SQUASHFS_MOUNT/var/lib/dpkg" dpkg --get-selections > "$PACKAGE_LIST_FILE"
    else
        warn "Cannot determine packages from gLiTcH Linux. Package integration may be incomplete."
        return 1
    fi
    
    # Get list of essential packages that should not be removed
    local essential_packages=$(dpkg-query -W -f='${Package} ${Essential}\n' | grep "yes" | cut -d' ' -f1)
    
    log "Found $(wc -l < "$PACKAGE_LIST_FILE") packages in gLiTcH Linux"
    log "Found $(wc -l < "$CURRENT_PACKAGE_LIST") packages in current system"
    
    # Keep a list of essential packages for reference
    echo "$essential_packages" > "$TEMP_DIR/essential-packages.list"
    
    # Handle package database replacement
    log "Backing up package database..."
    cp -a /var/lib/dpkg "$BACKUP_DIR/var/lib/"
    cp -a /var/lib/apt "$BACKUP_DIR/var/lib/"
    
    log "Package management process completed."
}

# Function to handle special cases
handle_special_cases() {
    log "Handling special cases..."
    
    # Handle encrypted system
    if [ -f "$TEMP_DIR/encrypted_system" ]; then
        log "Handling encrypted system configuration..."
        
        # Ensure cryptsetup is installed
        if [ -f "$SQUASHFS_MOUNT/usr/sbin/cryptsetup" ]; then
            cp -a "$SQUASHFS_MOUNT/usr/sbin/cryptsetup" /usr/sbin/
        else
            warn "cryptsetup not found in gLiTcH Linux. Your encrypted system might not boot properly."
        fi
        
        # Update initramfs with encryption support
        if grep -q "^CRYPTSETUP=" /etc/cryptsetup-initramfs/conf-hook ; then
            sed -i 's/^CRYPTSETUP=.*/CRYPTSETUP=y/' /etc/cryptsetup-initramfs/conf-hook
        else
            echo "CRYPTSETUP=y" >> /etc/cryptsetup-initramfs/conf-hook
        fi
    fi
    
    # Handle proprietary drivers (NVIDIA, etc.)
    if lspci | grep -i nvidia > /dev/null; then
        log "NVIDIA GPU detected, ensuring driver compatibility..."
        # Preserve current NVIDIA driver if installed
        if dpkg -l | grep -i nvidia-driver > /dev/null; then
            local nvidia_package=$(dpkg -l | grep -i nvidia-driver | awk '{print $2}' | head -1)
            log "Found NVIDIA driver package: $nvidia_package"
            
            # Check if the same package exists in gLiTcH
            if grep -q "$nvidia_package" "$PACKAGE_LIST_FILE"; then
                log "The same NVIDIA driver package exists in gLiTcH Linux."
            else
                warn "NVIDIA driver package differs between systems. You may need to reinstall drivers after conversion."
                touch "$TEMP_DIR/reinstall_nvidia"
            fi
        fi
    fi
    
    # Handle secure boot
    if [ -d "/sys/firmware/efi" ] && [ -f "/usr/bin/mokutil" ]; then
        if mokutil --sb-state | grep -q "enabled"; then
            log "Secure Boot is enabled. Ensuring compatibility..."
            # Back up secure boot keys
            if [ -d "/var/lib/shim-signed" ]; then
                cp -a "/var/lib/shim-signed" "$BACKUP_DIR/var/lib/"
            fi
        fi
    fi
    
    log "Special case handling completed."
}

# Function to verify ISO integrity
verify_iso() {
    log "Verifying ISO integrity..."
    
    # Check if ISO file exists and has a reasonable size
    if [ ! -f "$ISO_FILE" ] || [ $(stat -c%s "$ISO_FILE") -lt 10000000 ]; then
        warn "ISO file doesn't exist or is too small. Will download again."
        rm -f "$ISO_FILE" 2>/dev/null || true
        return 1
    fi
    
    # Basic verification - can we mount it?
    if ! mount -o loop "$ISO_FILE" "$ISO_MOUNT" 2>/dev/null; then
        warn "ISO file cannot be mounted. Will download again."
        rm -f "$ISO_FILE" 2>/dev/null || true
        return 1
    fi
    
    # Verify ISO structure
    if [ ! -f "$ISO_MOUNT/live/filesystem.squashfs" ]; then
        warn "Invalid ISO structure. Will download again."
        umount "$ISO_MOUNT" 2>/dev/null || true
        rm -f "$ISO_FILE" 2>/dev/null || true
        return 1
    fi
    
    umount "$ISO_MOUNT" 2>/dev/null || true
    log "ISO verification passed."
    return 0
}

# Function to handle boot configuration
update_boot_configuration() {
    log "Updating boot configuration..."
    
    # Back up current boot configuration
    backup_file "/boot"
    backup_file "/etc/default/grub"
    
    # Create bootloader-specific user configuration from gLiTcH
    if [ -d "$SQUASHFS_MOUNT/etc/default/grub.d" ]; then
        mkdir -p /etc/default/grub.d
        cp -a "$SQUASHFS_MOUNT/etc/default/grub.d/"* /etc/default/grub.d/
    fi
    
    # Update GRUB if it exists
    if [ -f /etc/default/grub ]; then
        log "Updating GRUB configuration..."
        sed -i "s/GRUB_DISTRIBUTOR=.*/GRUB_DISTRIBUTOR=\"gLiTcH Linux\"/" /etc/default/grub
        
        # Preserve existing boot parameters that might be important
        local current_cmdline=$(grep "GRUB_CMDLINE_LINUX=" /etc/default/grub | sed 's/GRUB_CMDLINE_LINUX=//;s/"//g')
        local glitch_cmdline=$(grep "GRUB_CMDLINE_LINUX=" "$SQUASHFS_MOUNT/etc/default/grub" 2>/dev/null | sed 's/GRUB_CMDLINE_LINUX=//;s/"//g')
        
        # Combine both, removing duplicates
        local combined_cmdline=$(echo "$current_cmdline $glitch_cmdline" | tr ' ' '\n' | sort | uniq | tr '\n' ' ')
        sed -i "s/GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX=\"$combined_cmdline\"/" /etc/default/grub
        
        # Copy gLiTcH-specific GRUB themes if they exist
        if [ -d "$SQUASHFS_MOUNT/boot/grub/themes" ]; then
            log "Installing gLiTcH GRUB themes..."
            cp -r "$SQUASHFS_MOUNT/boot/grub/themes" /boot/grub/
        fi
        
        # Copy splash screen if it exists
        if [ -f "$ISO_MOUNT/boot/grub/splash.png" ]; then
            cp "$ISO_MOUNT/boot/grub/splash.png" /boot/grub/
        fi
        
        update-grub || {
            warn "Failed to update GRUB. Will try again after other changes."
            touch "$TEMP_DIR/grub_update_needed"
        }
    fi
    
    # Update initramfs
    log "Updating initramfs..."
    update-initramfs -u || {
        warn "Failed to update initramfs. Will try again with more options."
        update-initramfs -u -k all || {
            warn "Still having issues with initramfs update. This may require manual intervention after reboot."
            touch "$TEMP_DIR/initramfs_issues"
        }
    }
    
    log "Boot configuration update completed."
}

# Function for progress display for long operations
show_progress() {
    local pid=$1
    local message=$2
    local chars=( "|" "/" "-" "\\" )
    local i=0
    
    while ps -p $pid > /dev/null; do
        echo -ne "\r$message ${chars[$i]} "
        i=$(( (i+1) % 4 ))
        sleep 0.5
    done
    echo -e "\r$message Completed.    "
}

# Start of main execution
#log "=== gLiTcH Linux KDE v9.0 Installation Script ==="
#log "Starting conversion from Debian to gLiTcH Linux..."
echo -e "${GREEN}  ${NC}"
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
echo -e "${GREEN}| |   /____ / ||    |     |||    |   |\`   |          | |   /____/ ||    | |    |${NC}"
echo -e "${GREEN} \|___|    | / |____|_____|/|____|   |____|           \|___|    | /|____| |____|${NC}"
echo -e "${GREEN}   \( |____|/    \(    )/     \(       \(               \( |____|/   \(     )/${NC}"  
echo -e "${GREEN}    '   )/        '    '       '        '                '   )/       '     '${NC}"   
echo -e "${GREEN}       ____         ____  _____   ______    ____   ___                   _${NC}"                         
echo -e "${GREEN}      |    |       |    ||\    \ |\     \  |    | |    |_____      _____${NC}"        
echo -e "${GREEN}      |    |       |    | \\    \| \     \ |    | |    |\    \    /    /${NC}"        
echo -e "${GREEN}      |    |       |    |  \|    \  \     ||    | |    | \    \  /    /${NC}"         
echo -e "${GREEN}      |    |  ____ |    |   |     \  |    ||    | |    |  \____\/____/${NC}"          
echo -e "${GREEN}      |    | |    ||    |   |      \ |    ||    | |    |  /    /\    \ ${NC}"          
echo -e "${GREEN}      |    | |    ||    |   |    |\ \|    ||    | |    | /    /  \    \ ${NC}"         
echo -e "${GREEN}      |____|/____/||____|   |____||\_____/||\___\_|____|/____/ /\ \____\ ${NC}"        
echo -e "${GREEN}      |    |     |||    |   |    |/ \|   ||| |    |    ||    |/  \|    |${NC}"        
echo -e "${GREEN}      |____|_____|/|____|   |____|   |___|/ \|____|____||____|    |____|${NC}"        
echo -e "${GREEN}        \(    )/     \(       \(       )/      \(   )/    \(        )/${NC}"          
echo -e "${GREEN}         '    '       '        '       '        '   '      '        '${NC}"           
echo -e "${GREEN}                                                                      ${NC}"
echo -e "${YELLOW}                  | FULL SYSTEM CONVERSION SCRIPT |${NC}"
echo -e "${YELLOW}                  |  https://www.glitchlinux.wtf  | ${NC}"
echo -e "${GREEN}  ${NC}"


# Display warning and get confirmation
echo -e "${GREEN}  ${NC}"
echo -e "${RED}WARNING: This script will convert your Debian installation to gLiTcH Linux.${NC}"
echo -e "${GREEN}  ${NC}"
echo "This is a potentially dangerous operation that could make your system unbootable."
echo "Please ensure you have a backup of important data."
echo -e "${GREEN}  ${NC}"
read -p "Do you want to continue? (y/n): " confirm
if [[ "$confirm" != "y" && "$confirm" != "Y" ]]; then
    log "Installation aborted by user."
    exit 0
fi

# Check system compatibility
check_compatibility

# Check disk space
check_disk_space

# Create recovery script (do this early)
create_recovery_script

# Download the ISO if needed
log "Checking for gLiTcH Linux ISO..."
if ! verify_iso; then
    log "Downloading gLiTcH Linux ISO..."
    wget --no-check-certificate -O "$ISO_FILE" "$ISO_URL" || error "Failed to download ISO file. Check your internet connection and try again."
    if ! verify_iso; then
        error "Downloaded ISO file is corrupted or invalid."
    fi
fi

# Mount the ISO
log "Mounting ISO..."
mount -o loop "$ISO_FILE" "$ISO_MOUNT" || error "Failed to mount ISO file."

# Mount the squashfs filesystem
log "Mounting squashfs filesystem..."
mount -o loop "$ISO_MOUNT/live/filesystem.squashfs" "$SQUASHFS_MOUNT" || {
    warn "Failed to mount squashfs directly. Trying alternative method..."
    mkdir -p "$TEMP_DIR/squashfs-extracted"
    unsquashfs -d "$TEMP_DIR/squashfs-extracted" "$ISO_MOUNT/live/filesystem.squashfs" || error "Failed to extract squashfs filesystem."
    SQUASHFS_MOUNT="$TEMP_DIR/squashfs-extracted"
}

# Handle package management
handle_packages &
PACKAGE_PID=$!
show_progress $PACKAGE_PID "Processing package information"

# Backup critical system files in background
log "Backing up critical system files..."
{
    critical_files=(
        "/etc/fstab"
        "/etc/crypttab"
        "/etc/default/grub"
        "/boot"
        "/etc/passwd"
        "/etc/shadow"
        "/etc/group"
        "/etc/hostname"
        "/etc/hosts"
        "/etc/resolv.conf"
        "/etc/network"
        "/etc/NetworkManager"
        "/etc/X11/xorg.conf"
        "/etc/X11/xorg.conf.d"
    )

    for file in "${critical_files[@]}"; do
        backup_file "$file"
    done
} &
BACKUP_PID=$!
show_progress $BACKUP_PID "Backing up system files"

# Handle special cases
handle_special_cases

# Create a list of files to exclude from copying
cat > "$TEMP_DIR/rsync-exclude" << "EOF"
/boot/*
/dev/*
/proc/*
/sys/*
/tmp/*
/run/*
/mnt/*
/media/*
/etc/fstab
/etc/crypttab
/etc/mtab
/etc/resolv.conf
/root/debian-backup-*
/var/lib/dpkg/status
/var/lib/dpkg/available
/var/log/*
EOF

# Copy files from gLiTcH Linux to the current system
log "Copying gLiTcH Linux files to your system..."
log "This may take a while..."
rsync -av --exclude-from="$TEMP_DIR/rsync-exclude" "$SQUASHFS_MOUNT/" / || {
    error "Failed to copy files from gLiTcH Linux."
}

# Integrate package databases
log "Integrating package management databases..."
# Merge package status files rather than replacing
if [ -f "$SQUASHFS_MOUNT/var/lib/dpkg/status" ]; then
    # Ensure essential packages are marked as installed
    for pkg in $(cat "$TEMP_DIR/essential-packages.list"); do
        sed -i "/^Package: $pkg$/,/^Status: / s/^Status: .*/Status: install ok installed/" /var/lib/dpkg/status
    done
    
    # Copy additional package info
    cp -a "$SQUASHFS_MOUNT/var/lib/dpkg/info/"*.list /var/lib/dpkg/info/ 2>/dev/null || warn "Could not copy package info files"
    cp -a "$SQUASHFS_MOUNT/var/lib/dpkg/info/"*.md5sums /var/lib/dpkg/info/ 2>/dev/null || warn "Could not copy md5sums files"
fi

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
    # Try with more verbose output to diagnose issues
    update-initramfs -v -u -k all || warn "Initramfs update is still having issues. Check the log for details."
fi

if [ -f "$TEMP_DIR/reinstall_nvidia" ]; then
    log "Marking NVIDIA drivers for reinstallation after reboot..."
    # Create a startup script to reinstall NVIDIA drivers
    cat > /etc/rc.local << EOF
#!/bin/bash
apt-get update
apt-get install --reinstall nvidia-driver
# Remove this file after execution
rm -f /etc/rc.local
exit 0
EOF
    chmod +x /etc/rc.local
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
log "Your system has been converted to gLiTcH Linux KDE v9.0."
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
echo -e "${GREEN}| |   /____ / ||    |     |||    |   |\`   |          | |   /____/ ||    | |    |${NC}"
echo -e "${GREEN} \|___|    | / |____|_____|/|____|   |____|           \|___|    | /|____| |____|${NC}"
echo -e "${GREEN}   \( |____|/    \(    )/     \(       \(               \( |____|/   \(     )/${NC}"  
echo -e "${GREEN}    '   )/        '    '       '        '                '   )/       '     '${NC}"                     
echo -e "${GREEN}       ____         ____  _____   ______    ____   __                    __${NC}"                         
echo -e "${GREEN}      |    |       |    ||\    \ |\     \  |    | |    |_____      _____${NC}"        
echo -e "${GREEN}      |    |       |    | \\    \| \     \ |    | |    |\    \    /    /${NC}"        
echo -e "${GREEN}      |    |       |    |  \|    \  \     ||    | |    | \    \  /    /${NC}"         
echo -e "${GREEN}      |    |  ____ |    |   |     \  |    ||    | |    |  \____\/____/${NC}"          
echo -e "${GREEN}      |    | |    ||    |   |      \ |    ||    | |    |  /    /\    \ ${NC}"          
echo -e "${GREEN}      |    | |    ||    |   |    |\ \|    ||    | |    | /    /  \    \ ${NC}"         
echo -e "${GREEN}      |____|/____/||____|   |____||\_____/||\___\_|____|/____/ /\ \____\ ${NC}"        
echo -e "${GREEN}      |    |     |||    |   |    |/ \|   ||| |    |    ||    |/  \|    |${NC}"        
echo -e "${GREEN}      |____|_____|/|____|   |____|   |___|/ \|____|____||____|    |____|${NC}"        
echo -e "${GREEN}        \(    )/     \(       \(       )/      \(   )/    \(        )/${NC}"          
echo -e "${GREEN}         '    '       '        '       '        '   '      '        '${NC}"           
echo -e "${GREEN}                                                                   ${NC}"
echo -e "${YELLOW}                   | SYSTEM HAVE BEEN CONVERTED! |${NC}"
echo -e "${YELLOW}                   | https://www.glitchlinux.wtf | ${NC}"
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

exit 0
