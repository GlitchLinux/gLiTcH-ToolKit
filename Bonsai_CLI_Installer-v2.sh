#!/bin/bash

# Enhanced Debian Live Installer - Complete Version with LUKS, Boot Partition & Loop Device Support
# All functions included - ready to run

set -e

# Enhanced color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
MAGENTA='\033[38;5;198m'
BRIGHT_GREEN='\033[0;96m'
CYAN='\033[0;96m'
NC='\033[0m'

# Global variables
INSTALL_SOURCE=""
INSTALL_SOURCE_TYPE=""
MOUNT_LIVE="/mnt/live"
MOUNT_TARGET="/mnt/target"
INSTALL_TYPE=""
TARGET_DEVICE=""
DATA_PARTITION=""
EFI_PARTITION=""
BOOT_PARTITION=""
USE_EXISTING_PARTITIONS=""
USE_SEPARATE_BOOT=""
BOOT_PARTITION_SIZE=""
BOOT_PARTITION_FS=""
DATA_PARTITION_SIZE=""
ORIGINAL_SQUASHFS=""
OS_NAME=""
USE_LUKS=""
LUKS_DEVICE=""
LUKS_MAPPER="luks-root"
IS_LOOP_DEVICE=""

# Clear screen and show header
clear_and_header() {
    clear
    echo -e "${CYAN}╔══════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}${WHITE} Bonsai CLI Installer${NC}${CYAN} ║${NC}"
    echo -e "${CYAN}╚══════════════════════╝${NC}"
    echo
}

# Print functions
print_main() { echo -e "${WHITE}$1${NC}"; }
print_info() { echo -e "${BLUE}[INFO]${NC} ${WHITE}$1${NC}"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} ${WHITE}$1${NC}"; }
print_warning() { echo -e "${MAGENTA}[WARNING]${NC} ${MAGENTA}$1${NC}"; }
print_error() { echo -e "${RED}[ERROR]${NC} ${RED}$1${NC}"; }
print_prompt() { echo -e "${BRIGHT_GREEN}$1${NC}"; }
print_progress() { echo -e "${CYAN}[PROGRESS]${NC} ${CYAN}$1${NC}"; }

show_step() {
    local step=$1
    local description=$2
    echo -e "${CYAN}━━━ Step $step: ${WHITE}$description${CYAN} ━━━${NC}"
    echo
}

check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root"
        exit 1
    fi
}

install_dependencies() {
    clear_and_header
    show_step "1" "Installing Dependencies"
    
    local packages=("rsync" "parted" "gdisk" "dosfstools" "e2fsprogs" "pv" "dialog" "cryptsetup")
    local missing_packages=()
    
    for package in "${packages[@]}"; do
        if ! dpkg -l "$package" >/dev/null 2>&1; then
            missing_packages+=("$package")
        fi
    done
    
    if [[ ${#missing_packages[@]} -gt 0 ]]; then
        print_info "Installing missing packages: ${missing_packages[*]}"
        apt-get update >/dev/null 2>&1
        apt-get install -y "${missing_packages[@]}" >/dev/null 2>&1
        print_success "Dependencies installed successfully"
    else
        print_success "All required dependencies are already installed"
    fi
    
    sleep 1
}

get_os_name_from_source() {
    local source_path="$1"
    local temp_mount=""
    
    if [[ "$source_path" == "/" ]]; then
        # Installing from current system
        OS_NAME=$(cat /etc/os-release 2>/dev/null | grep -w "PRETTY_NAME" | cut -d '=' -f2 | sed 's/"//g' || echo "Unknown")
    elif [[ -f "$source_path" && "$source_path" =~ \.squashfs$ ]]; then
        # Installing from squashfs file
        temp_mount="/tmp/squashfs_mount_$$"
        mkdir -p "$temp_mount"
        if mount -t squashfs -o loop "$source_path" "$temp_mount" 2>/dev/null; then
            OS_NAME=$(cat "$temp_mount/etc/os-release" 2>/dev/null | grep -w "PRETTY_NAME" | cut -d '=' -f2 | sed 's/"//g' || echo "Unknown")
            umount "$temp_mount" 2>/dev/null || true
        else
            OS_NAME="Unknown"
        fi
        rmdir "$temp_mount" 2>/dev/null || true
    else
        OS_NAME="Unknown"
    fi
    
    print_info "Detected OS: $OS_NAME"
}

select_install_source() {
    clear_and_header
    show_step "2" "Select Installation Source"
    
    print_main "Choose your installation source:"
    echo "1) Install current system (live boot or full install from /)"
    echo "2) Install from custom .squashfs file"
    echo
    
    while true; do
        print_prompt "Enter your choice (1-2):"
        read -r choice
        case $choice in
            1)
                INSTALL_SOURCE_TYPE="current"
                # Enhanced squashfs detection for both Debian and Ubuntu
                if [[ -f "/run/live/medium/live/filesystem.squashfs" ]]; then
                    INSTALL_SOURCE="/run/live/medium/live/filesystem.squashfs"
                    ORIGINAL_SQUASHFS="$INSTALL_SOURCE"
                    print_info "Detected Debian live environment, using: $INSTALL_SOURCE"
                elif [[ -f "/cdrom/casper/filesystem.squashfs" ]]; then
                    INSTALL_SOURCE="/cdrom/casper/filesystem.squashfs"
                    ORIGINAL_SQUASHFS="$INSTALL_SOURCE"
                    print_info "Detected Ubuntu live environment, using: $INSTALL_SOURCE"
                elif [[ -d "/run/live/medium/live" ]]; then
                    local squashfs_file=$(find /run/live/medium/live -name "*.squashfs" | head -1)
                    if [[ -n "$squashfs_file" ]]; then
                        INSTALL_SOURCE="$squashfs_file"
                        ORIGINAL_SQUASHFS="$INSTALL_SOURCE"
                        print_info "Found squashfs file: $INSTALL_SOURCE"
                    else
                        INSTALL_SOURCE="/"
                        print_info "No squashfs found, will copy from root filesystem: $INSTALL_SOURCE"
                    fi
                elif [[ -d "/cdrom/casper" ]]; then
                    local squashfs_file=$(find /cdrom/casper -name "*.squashfs" | head -1)
                    if [[ -n "$squashfs_file" ]]; then
                        INSTALL_SOURCE="$squashfs_file"
                        ORIGINAL_SQUASHFS="$INSTALL_SOURCE"
                        print_info "Found Ubuntu squashfs file: $INSTALL_SOURCE"
                    else
                        INSTALL_SOURCE="/"
                        print_info "No squashfs found, will copy from root filesystem: $INSTALL_SOURCE"
                    fi
                else
                    INSTALL_SOURCE="/"
                    print_info "Using current root filesystem: $INSTALL_SOURCE"
                fi
                break
                ;;
            2)
                INSTALL_SOURCE_TYPE="custom"
                while true; do
                    print_prompt "Enter path to .squashfs file: "
                    read -r squashfs_input
                    
                    if [[ -f "$squashfs_input" ]]; then
                        INSTALL_SOURCE="$squashfs_input"
                        ORIGINAL_SQUASHFS="$INSTALL_SOURCE"
                        print_success "Using custom squashfs: $INSTALL_SOURCE"
                        break
                    else
                        print_error "File not found: $squashfs_input"
                    fi
                done
                break
                ;;
            *)
                print_error "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done
    
    # Get OS name from source
    get_os_name_from_source "$INSTALL_SOURCE"
    sleep 1
}

