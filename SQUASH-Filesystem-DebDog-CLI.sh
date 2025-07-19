#!/bin/bash

# Enhanced Linux Live Remaster Script - CLI Version
# Creates a squashfs module from current system with systemd boot fixes
# CLI version with hostname customization

# Color codes for better CLI experience
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(whoami)" != "root" ]; then
    echo -e "${RED}This script must be run as root.${NC}"
    echo "Re-running with sudo..."
    exec sudo "$0" "$@"
fi

# Function to print colored messages
print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to fix systemd issues in the remastered system
fix_systemd_issues() {
    local WORK="$1"
    local HOSTNAME="$2"
    
    print_info "Fixing systemd configuration..."
    
    # Ensure essential device nodes exist
    mkdir -p "$WORK/dev"
    
    # Create essential device nodes that systemd expects
    mknod "$WORK/dev/null" c 1 3 2>/dev/null || true
    mknod "$WORK/dev/zero" c 1 5 2>/dev/null || true
    mknod "$WORK/dev/random" c 1 8 2>/dev/null || true
    mknod "$WORK/dev/urandom" c 1 9 2>/dev/null || true
    mknod "$WORK/dev/tty" c 5 0 2>/dev/null || true
    mknod "$WORK/dev/console" c 5 1 2>/dev/null || true
    
    # Set proper permissions
    chmod 666 "$WORK/dev/null" "$WORK/dev/zero" "$WORK/dev/random" "$WORK/dev/urandom"
    chmod 600 "$WORK/dev/console" "$WORK/dev/tty"
    
    # Fix systemd service files and directories
    mkdir -p "$WORK/run/systemd"
    mkdir -p "$WORK/var/lib/systemd"
    mkdir -p "$WORK/etc/systemd/system"
    
    # Create a basic machine-id (systemd requirement)
    if [ ! -f "$WORK/etc/machine-id" ]; then
        systemd-machine-id-setup --root="$WORK" 2>/dev/null || \
        echo "$(cat /proc/sys/kernel/random/uuid | tr -d '-')" > "$WORK/etc/machine-id"
    fi
    
    # Fix /etc/fstab for live system
    cat > "$WORK/etc/fstab" << EOF
# Live system fstab
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devpts /dev/pts devpts defaults 0 0
tmpfs /tmp tmpfs defaults 0 0
tmpfs /run tmpfs defaults 0 0
EOF
    
    # Set hostname in the live system
    echo "$HOSTNAME" > "$WORK/etc/hostname"
    
    # Update /etc/hosts with the new hostname
    cat > "$WORK/etc/hosts" << EOF
127.0.0.1	localhost
127.0.1.1	$HOSTNAME
::1		localhost ip6-localhost ip6-loopback
ff02::1		ip6-allnodes
ff02::2		ip6-allrouters
EOF
    
    # Ensure systemd default target is set correctly
    chroot "$WORK" systemctl set-default multi-user.target 2>/dev/null || true
    
    # Fix potential systemd service issues
    chroot "$WORK" systemctl disable systemd-machine-id-commit.service 2>/dev/null || true
    chroot "$WORK" systemctl disable systemd-firstboot.service 2>/dev/null || true
    
    # Create a basic resolv.conf
    echo "nameserver 8.8.8.8" > "$WORK/etc/resolv.conf"
    echo "nameserver 8.8.4.4" >> "$WORK/etc/resolv.conf"
    
    # Fix initramfs/initrd issues
    chroot "$WORK" update-initramfs -u 2>/dev/null || true
    
    # Ensure proper permissions on systemd directories
    chown -R root:root "$WORK/etc/systemd" 2>/dev/null || true
    chown -R root:root "$WORK/lib/systemd" 2>/dev/null || true
    chown -R root:root "$WORK/usr/lib/systemd" 2>/dev/null || true
    
    print_success "Systemd configuration fixed with hostname: $HOSTNAME"
}

