#!/bin/bash

# Custom rEFInd Installer Script
# Downloads and installs GlitchLinux custom rEFInd bootloader

set -e  # Exit on any error

# Global variables
LOOP_DEVICE=""

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
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

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        exit 1
    fi
}

# Check if EFI system exists
check_efi_system() {
    if [[ ! -d "/sys/firmware/efi" ]]; then
        print_error "This system does not appear to be booted in EFI mode"
        exit 1
    fi
    
    if [[ ! -d "/boot/efi/EFI" ]]; then
        print_error "EFI system partition not found at /boot/efi/EFI"
        print_warning "Make sure your EFI system partition is mounted at /boot/efi"
        exit 1
    fi
}

# Download the rEFInd image
download_refind() {
    print_status "Downloading custom rEFInd image..."
    
    cd /tmp
    if wget -O "REFIND_MASTER.img" "https://github.com/GlitchLinux/REFIND_CUSTOM/raw/refs/heads/main/REFIND%C2%A4MASTER.img"; then
        print_success "rEFInd image downloaded successfully"
    else
        print_error "Failed to download rEFInd image"
        exit 1
    fi
}

# Create loop device and mount the EFI partition
mount_refind_image() {
    print_status "Setting up loop device for disk image..."
    
    # Create mount point
    mkdir -p /tmp/refind
    
    # Set up loop device for the entire disk image
    LOOP_DEVICE=$(losetup --find --show /tmp/REFIND_MASTER.img)
    if [[ $? -ne 0 ]]; then
        print_error "Failed to create loop device"
        cleanup_on_error
        exit 1
    fi
    
    print_success "Loop device created: $LOOP_DEVICE"
    
    # Wait a moment for the kernel to detect partitions
    sleep 2
    
    # Trigger partition table re-read
    partprobe $LOOP_DEVICE 2>/dev/null || true
    
    # List available partitions
    print_status "Available partitions:"
    lsblk $LOOP_DEVICE
    
    # Try to mount the first partition (usually the EFI partition)
    EFI_PARTITION="${LOOP_DEVICE}p1"
    
    # Check if partition exists
    if [[ ! -e "$EFI_PARTITION" ]]; then
        print_warning "Partition ${LOOP_DEVICE}p1 not found, trying alternative naming..."
        EFI_PARTITION="${LOOP_DEVICE}1"
    fi
    
    if [[ ! -e "$EFI_PARTITION" ]]; then
        print_error "Could not find EFI partition on loop device"
        cleanup_on_error
        exit 1
    fi
    
    # Mount the EFI partition
    if mount $EFI_PARTITION /tmp/refind; then
        print_success "EFI partition mounted successfully at /tmp/refind"
        print_status "Using partition: $EFI_PARTITION"
    else
        print_error "Failed to mount EFI partition"
        cleanup_on_error
        exit 1
    fi
}

# Rename EFI/BOOT to EFI/refind
rename_boot_directory() {
    print_status "Renaming /EFI/BOOT directory to /EFI/refind..."
    
    if [[ -d "/tmp/refind/EFI/BOOT" ]]; then
        if mv /tmp/refind/EFI/BOOT /tmp/refind/EFI/refind; then
            print_success "Directory renamed successfully"
        else
            print_error "Failed to rename directory"
            cleanup_on_error
            exit 1
        fi
    else
        print_warning "EFI/BOOT directory not found in mounted image"
    fi
}