select_install_type() {
    clear_and_header
    show_step "3" "Select Boot Type"
    
    print_main "Select firmware/boot type:"
    echo "1) Legacy BIOS (MBR)"
    echo "2) Legacy BIOS (GPT)"
    echo "3) UEFI"
    echo
    
    while true; do
        print_prompt "Enter your choice (1-3): "
        read -r choice
        case $choice in
            1)
                INSTALL_TYPE="legacy_mbr"
                print_info "Selected: Legacy BIOS with MBR partition table"
                break
                ;;
            2)
                INSTALL_TYPE="bios_gpt"
                print_info "Selected: Legacy BIOS with GPT partition table"
                break
                ;;
            3)
                INSTALL_TYPE="uefi"
                print_info "Selected: UEFI boot"
                break
                ;;
            *)
                print_error "Invalid choice. Please enter 1, 2, or 3."
                ;;
        esac
    done
    
    sleep 1
}

select_target_disk() {
    clear_and_header
    show_step "4" "Select Target Disk"
    
    print_main "Available storage devices:"
    lsblk -o NAME,SIZE,TYPE,FSTYPE,MOUNTPOINT,LABEL
    echo
    print_info "You can also specify loop devices (e.g., /dev/loop0)"
    echo
    
    while true; do
        print_prompt "Enter target disk (e.g., sda, nvme0n1, /dev/loop0): "
        read -r disk_input
        
        if [[ ! "$disk_input" =~ ^/dev/ ]]; then
            disk_input="/dev/$disk_input"
        fi
        
        # Check for loop device
        if [[ "$disk_input" =~ /dev/loop[0-9]+ ]]; then
            IS_LOOP_DEVICE="yes"
            if [[ -b "$disk_input" ]]; then
                TARGET_DEVICE="$disk_input"
                print_success "Selected loop device: $TARGET_DEVICE"
                break
            else
                print_error "Loop device not found: $disk_input"
                print_info "You may need to create it first with: losetup"
            fi
        elif [[ -b "$disk_input" ]]; then
            TARGET_DEVICE="$disk_input"
            IS_LOOP_DEVICE="no"
            print_success "Selected target disk: $TARGET_DEVICE"
            break
        else
            print_error "Invalid disk device: $disk_input"
        fi
    done
    
    sleep 1
}

select_partitioning_method() {
    clear_and_header
    show_step "5" "Partitioning Method"
    
    print_main "Partitioning options:"
    echo "1) Use existing partitions"
    echo "2) Erase disk and create new partitions"
    echo
    
    while true; do
        print_prompt "Enter your choice (1-2): "
        read -r choice
        case $choice in
            1)
                USE_EXISTING_PARTITIONS="yes"
                print_info "Will use existing partitions"
                select_existing_partitions
                break
                ;;
            2)
                USE_EXISTING_PARTITIONS="no"
                print_warning "This will ERASE ALL DATA on $TARGET_DEVICE"
                print_prompt "Are you sure? Type 'YES' to confirm: "
                read -r confirm
                if [[ "$confirm" == "YES" ]]; then
                    select_boot_partition_option
                    select_luks_encryption
                    create_new_partitions
                else
                    print_info "Operation cancelled"
                    exit 0
                fi
                break
                ;;
            *)
                print_error "Invalid choice. Please enter 1 or 2."
                ;;
        esac
    done
}

select_boot_partition_option() {
    print_main "Boot partition configuration:"
    print_prompt "Create separate /boot partition? (y/N): "
    read -r boot_choice
    
    if [[ "$boot_choice" =~ ^[Yy]$ ]]; then
        USE_SEPARATE_BOOT="yes"
        
        while true; do
            print_prompt "Enter /boot partition size in MB (recommended: 256-512): "
            read -r boot_size
            if [[ "$boot_size" =~ ^[0-9]+$ ]] && [[ $boot_size -ge 100 ]]; then
                BOOT_PARTITION_SIZE="$boot_size"
                break
            else
                print_error "Invalid size. Please enter a number >= 100"
            fi
        done
        
        print_main "Select filesystem for /boot partition:"
        echo "1) ext2 (recommended for /boot)"
        echo "2) ext3"
        echo "3) ext4"
        
        while true; do
            print_prompt "Enter choice (1-3): "
            read -r fs_choice
            case $fs_choice in
                1) BOOT_PARTITION_FS="ext2"; break;;
                2) BOOT_PARTITION_FS="ext3"; break;;
                3) BOOT_PARTITION_FS="ext4"; break;;
                *) print_error "Invalid choice";;
            esac
        done
        
        print_info "Will create ${BOOT_PARTITION_SIZE}MB /boot partition with $BOOT_PARTITION_FS"
    else
        USE_SEPARATE_BOOT="no"
        print_info "Will use single root partition"
    fi
}