# Function to create a live system boot configuration
create_live_boot_config() {
    local WORK="$1"
    local HOSTNAME="$2"
    
    print_info "Creating live boot configuration..."
    
    # Create live system specific configurations
    mkdir -p "$WORK/etc/live"
    
    # Create a live system init script
    cat > "$WORK/etc/systemd/system/live-config.service" << 'EOF'
[Unit]
Description=Live system configuration
After=local-fs.target
Before=display-manager.service

[Service]
Type=oneshot
ExecStart=/usr/bin/live-config
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
    
    # Enable the live config service
    chroot "$WORK" systemctl enable live-config.service 2>/dev/null || true
    
    # Create basic live-config script with hostname
    cat > "$WORK/usr/bin/live-config" << EOF
#!/bin/bash
# Basic live system configuration

# Mount essential filesystems
mount -t proc proc /proc 2>/dev/null || true
mount -t sysfs sysfs /sys 2>/dev/null || true
mount -t devtmpfs devtmpfs /dev 2>/dev/null || true

# Set hostname
echo "$HOSTNAME" > /etc/hostname
hostname "$HOSTNAME"

exit 0
EOF
    
    chmod +x "$WORK/usr/bin/live-config"
    print_success "Live boot configuration created"
}

# Function to display available drives
show_available_drives() {
    print_info "Available drives and partitions:"
    echo -e "${YELLOW}Drive${NC}\t${YELLOW}Size${NC}\t${YELLOW}Type${NC}\t${YELLOW}Mountpoint${NC}"
    echo "------------------------------------------------"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT | grep -E "^[sd|nvme|hd]" | while read line; do
        echo -e "${GREEN}$line${NC}"
    done
    echo
    echo -e "${BLUE}Available paths:${NC}"
    echo "/tmp (temporary storage)"
    echo "/ (root filesystem)"
    for dev in $(lsblk -rno NAME,MOUNTPOINT | awk '$2!="" && $2!="/" && $2!="[SWAP]" {print $2}' | sort -u); do
        if [ -d "$dev" ] && [ -w "$dev" ]; then
            echo "$dev"
        fi
    done
}

# Main script starts here
clear
echo -e "${GREEN}===============================================${NC}"
echo -e "${GREEN}  Enhanced Linux Live Remaster - CLI Version${NC}"
echo -e "${GREEN}===============================================${NC}"
echo
print_info "This script creates a squashfs module from your current system"
print_info "with systemd boot fixes and hostname customization."
echo

# Show available drives
show_available_drives

# Get user input
echo
echo -e "${YELLOW}Please provide the following information:${NC}"
echo

# Drive selection
while true; do
    echo -n "Enter the path where to create the module (e.g., /tmp, /, /mnt/sda1): "
    read DRIVE_PATH
    
    if [ -z "$DRIVE_PATH" ]; then
        print_error "Path cannot be empty. Please enter a valid path."
        continue
    fi
    
    if [ ! -d "$DRIVE_PATH" ]; then
        print_error "Directory $DRIVE_PATH does not exist."
        continue
    fi
    
    if [ ! -w "$DRIVE_PATH" ]; then
        print_error "Directory $DRIVE_PATH is not writable."
        continue
    fi
    
    break
done

# Working directory name
while true; do
    echo -n "Enter working directory name [remastered]: "
    read WRKDIR
    WRKDIR=${WRKDIR:-remastered}
    
    if [[ "$WRKDIR" =~ [^a-zA-Z0-9_-] ]]; then
        print_error "Working directory name can only contain letters, numbers, hyphens, and underscores."
        continue
    fi
    
    break
done

# Hostname for the live system
while true; do
    echo -n "Enter hostname for the live system [live-system]: "
    read HOSTNAME
    HOSTNAME=${HOSTNAME:-live-system}
    
    if [[ ! "$HOSTNAME" =~ ^[a-zA-Z0-9]([a-zA-Z0-9-]*[a-zA-Z0-9])?$ ]]; then
        print_error "Invalid hostname. Use only letters, numbers, and hyphens. Cannot start or end with hyphen."
        continue
    fi
    
    break
done

# Set up paths
WORK="$DRIVE_PATH/$WRKDIR"
SQFS="$DRIVE_PATH/filesystem.squashfs"

echo
print_info "Configuration summary:"
echo "  Working directory: $WORK"
echo "  Output file: $SQFS" 
echo "  Hostname: $HOSTNAME"
echo