# Copy rEFInd files to system EFI partition
copy_refind_files() {
    print_status "Copying rEFInd files to system EFI partition..."
    
    # Backup existing refind directory if it exists
    if [[ -d "/boot/efi/EFI/refind" ]]; then
        print_warning "Existing rEFInd installation found, creating backup..."
        cp -r /boot/efi/EFI/refind /boot/efi/EFI/refind.backup.$(date +%Y%m%d_%H%M%S)
    fi
    
    # Copy all files from mounted image to EFI partition
    if cp -rf /tmp/refind/EFI/* /boot/efi/EFI/; then
        print_success "rEFInd files copied successfully"
    else
        print_error "Failed to copy rEFInd files"
        cleanup_on_error
        exit 1
    fi
}

# Add rEFInd entry to GRUB
add_grub_entry() {
    print_status "Adding rEFInd entry to GRUB configuration..."
    
    # Get EFI partition UUID for proper GRUB search
    EFI_UUID=$(blkid -s UUID -o value $(df /boot/efi | tail -1 | awk '{print $1}'))
    
    # Create comprehensive GRUB entry for rEFInd with multiple search paths
    cat > /etc/grub.d/30_refind << EOF
#!/bin/sh
exec tail -n +3 \$0
# Custom rEFInd Boot Manager entry with comprehensive path search

menuentry "rEFInd Boot Manager" {
    insmod part_gpt
    insmod fat
    insmod chain
    insmod efifwsetup
    
    # Search for EFI partition by UUID
    search --no-floppy --fs-uuid --set=root ${EFI_UUID}
    
    # Try multiple possible rEFInd locations and filenames
    # First try: /EFI/refind/bootx64.efi (our renamed directory)
    if [ -f /EFI/refind/bootx64.efi ]; then
        chainloader /EFI/refind/bootx64.efi
    # Second try: /EFI/refind/refind_x64.efi (standard rEFInd name)
    elif [ -f /EFI/refind/refind_x64.efi ]; then
        chainloader /EFI/refind/refind_x64.efi
    # Third try: /EFI/BOOT/bootx64.efi (if rename failed)
    elif [ -f /EFI/BOOT/bootx64.efi ]; then
        chainloader /EFI/BOOT/bootx64.efi
    # Fourth try: /EFI/tools/refind_x64.efi
    elif [ -f /EFI/tools/refind_x64.efi ]; then
        chainloader /EFI/tools/refind_x64.efi
    # Fifth try: search for any refind executable
    elif [ -f /EFI/Microsoft/Boot/bootmgfw.efi ]; then
        # Fallback to Windows Boot Manager if rEFInd not found
        chainloader /EFI/Microsoft/Boot/bootmgfw.efi
    else
        # Last resort: try to boot from firmware
        fwsetup
    fi
}

# Alternative rEFInd entry with direct file specification
menuentry "rEFInd Boot Manager (Direct)" {
    insmod part_gpt
    insmod fat
    insmod chain
    
    # Search for EFI partition
    search --no-floppy --fs-uuid --set=root ${EFI_UUID}
    
    # Direct path to our installed rEFInd
    chainloader /EFI/refind/bootx64.efi
}
EOF
    
    # Make the script executable
    chmod +x /etc/grub.d/30_refind
    
    print_success "rEFInd GRUB entry created with comprehensive path search"
    print_status "EFI partition UUID: ${EFI_UUID}"
}

# Update GRUB configuration
update_grub_config() {
    print_status "Updating GRUB configuration..."
    
    if command -v update-grub &> /dev/null; then
        if update-grub; then
            print_success "GRUB configuration updated successfully"
        else
            print_error "Failed to update GRUB configuration"
            exit 1
        fi
    elif command -v grub-mkconfig &> /dev/null; then
        if grub-mkconfig -o /boot/grub/grub.cfg; then
            print_success "GRUB configuration updated successfully"
        else
            print_error "Failed to update GRUB configuration"
            exit 1
        fi
    else
        print_error "Neither update-grub nor grub-mkconfig found"
        exit 1
    fi
}

# Cleanup function for errors
cleanup_on_error() {
    print_status "Cleaning up due to error..."
    
    # Unmount if mounted
    if mountpoint -q /tmp/refind 2>/dev/null; then
        umount /tmp/refind
    fi
    
    # Detach loop device if it was created
    if [[ -n "$LOOP_DEVICE" ]] && losetup "$LOOP_DEVICE" &>/dev/null; then
        losetup -d "$LOOP_DEVICE"
    fi
    
    # Remove mount point
    [[ -d "/tmp/refind" ]] && rmdir /tmp/refind
    
    # Remove downloaded image
    [[ -f "/tmp/REFIND_MASTER.img" ]] && rm -f /tmp/REFIND_MASTER.img
}

# Final cleanup
cleanup() {
    print_status "Performing final cleanup..."
    
    # Unmount the image
    if mountpoint -q /tmp/refind 2>/dev/null; then
        umount /tmp/refind
        print_success "EFI partition unmounted"
    fi
    
    # Detach loop device
    if [[ -n "$LOOP_DEVICE" ]] && losetup "$LOOP_DEVICE" &>/dev/null; then
        losetup -d "$LOOP_DEVICE"
        print_success "Loop device detached"
    fi
    
    # Remove mount point
    if [[ -d "/tmp/refind" ]]; then
        rmdir /tmp/refind
        print_success "Mount point removed"
    fi
    
    # Remove downloaded image
    if [[ -f "/tmp/REFIND_MASTER.img" ]]; then
        rm -f /tmp/REFIND_MASTER.img
        print_success "Downloaded image cleaned up"
    fi
    
    print_success "Cleanup completed successfully"
}

# Main installation function
main() {
    print_status "Starting custom rEFInd installation..."
    
    # Pre-installation checks
    check_root
    check_efi_system
    
    # Installation steps
    download_refind
    mount_refind_image
    rename_boot_directory
    copy_refind_files
    add_grub_entry
    update_grub_config
    
    # Final cleanup
    cleanup
    
    print_success "rEFInd installation completed successfully!"
    print_status "You can now reboot and select 'rEFInd Boot Manager' from GRUB menu"
    print_status "Or you can directly boot rEFInd from your UEFI firmware settings"
}

# Trap to ensure cleanup on script exit
trap cleanup_on_error ERR
trap cleanup EXIT

# Run main function
main "$@"