select_luks_encryption() {
    print_main "LUKS encryption configuration:"
    print_prompt "Encrypt data partition with LUKS? (y/N): "
    read -r luks_choice
    
    if [[ "$luks_choice" =~ ^[Yy]$ ]]; then
        USE_LUKS="yes"
        print_warning "You will be prompted for a strong passphrase during encryption setup"
        print_info "LUKS encryption will be applied to the data/root partition"
    else
        USE_LUKS="no"
        print_info "No encryption will be used"
    fi
}

select_existing_partitions() {
    print_main "Current partition layout for $TARGET_DEVICE:"
    lsblk "$TARGET_DEVICE"
    echo
    
    if [[ "$INSTALL_TYPE" == "uefi" ]]; then
        while true; do
            print_prompt "Enter EFI System Partition (e.g., ${TARGET_DEVICE}1): "
            read -r efi_input
            
            if [[ ! "$efi_input" =~ ^/dev/ ]]; then
                if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                    efi_input="${TARGET_DEVICE}p${efi_input##*[a-z]}"
                else
                    efi_input="${TARGET_DEVICE}${efi_input##*[a-z]}"
                fi
            fi
            
            if [[ -b "$efi_input" ]]; then
                EFI_PARTITION="$efi_input"
                print_success "Selected EFI partition: $EFI_PARTITION"
                break
            else
                print_error "Invalid partition: $efi_input"
            fi
        done
    fi
    
    # Ask for boot partition
    print_prompt "Enter partition to use as /boot (hit enter to skip): "
    read -r boot_input
    
    if [[ -n "$boot_input" ]]; then
        if [[ ! "$boot_input" =~ ^/dev/ ]]; then
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                boot_input="${TARGET_DEVICE}p${boot_input##*[a-z]}"
            else
                boot_input="${TARGET_DEVICE}${boot_input##*[a-z]}"
            fi
        fi
        
        if [[ -b "$boot_input" ]]; then
            BOOT_PARTITION="$boot_input"
            USE_SEPARATE_BOOT="yes"
            print_success "Selected boot partition: $BOOT_PARTITION"
        else
            print_error "Invalid boot partition: $boot_input"
            USE_SEPARATE_BOOT="no"
        fi
    else
        USE_SEPARATE_BOOT="no"
        print_info "No separate boot partition will be used"
    fi
    
    while true; do
        print_prompt "Enter data/root partition (e.g., ${TARGET_DEVICE}2): "
        read -r data_input
        
        if [[ ! "$data_input" =~ ^/dev/ ]]; then
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                data_input="${TARGET_DEVICE}p${data_input##*[a-z]}"
            else
                data_input="${TARGET_DEVICE}${data_input##*[a-z]}"
            fi
        fi
        
        if [[ -b "$data_input" ]]; then
            DATA_PARTITION="$data_input"
            print_success "Selected data partition: $DATA_PARTITION"
            break
        else
            print_error "Invalid partition: $data_input"
        fi
    done
    
    # Ask for LUKS encryption on existing partition
    print_warning "Do you want to encrypt the data partition with LUKS?"
    print_warning "This will FORMAT and ERASE all data on $DATA_PARTITION"
    print_prompt "Encrypt with LUKS? (y/N): "
    read -r luks_choice
    
    if [[ "$luks_choice" =~ ^[Yy]$ ]]; then
        USE_LUKS="yes"
        print_warning "Data partition will be encrypted with LUKS"
    else
        USE_LUKS="no"
    fi
}

get_data_partition_size() {
    local disk_size_bytes=$(lsblk -b -d -o SIZE "$TARGET_DEVICE" | tail -1)
    local disk_size_gb=$((disk_size_bytes / 1024 / 1024 / 1024))
    
    print_main "Target disk size: ${disk_size_gb}GB"
    
    while true; do
        print_prompt "Enter size for data partition in GB (or 'max' for remaining space): "
        read -r size_input
        
        if [[ "$size_input" == "max" ]]; then
            DATA_PARTITION_SIZE="100%"
            print_info "Using maximum available space"
            break
        elif [[ "$size_input" =~ ^[0-9]+$ ]] && [[ $size_input -gt 0 ]] && [[ $size_input -le $disk_size_gb ]]; then
            DATA_PARTITION_SIZE="$size_input"
            print_info "Data partition size: ${DATA_PARTITION_SIZE}GB"
            break
        else
            print_error "Invalid size. Please enter a number between 1 and $disk_size_gb, or 'max'"
        fi
    done
}

setup_luks_encryption() {
    local target_partition="$1"
    
    print_progress "Setting up LUKS encryption on $target_partition..."
    
    # Unmount if mounted
    umount "$target_partition" 2>/dev/null || true
    
    print_warning "You will now be prompted to enter a strong passphrase for LUKS encryption"
    print_info "Please use a secure passphrase that you will remember!"
    
    # Format with LUKS
    if ! cryptsetup luksFormat "$target_partition"; then
        print_error "Failed to format LUKS partition"
        exit 1
    fi
    
    print_info "Opening LUKS partition..."
    if ! cryptsetup luksOpen "$target_partition" "$LUKS_MAPPER"; then
        print_error "Failed to open LUKS partition"
        exit 1
    fi
    
    LUKS_DEVICE="/dev/mapper/$LUKS_MAPPER"
    print_success "LUKS partition opened as $LUKS_DEVICE"
    
    # Format the encrypted partition
    print_progress "Formatting encrypted partition as ext4..."
    if [[ -n "$OS_NAME" && "$OS_NAME" != "Unknown" ]]; then
        mkfs.ext4 -F -L "$OS_NAME" "$LUKS_DEVICE" >/dev/null 2>&1
    else
        mkfs.ext4 -F "$LUKS_DEVICE" >/dev/null 2>&1
    fi
    
    # Update DATA_PARTITION to point to the mapper device
    DATA_PARTITION="$LUKS_DEVICE"
    
    print_success "LUKS encryption setup completed"
}