# Check if paths already exist
if [ -d "$WORK" ]; then
    print_error "Directory $WORK already exists."
    echo -n "Do you want to remove it and continue? (y/N): "
    read response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -rf "$WORK"
        print_warning "Removed existing directory $WORK"
    else
        print_error "Aborted by user."
        exit 1
    fi
fi

if [ -e "$SQFS" ]; then
    print_error "File $SQFS already exists."
    echo -n "Do you want to overwrite it? (y/N): "
    read response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        rm -f "$SQFS"
        print_warning "Removed existing file $SQFS"
    else
        print_error "Aborted by user."
        exit 1
    fi
fi

# Confirm before proceeding
echo
echo -n "Proceed with creating the live system? (y/N): "
read confirm
if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
    print_error "Aborted by user."
    exit 1
fi

echo
print_info "Starting remaster process..."

# Create working directory
mkdir -p "$WORK"

# Copy system files with improved exclusions
print_info "Copying system files (this may take several minutes)..."
rsync -aHAXS --numeric-ids --info=progress2 / "$WORK" \
    --exclude=/dev/* \
    --exclude=/proc/* \
    --exclude=/sys/* \
    --exclude=/tmp/* \
    --exclude=/run/* \
    --exclude=/mnt/* \
    --exclude=/media/* \
    --exclude=/live/* \
    --exclude=/lib/live/mount/* \
    --exclude=/cdrom/* \
    --exclude=/initrd/* \
    --exclude="/$WRKDIR" \
    --exclude=/var/cache/apt/archives/* \
    --exclude=/var/lib/apt/lists/* \
    --exclude=/var/log/* \
    --exclude=/root/.cache \
    --exclude=/root/.thumbnails \
    --exclude=/home/*/.cache \
    --exclude=/home/*/.thumbnails \
    --exclude=/swap.file \
    --exclude=/swapfile

# Create essential directories
mkdir -p "$WORK"/{dev,proc,sys,tmp,run,mnt,media}

# Apply systemd fixes with hostname
fix_systemd_issues "$WORK" "$HOSTNAME"

# Create live boot configuration
create_live_boot_config "$WORK" "$HOSTNAME"

# Clean up and prepare the system
print_info "Cleaning up system..."
rm -f "$WORK"/var/lib/alsa/asound.state
rm -f "$WORK"/root/.bash_history
rm -f "$WORK"/root/.xsession-errors*
rm -f "$WORK"/etc/blkid-cache
rm -rf "$WORK"/etc/udev/rules.d/70-persistent*
rm -f "$WORK"/var/lib/dhcp/dhclient.*.leases
rm -f "$WORK"/var/lib/dhcpcd/*.lease
rm -rf "$WORK"/var/tmp/*
rm -rf "$WORK"/tmp/*

# Set proper permissions
chmod 1777 "$WORK/tmp"
chmod 755 "$WORK/run"

# Create the squashfs
print_info "Creating squashfs filesystem (this may take several minutes)..."
if mksquashfs "$WORK" "$SQFS" -comp xz -b 512k -Xbcj x86 -progress; then
    print_success "Successfully created: $SQFS"
    
    # Show file size
    SIZE=$(du -h "$SQFS" | cut -f1)
    print_info "File size: $SIZE"
    
    echo
    echo -n "Do you want to remove the working directory? (Y/n): "
    read cleanup
    if [[ ! "$cleanup" =~ ^[Nn]$ ]]; then
        rm -rf "$WORK"
        print_success "Working directory cleaned up"
    else
        print_info "Working directory preserved at: $WORK"
    fi
    
    echo
    print_success "Live system creation completed successfully!"
    print_info "Your live system squashfs is ready at: $SQFS"
    print_info "Hostname has been set to: $HOSTNAME"
    
else
    print_error "Failed to create squashfs filesystem"
    echo -n "Keep working directory for debugging? (Y/n): "
    read keep
    if [[ "$keep" =~ ^[Nn]$ ]]; then
        rm -rf "$WORK"
    fi
    exit 1
fi

exit 0