create_new_partitions() {
    print_progress "Creating new partition table on $TARGET_DEVICE..."
    
    umount "${TARGET_DEVICE}"* 2>/dev/null || true
    
    local current_start="1MiB"
    
    if [[ "$INSTALL_TYPE" == "legacy_mbr" ]]; then
        parted -s "$TARGET_DEVICE" mklabel msdos
        
        if [[ "$USE_SEPARATE_BOOT" == "yes" ]]; then
            parted -s "$TARGET_DEVICE" mkpart primary "$BOOT_PARTITION_FS" "$current_start" "${BOOT_PARTITION_SIZE}MiB"
            parted -s "$TARGET_DEVICE" set 1 boot on
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                BOOT_PARTITION="${TARGET_DEVICE}p1"
            else
                BOOT_PARTITION="${TARGET_DEVICE}1"
            fi
            current_start="${BOOT_PARTITION_SIZE}MiB"
        fi
        
        get_data_partition_size
        if [[ "$DATA_PARTITION_SIZE" == "100%" ]]; then
            parted -s "$TARGET_DEVICE" mkpart primary ext4 "$current_start" 100%
        else
            parted -s "$TARGET_DEVICE" mkpart primary ext4 "$current_start" "${DATA_PARTITION_SIZE}GB"
        fi
        
        if [[ "$USE_SEPARATE_BOOT" == "yes" ]]; then
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                DATA_PARTITION="${TARGET_DEVICE}p2"
            else
                DATA_PARTITION="${TARGET_DEVICE}2"
            fi
        else
            parted -s "$TARGET_DEVICE" set 1 boot on
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                DATA_PARTITION="${TARGET_DEVICE}p1"
            else
                DATA_PARTITION="${TARGET_DEVICE}1"
            fi
        fi
        
    elif [[ "$INSTALL_TYPE" == "bios_gpt" ]]; then
        parted -s "$TARGET_DEVICE" mklabel gpt
        parted -s "$TARGET_DEVICE" mkpart BIOS_GRUB 1MiB 2MiB
        parted -s "$TARGET_DEVICE" set 1 bios_grub on
        current_start="2MiB"
        
        if [[ "$USE_SEPARATE_BOOT" == "yes" ]]; then
            local boot_end=$((2 + BOOT_PARTITION_SIZE))
            parted -s "$TARGET_DEVICE" mkpart BOOT "$BOOT_PARTITION_FS" "$current_start" "${boot_end}MiB"
            parted -s "$TARGET_DEVICE" set 2 boot on
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                BOOT_PARTITION="${TARGET_DEVICE}p2"
            else
                BOOT_PARTITION="${TARGET_DEVICE}2"
            fi
            current_start="${boot_end}MiB"
        fi
        
        get_data_partition_size
        if [[ "$DATA_PARTITION_SIZE" == "100%" ]]; then
            if [[ -n "$OS_NAME" && "$OS_NAME" != "Unknown" ]]; then
                parted -s "$TARGET_DEVICE" mkpart "$OS_NAME" ext4 "$current_start" 100%
            else
                parted -s "$TARGET_DEVICE" mkpart ROOT ext4 "$current_start" 100%
            fi
        else
            if [[ -n "$OS_NAME" && "$OS_NAME" != "Unknown" ]]; then
                parted -s "$TARGET_DEVICE" mkpart "$OS_NAME" ext4 "$current_start" "${DATA_PARTITION_SIZE}GB"
            else
                parted -s "$TARGET_DEVICE" mkpart ROOT ext4 "$current_start" "${DATA_PARTITION_SIZE}GB"
            fi
        fi
        
        if [[ "$USE_SEPARATE_BOOT" == "yes" ]]; then
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                DATA_PARTITION="${TARGET_DEVICE}p3"
            else
                DATA_PARTITION="${TARGET_DEVICE}3"
            fi
        else
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                DATA_PARTITION="${TARGET_DEVICE}p2"
            else
                DATA_PARTITION="${TARGET_DEVICE}2"
            fi
        fi
        
    elif [[ "$INSTALL_TYPE" == "uefi" ]]; then
        parted -s "$TARGET_DEVICE" mklabel gpt
        parted -s "$TARGET_DEVICE" mkpart EFI fat32 1MiB 101MiB
        parted -s "$TARGET_DEVICE" set 1 esp on
        if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
            EFI_PARTITION="${TARGET_DEVICE}p1"
        else
            EFI_PARTITION="${TARGET_DEVICE}1"
        fi
        current_start="101MiB"
        
        if [[ "$USE_SEPARATE_BOOT" == "yes" ]]; then
            local boot_end=$((101 + BOOT_PARTITION_SIZE))
            parted -s "$TARGET_DEVICE" mkpart BOOT "$BOOT_PARTITION_FS" "$current_start" "${boot_end}MiB"
            parted -s "$TARGET_DEVICE" set 2 boot on
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                BOOT_PARTITION="${TARGET_DEVICE}p2"
            else
                BOOT_PARTITION="${TARGET_DEVICE}2"
            fi
            current_start="${boot_end}MiB"
        fi
        
        get_data_partition_size
        if [[ "$DATA_PARTITION_SIZE" == "100%" ]]; then
            if [[ -n "$OS_NAME" && "$OS_NAME" != "Unknown" ]]; then
                parted -s "$TARGET_DEVICE" mkpart "$OS_NAME" ext4 "$current_start" 100%
            else
                parted -s "$TARGET_DEVICE" mkpart ROOT ext4 "$current_start" 100%
            fi
        else
            if [[ -n "$OS_NAME" && "$OS_NAME" != "Unknown" ]]; then
                parted -s "$TARGET_DEVICE" mkpart "$OS_NAME" ext4 "$current_start" "${DATA_PARTITION_SIZE}GB"
            else
                parted -s "$TARGET_DEVICE" mkpart ROOT ext4 "$current_start" "${DATA_PARTITION_SIZE}GB"
            fi
        fi
        
        if [[ "$USE_SEPARATE_BOOT" == "yes" ]]; then
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                DATA_PARTITION="${TARGET_DEVICE}p3"
            else
                DATA_PARTITION="${TARGET_DEVICE}3"
            fi
        else
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                DATA_PARTITION="${TARGET_DEVICE}p2"
            else
                DATA_PARTITION="${TARGET_DEVICE}2"
            fi
        fi
    fi
    
    sleep 2
    partprobe "$TARGET_DEVICE"
    sleep 2
    
    format_partitions
    print_success "Partitions created successfully"
}

format_partitions() {
    print_progress "Formatting partitions..."
    
    if [[ "$INSTALL_TYPE" == "uefi" && -n "$EFI_PARTITION" ]]; then
        print_progress "Formatting EFI partition as FAT32..."
        mkfs.fat -F32 -n "EFI" "$EFI_PARTITION" >/dev/null 2>&1
    fi
    
    if [[ "$USE_SEPARATE_BOOT" == "yes" && -n "$BOOT_PARTITION" ]]; then
        print_progress "Formatting boot partition as $BOOT_PARTITION_FS..."
        case "$BOOT_PARTITION_FS" in
            "ext2") mkfs.ext2 -F -L "BOOT" "$BOOT_PARTITION" >/dev/null 2>&1;;
            "ext3") mkfs.ext3 -F -L "BOOT" "$BOOT_PARTITION" >/dev/null 2>&1;;
            "ext4") mkfs.ext4 -F -L "BOOT" "$BOOT_PARTITION" >/dev/null 2>&1;;
        esac
    fi
    
    # Handle LUKS encryption for data partition
    if [[ "$USE_LUKS" == "yes" ]]; then
        setup_luks_encryption "$DATA_PARTITION"
    else
        print_progress "Formatting data partition as ext4..."
        if [[ -n "$OS_NAME" && "$OS_NAME" != "Unknown" ]]; then
            mkfs.ext4 -F -L "$OS_NAME" "$DATA_PARTITION" >/dev/null 2>&1
        else
            mkfs.ext4 -F "$DATA_PARTITION" >/dev/null 2>&1
        fi
    fi
    
    print_success "Partitions formatted successfully"
}

display_install_summary() {
    clear_and_header
    show_step "6" "Installation Summary"
    
    echo -e "${CYAN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║${NC}                    ${WHITE}INSTALLATION SUMMARY${NC}                   ${CYAN}║${NC}"
    echo -e "${CYAN}╠══════════════════════════════════════════════════════════╣${NC}"
    echo -e "${CYAN}║${NC} Source:           ${WHITE}$INSTALL_SOURCE${NC}"
    echo -e "${CYAN}║${NC} Target Device:    ${WHITE}$TARGET_DEVICE${NC}"
    echo -e "${CYAN}║${NC} Install Type:     ${WHITE}$INSTALL_TYPE${NC}"
    echo -e "${CYAN}║${NC} OS Name:          ${WHITE}$OS_NAME${NC}"
    echo -e "${CYAN}║${NC} Data Partition:   ${WHITE}$DATA_PARTITION${NC}"
    [[ -n "$EFI_PARTITION" ]] && echo -e "${CYAN}║${NC} EFI Partition:    ${WHITE}$EFI_PARTITION${NC}"
    [[ "$USE_SEPARATE_BOOT" == "yes" ]] && echo -e "${CYAN}║${NC} Boot Partition:   ${WHITE}$BOOT_PARTITION ($BOOT_PARTITION_FS)${NC}"
    echo -e "${CYAN}║${NC} Use Existing:     ${WHITE}$USE_EXISTING_PARTITIONS${NC}"
    [[ "$USE_LUKS" == "yes" ]] && echo -e "${CYAN}║${NC} LUKS Encryption:  ${WHITE}Enabled${NC}"
    [[ "$IS_LOOP_DEVICE" == "yes" ]] && echo -e "${CYAN}║${NC} Loop Device:      ${WHITE}Yes${NC}"
    echo -e "${CYAN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    
    print_warning "Please verify the above settings before proceeding!"
    print_prompt "Continue with installation? (y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        print_info "Installation cancelled by user"
        exit 0
    fi
}

mount_source() {
    if [[ "$INSTALL_SOURCE" == "/" ]]; then
        print_info "Using current root filesystem as source"
        return 0
    fi
    
    print_progress "Mounting source filesystem..."
    mkdir -p "$MOUNT_LIVE"
    
    if mount -t squashfs -o loop "$INSTALL_SOURCE" "$MOUNT_LIVE" 2>/dev/null; then
        print_success "Source mounted at $MOUNT_LIVE"
        INSTALL_SOURCE="$MOUNT_LIVE"
    else
        print_error "Failed to mount source filesystem"
        exit 1
    fi
}

mount_target() {
    print_progress "Mounting target partitions..."
    
    mkdir -p "$MOUNT_TARGET"
    
    if mount "$DATA_PARTITION" "$MOUNT_TARGET"; then
        print_success "Data partition mounted"
    else
        print_error "Failed to mount data partition"
        exit 1
    fi
    
    if [[ "$USE_SEPARATE_BOOT" == "yes" && -n "$BOOT_PARTITION" ]]; then
        mkdir -p "$MOUNT_TARGET/boot"
        if mount "$BOOT_PARTITION" "$MOUNT_TARGET/boot"; then
            print_success "Boot partition mounted"
        else
            print_error "Failed to mount boot partition"
            exit 1
        fi
    fi
    
    if [[ "$INSTALL_TYPE" == "uefi" && -n "$EFI_PARTITION" ]]; then
        mkdir -p "$MOUNT_TARGET/boot/efi"
        if mount "$EFI_PARTITION" "$MOUNT_TARGET/boot/efi"; then
            print_success "EFI partition mounted"
        else
            print_error "Failed to mount EFI partition"
            exit 1
        fi
    fi
}

show_rsync_progress() {
    local source="$1"
    local target="$2"
    local exclude_args=("${@:3}")
    
    print_main "Calculating transfer size..."
    
    # Get source info
    local total_size total_files
    if [[ "$source" == "/" ]]; then
        total_size=$(du -sb /usr /etc /bin /sbin /lib* /opt /var /home 2>/dev/null | awk '{sum+=$1} END {print sum}')
        total_files=$(find /usr /etc /bin /sbin /lib* /opt /var /home -type f 2>/dev/null | wc -l)
    else
        total_size=$(du -sb "$source" 2>/dev/null | cut -f1)
        total_files=$(find "$source" -type f 2>/dev/null | wc -l)
    fi
    
    local total_mb=$((total_size / 1024 / 1024))
    print_success "Found $(printf "%'d" $total_files) files (${total_mb}MB)"
    echo
    
    # Clear screen and start at top
    clear
    
    # Create control file
    local control_file="/tmp/progress_control_$"
    echo "running" > "$control_file"
    
    # Simple progress monitor
    {
        local start_time=$(date +%s)
        local last_size=0
        local last_time=$start_time
        
        while [[ -f "$control_file" && "$(cat "$control_file")" == "running" ]]; do
            # Move to top of screen
            printf "\033[1;1H"
            
            # Get current status
            local current_size=0
            local current_files=0
            if [[ -d "$target" ]]; then
                current_size=$(du -sb "$target" 2>/dev/null | cut -f1 || echo "0")
                current_files=$(find "$target" -type f 2>/dev/null | wc -l || echo "0")
            fi
            
            local current_mb=$((current_size / 1024 / 1024))
            local progress_percent=0
            if [[ $total_size -gt 0 ]]; then
                progress_percent=$((current_size * 100 / total_size))
            fi
            
            # Calculate speed and ETA
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            local eta="calculating"
            
            if [[ $elapsed -gt 10 && $progress_percent -gt 3 ]]; then
                local speed_mb=0
                if [[ $elapsed -gt 0 ]]; then
                    speed_mb=$((current_mb / elapsed))
                fi
                
                if [[ $speed_mb -gt 0 ]]; then
                    local remaining_mb=$((total_mb - current_mb))
                    local eta_seconds=$((remaining_mb / speed_mb))
                    local eta_minutes=$((eta_seconds / 60))
                    if [[ $eta_minutes -gt 0 ]]; then
                        eta="${eta_minutes} min"
                    else
                        eta="${eta_seconds}s"
                    fi
                fi
            fi
            
            # Progress bar
            local border_line="┌─ Installation Progress ─────────────────────────────────────────────────────────────────────────┐"
            local border_width=${#border_line}
            
            local prefix="│ ["
            local suffix="] $(printf "%3d" $progress_percent)% │"
            local reserved_chars=$((${#prefix} + ${#suffix}))
            local available_width=$((border_width - reserved_chars))
            
            local bar=""
            local bar_length=$available_width
            local filled=$((progress_percent * bar_length / 100))
            for ((i=0; i<filled; i++)); do bar+="█"; done
            for ((i=filled; i<bar_length; i++)); do bar+="░"; done
            
            echo "┌─ Installation Progress ─────────────────────────────────────────────────────────────────────────┐"
            printf "│ [%s] %3d%% │\n" "$bar" "$progress_percent"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────────────┘"
            printf "│   Files:   %6d / %-6d    ¦ Data: %4dMB / %-4dMB   ¦  Time: %2ds   |   ETA: %-7s │\n" \
                "$current_files" "$total_files" "$current_mb" "$total_mb" "$elapsed" "$eta"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────────────┘"
            
            printf "\033[J"
            
            sleep 2
        done
    } &
    local monitor_pid=$!
    
    # Start rsync
    rsync -a "${exclude_args[@]}" "$source/" "$target/" >/dev/null 2>&1
    local rsync_exit=$?
    
    # Stop monitor
    echo "finished" > "$control_file"
    sleep 1
    kill $monitor_pid 2>/dev/null || true
    wait $monitor_pid 2>/dev/null || true
    rm -f "$control_file"
    
    # Return to normal screen
    clear_and_header
    
    if [[ $rsync_exit -eq 0 ]]; then
        print_success "✓ File transfer completed successfully"
    else
        print_error "✗ File transfer failed"
        return $rsync_exit
    fi
}

sync_filesystem() {
    clear_and_header
    show_step "7" "Installing System Files"
    
    local exclude_dirs=(
        "--exclude=/proc/*"
        "--exclude=/sys/*" 
        "--exclude=/dev/*"
        "--exclude=/run/*"
        "--exclude=/tmp/*"
        "--exclude=/mnt/*"
        "--exclude=/media/*"
        "--exclude=/swapfile"
        "--exclude=/swap.img"
        "--exclude=lost+found"
    )
    
    if [[ "$INSTALL_SOURCE" == "/" ]]; then
        exclude_dirs+=(
            "--exclude=/home/*/.cache/*"
            "--exclude=/var/cache/*"
            "--exclude=/var/tmp/*"
            "--exclude=/var/log/*"
        )
    fi
    
    show_rsync_progress "$INSTALL_SOURCE" "$MOUNT_TARGET" "${exclude_dirs[@]}"
}

prepare_chroot() {
    print_progress "Preparing chroot environment..."
    
    mount --bind /dev "$MOUNT_TARGET/dev"
    mount --bind /proc "$MOUNT_TARGET/proc"
    mount --bind /sys "$MOUNT_TARGET/sys"
    mount --bind /run "$MOUNT_TARGET/run"
    mount -t devpts devpts "$MOUNT_TARGET/dev/pts"
    
    cp /etc/resolv.conf "$MOUNT_TARGET/etc/resolv.conf"
    
    print_success "Chroot environment ready"
}

update_fstab() {
    print_progress "Updating fstab..."
    
    cp "$MOUNT_TARGET/etc/fstab" "$MOUNT_TARGET/etc/fstab.backup" 2>/dev/null || true
    
    {
        echo "# <file system> <mount point> <type> <options> <dump> <pass>"
        
        if [[ "$USE_LUKS" == "yes" ]]; then
            # For LUKS, use the mapper device UUID
            echo "UUID=$(blkid -o value -s UUID "$LUKS_DEVICE") / $(blkid -o value -s TYPE "$LUKS_DEVICE") defaults 0 1"
        else
            echo "UUID=$(blkid -o value -s UUID "$DATA_PARTITION") / $(blkid -o value -s TYPE "$DATA_PARTITION") defaults 0 1"
        fi
        
        if [[ "$USE_SEPARATE_BOOT" == "yes" && -n "$BOOT_PARTITION" ]]; then
            echo "UUID=$(blkid -o value -s UUID "$BOOT_PARTITION") /boot $(blkid -o value -s TYPE "$BOOT_PARTITION") defaults 0 2"
        fi
        
        if [[ "$INSTALL_TYPE" == "uefi" && -n "$EFI_PARTITION" ]]; then
            echo "UUID=$(blkid -o value -s UUID "$EFI_PARTITION") /boot/efi vfat umask=0077 0 2"
        fi
        
        echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0"
    } > "$MOUNT_TARGET/etc/fstab"
    
    print_success "fstab updated"
}

update_crypttab() {
    if [[ "$USE_LUKS" == "yes" ]]; then
        print_progress "Updating crypttab for LUKS..."
        
        local luks_uuid
        if [[ "$USE_EXISTING_PARTITIONS" == "yes" ]]; then
            # For existing partitions, get UUID of the original partition
            luks_uuid=$(blkid -o value -s UUID "${DATA_PARTITION%p*}" 2>/dev/null || blkid -o value -s UUID "${DATA_PARTITION%[0-9]*}" 2>/dev/null)
        else
            # For new partitions, get UUID of the partition before LUKS setup
            local original_partition
            if [[ "$IS_LOOP_DEVICE" == "yes" ]]; then
                if [[ "$USE_SEPARATE_BOOT" == "yes" ]]; then
                    original_partition="${TARGET_DEVICE}p3"
                else
                    original_partition="${TARGET_DEVICE}p2"
                fi
            else
                if [[ "$USE_SEPARATE_BOOT" == "yes" ]]; then
                    if [[ "$INSTALL_TYPE" == "uefi" ]]; then
                        original_partition="${TARGET_DEVICE}3"
                    else
                        original_partition="${TARGET_DEVICE}2"
                    fi
                else
                    if [[ "$INSTALL_TYPE" == "uefi" ]]; then
                        original_partition="${TARGET_DEVICE}2"
                    else
                        original_partition="${TARGET_DEVICE}1"
                    fi
                fi
            fi
            luks_uuid=$(blkid -o value -s UUID "$original_partition" 2>/dev/null)
        fi
        
        if [[ -n "$luks_uuid" ]]; then
            echo "$LUKS_MAPPER UUID=$luks_uuid none luks,discard" > "$MOUNT_TARGET/etc/crypttab"
            print_success "crypttab updated with LUKS configuration"
        else
            print_warning "Could not determine LUKS UUID for crypttab"
        fi
    fi
}

install_grub() {
    clear_and_header
    show_step "8" "Installing Bootloader"
    
    case "$INSTALL_TYPE" in
        "legacy_mbr"|"bios_gpt")
            print_progress "Installing GRUB for BIOS systems..."
            chroot "$MOUNT_TARGET" /bin/bash -c "
                export DEBIAN_FRONTEND=noninteractive
                apt-get update >/dev/null 2>&1
                apt-get install -y grub-pc >/dev/null 2>&1
                grub-install --recheck $TARGET_DEVICE >/dev/null 2>&1
                update-grub >/dev/null 2>&1
            " 2>/dev/null
            ;;
            
        "uefi")
            print_progress "Installing GRUB for UEFI systems..."
            chroot "$MOUNT_TARGET" /bin/bash -c "
                export DEBIAN_FRONTEND=noninteractive
                apt-get update >/dev/null 2>&1
                apt-get install -y grub-efi-amd64 efibootmgr >/dev/null 2>&1
                grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Debian --recheck >/dev/null 2>&1
                update-grub >/dev/null 2>&1
            " 2>/dev/null
            ;;
    esac
    
    print_success "Bootloader installation completed"
    sleep 1
}

setup_live_boot() {
    clear_and_header
    show_step "9" "Live Boot Setup (Optional)"
    
    print_main "Would you like to add live boot capabilities to the installed system?"
    print_info "This allows booting the installed system as a live environment"
    echo
    
    print_prompt "Setup live boot? (y/N): "
    read -r setup_live
    
    if [[ "$setup_live" =~ ^[Yy]$ ]]; then
        print_progress "Setting up live boot environment..."
        
        # Create directory structure
        mkdir -p "$MOUNT_TARGET/boot/live"
        
        if [[ -n "$ORIGINAL_SQUASHFS" && -f "$ORIGINAL_SQUASHFS" ]]; then
            print_progress "Copying squashfs to target system..."
            cp "$ORIGINAL_SQUASHFS" "$MOUNT_TARGET/boot/live/filesystem.squashfs"
            print_success "Squashfs copied to /boot/live/filesystem.squashfs"
        elif [[ -f "/run/live/medium/live/filesystem.squashfs" ]]; then
            print_progress "Copying Debian squashfs to target system..."
            cp "/run/live/medium/live/filesystem.squashfs" "$MOUNT_TARGET/boot/live/filesystem.squashfs"
            print_success "Squashfs copied to /boot/live/filesystem.squashfs"
        elif [[ -f "/cdrom/casper/filesystem.squashfs" ]]; then
            print_progress "Copying Ubuntu squashfs to target system..."
            cp "/cdrom/casper/filesystem.squashfs" "$MOUNT_TARGET/boot/live/filesystem.squashfs"
            print_success "Squashfs copied to /boot/live/filesystem.squashfs"
        else
            print_warning "No squashfs file found to copy"
            return
        fi
        
        print_progress "Updating GRUB configuration..."
        chroot "$MOUNT_TARGET" /bin/bash -c "update-grub >/dev/null 2>&1" 2>/dev/null
        
        print_success "Live boot setup completed"
    else
        print_info "Skipping live boot setup"
    fi
    
    sleep 1
}

verify_installation() {
    clear_and_header
    show_step "10" "Verifying Installation"
    
    local errors=0
    
    if ls "$MOUNT_TARGET/boot/vmlinuz-"* 1>/dev/null 2>&1; then
        print_success "✓ Kernel found"
    else
        print_error "✗ No kernel found"
        ((errors++))
    fi
    
    if ls "$MOUNT_TARGET/boot/initrd.img-"* 1>/dev/null 2>&1; then
        print_success "✓ Initramfs found"
    else
        print_error "✗ No initramfs found"
        ((errors++))
    fi
    
    if [[ -f "$MOUNT_TARGET/boot/grub/grub.cfg" ]]; then
        print_success "✓ GRUB configuration found"
    else
        print_error "✗ GRUB configuration missing"
        ((errors++))
    fi
    
    if [[ -f "$MOUNT_TARGET/etc/fstab" ]]; then
        if [[ "$USE_LUKS" == "yes" ]]; then
            if grep -q "$(blkid -o value -s UUID "$LUKS_DEVICE")" "$MOUNT_TARGET/etc/fstab"; then
                print_success "✓ fstab configured correctly for LUKS"
            else
                print_error "✗ fstab LUKS configuration issue"
                ((errors++))
            fi
        else
            if grep -q "$(blkid -o value -s UUID "$DATA_PARTITION")" "$MOUNT_TARGET/etc/fstab"; then
                print_success "✓ fstab configured correctly"
            else
                print_error "✗ fstab configuration issue"
                ((errors++))
            fi
        fi
    else
        print_error "✗ fstab missing"
        ((errors++))
    fi
    
    if [[ "$USE_LUKS" == "yes" ]]; then
        if [[ -f "$MOUNT_TARGET/etc/crypttab" ]] && grep -q "$LUKS_MAPPER" "$MOUNT_TARGET/etc/crypttab"; then
            print_success "✓ crypttab configured for LUKS"
        else
            print_warning "⚠ crypttab configuration may be incomplete"
        fi
    fi
    
    if [[ "$INSTALL_TYPE" == "uefi" ]]; then
        if [[ -f "$MOUNT_TARGET/boot/efi/EFI/BOOT/bootx64.efi" ]] || [[ -d "$MOUNT_TARGET/boot/efi/EFI/debian" ]] || [[ -d "$MOUNT_TARGET/boot/efi/EFI/Debian" ]]; then
            print_success "✓ UEFI bootloader found"
        else
            print_warning "⚠ UEFI bootloader may not be properly installed"
        fi
    fi
    
    if [[ -f "$MOUNT_TARGET/boot/live/filesystem.squashfs" ]]; then
        print_success "✓ Live boot environment configured"
    fi
    
    if [[ $errors -eq 0 ]]; then
        print_success "Installation verification passed!"
        return 0
    else
        print_warning "Installation completed with $errors potential issues"
        return 1
    fi
}

cleanup_mounts() {
    # Close LUKS device if it was opened
    if [[ "$USE_LUKS" == "yes" && -b "$LUKS_DEVICE" ]]; then
        print_progress "Closing LUKS device..."
        cryptsetup luksClose "$LUKS_MAPPER" 2>/dev/null || true
    fi
    
    umount "$MOUNT_TARGET/dev/pts" 2>/dev/null || true
    umount "$MOUNT_TARGET/run" 2>/dev/null || true
    umount "$MOUNT_TARGET/sys" 2>/dev/null || true
    umount "$MOUNT_TARGET/proc" 2>/dev/null || true
    umount "$MOUNT_TARGET/dev" 2>/dev/null || true
    
    if [[ "$INSTALL_TYPE" == "uefi" && -n "$EFI_PARTITION" ]]; then
        umount "$MOUNT_TARGET/boot/efi" 2>/dev/null || true
    fi
    
    if [[ "$USE_SEPARATE_BOOT" == "yes" && -n "$BOOT_PARTITION" ]]; then
        umount "$MOUNT_TARGET/boot" 2>/dev/null || true
    fi
    
    umount "$MOUNT_TARGET" 2>/dev/null || true
    
    if [[ "$INSTALL_SOURCE" == "$MOUNT_LIVE" ]]; then
        umount "$MOUNT_LIVE" 2>/dev/null || true
    fi
}

show_completion() {
    clear_and_header
    
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}${WHITE}                INSTALLATION COMPLETED SUCCESSFULLY!${NC}            ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    
    print_main "Installation Details:"
    echo -e "  ${CYAN}•${NC} Target Device:   ${WHITE}$TARGET_DEVICE${NC}" 
    echo -e "  ${CYAN}•${NC} Data Partition:  ${WHITE}$DATA_PARTITION${NC}"
    [[ -n "$EFI_PARTITION" ]] && echo -e "  ${CYAN}•${NC} EFI Partition:   ${WHITE}$EFI_PARTITION${NC}"
    [[ "$USE_SEPARATE_BOOT" == "yes" ]] && echo -e "  ${CYAN}•${NC} Boot Partition:  ${WHITE}$BOOT_PARTITION ($BOOT_PARTITION_FS)${NC}"
    echo -e "  ${CYAN}•${NC} Boot Type:       ${WHITE}$INSTALL_TYPE${NC}"
    echo -e "  ${CYAN}•${NC} OS Name:         ${WHITE}$OS_NAME${NC}"
    [[ "$USE_LUKS" == "yes" ]] && echo -e "  ${CYAN}•${NC} LUKS Encryption: ${WHITE}Enabled${NC}"
    [[ "$IS_LOOP_DEVICE" == "yes" ]] && echo -e "  ${CYAN}•${NC} Loop Device:     ${WHITE}Yes${NC}"
    [[ -f "$MOUNT_TARGET/boot/live/filesystem.squashfs" ]] && echo -e "  ${CYAN}•${NC} Live Boot:       ${WHITE}Enabled${NC}"
    echo
    
    if [[ "$USE_LUKS" == "yes" ]]; then
        print_warning "IMPORTANT: Remember your LUKS passphrase - you'll need it to boot!"
        echo
    fi
    
    print_warning "Remove installation media and reboot to use the new system"
    echo
}

main() {
    check_root
    
    install_dependencies
    select_install_source
    select_install_type
    select_target_disk
    select_partitioning_method
    display_install_summary
    
    clear_and_header
    show_step "7" "Beginning Installation"
    
    mount_source
    mount_target
    sync_filesystem
    prepare_chroot
    update_fstab
    update_crypttab
    install_grub
    setup_live_boot
    
    if verify_installation; then
        show_completion
    else
        clear_and_header
        print_warning "Installation completed with some issues - please review before rebooting"
    fi
    
    cleanup_mounts
}

trap cleanup_mounts EXIT

main "$@"
