#!/bin/bash

# Enhanced Debian Live Installer - Simple Clean Progress Version
# ONLY the progress function is changed - everything else identical

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
USE_EXISTING_PARTITIONS=""
DATA_PARTITION_SIZE=""
ORIGINAL_SQUASHFS=""

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
    
    local packages=("rsync" "parted" "gdisk" "dosfstools" "e2fsprogs" "pv" "dialog")
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
                if [[ -f "/run/live/medium/live/filesystem.squashfs" ]]; then
                    INSTALL_SOURCE="/run/live/medium/live/filesystem.squashfs"
                    ORIGINAL_SQUASHFS="$INSTALL_SOURCE"
                    print_info "Detected live environment, using: $INSTALL_SOURCE"
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
    
    while true; do
        print_prompt "Enter target disk (e.g., sda, nvme0n1): "
        read -r disk_input
        
        if [[ ! "$disk_input" =~ ^/dev/ ]]; then
            disk_input="/dev/$disk_input"
        fi
        
        if [[ -b "$disk_input" ]]; then
            TARGET_DEVICE="$disk_input"
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

select_existing_partitions() {
    print_main "Current partition layout for $TARGET_DEVICE:"
    lsblk "$TARGET_DEVICE"
    echo
    
    if [[ "$INSTALL_TYPE" == "uefi" ]]; then
        while true; do
            print_prompt "Enter EFI System Partition (e.g., ${TARGET_DEVICE}1): "
            read -r efi_input
            
            if [[ ! "$efi_input" =~ ^/dev/ ]]; then
                efi_input="${TARGET_DEVICE}${efi_input##*[a-z]}"
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
    
    while true; do
        print_prompt "Enter data/root partition (e.g., ${TARGET_DEVICE}2): "
        read -r data_input
        
        if [[ ! "$data_input" =~ ^/dev/ ]]; then
            data_input="${TARGET_DEVICE}${data_input##*[a-z]}"
        fi
        
        if [[ -b "$data_input" ]]; then
            DATA_PARTITION="$data_input"
            print_success "Selected data partition: $DATA_PARTITION"
            break
        else
            print_error "Invalid partition: $data_input"
        fi
    done
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

create_new_partitions() {
    print_progress "Creating new partition table on $TARGET_DEVICE..."
    
    umount "${TARGET_DEVICE}"* 2>/dev/null || true
    
    if [[ "$INSTALL_TYPE" == "legacy_mbr" ]]; then
        parted -s "$TARGET_DEVICE" mklabel msdos
        get_data_partition_size
        if [[ "$DATA_PARTITION_SIZE" == "100%" ]]; then
            parted -s "$TARGET_DEVICE" mkpart primary ext4 1MiB 100%
        else
            parted -s "$TARGET_DEVICE" mkpart primary ext4 1MiB "${DATA_PARTITION_SIZE}GB"
        fi
        parted -s "$TARGET_DEVICE" set 1 boot on
        DATA_PARTITION="${TARGET_DEVICE}1"
        
    elif [[ "$INSTALL_TYPE" == "bios_gpt" ]]; then
        parted -s "$TARGET_DEVICE" mklabel gpt
        parted -s "$TARGET_DEVICE" mkpart BIOS_GRUB 1MiB 2MiB
        parted -s "$TARGET_DEVICE" set 1 bios_grub on
        get_data_partition_size
        if [[ "$DATA_PARTITION_SIZE" == "100%" ]]; then
            parted -s "$TARGET_DEVICE" mkpart primary ext4 2MiB 100%
        else
            parted -s "$TARGET_DEVICE" mkpart primary ext4 2MiB "${DATA_PARTITION_SIZE}GB"
        fi
        DATA_PARTITION="${TARGET_DEVICE}2"
        
    elif [[ "$INSTALL_TYPE" == "uefi" ]]; then
        parted -s "$TARGET_DEVICE" mklabel gpt
        parted -s "$TARGET_DEVICE" mkpart Bonsai-EFI fat32 1MiB 81MiB
        parted -s "$TARGET_DEVICE" set 1 esp on
        get_data_partition_size
        if [[ "$DATA_PARTITION_SIZE" == "100%" ]]; then
            parted -s "$TARGET_DEVICE" mkpart Bonsai-ROOT ext4 81MiB 100%
        else
            parted -s "$TARGET_DEVICE" mkpart Bonsai-ROOT ext4 81MiB "${DATA_PARTITION_SIZE}GB"
        fi
        EFI_PARTITION="${TARGET_DEVICE}1"
        DATA_PARTITION="${TARGET_DEVICE}2"
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
        mkfs.fat -F32 -n "Bonsai-EFI" "$EFI_PARTITION" >/dev/null 2>&1
    fi
    
    print_progress "Formatting data partition as ext4..."
    mkfs.ext4 -F -L "Bonsai-ROOT" "$DATA_PARTITION" >/dev/null 2>&1
    
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
    echo -e "${CYAN}║${NC} Data Partition:   ${WHITE}$DATA_PARTITION${NC}"
    [[ -n "$EFI_PARTITION" ]] && echo -e "${CYAN}║${NC} EFI Partition:    ${WHITE}$EFI_PARTITION${NC}"
    echo -e "${CYAN}║${NC} Use Existing:     ${WHITE}$USE_EXISTING_PARTITIONS${NC}"
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

# SIMPLE: Clean progress bar that stays at top and doesn't jump
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
    local control_file="/tmp/progress_control_$$"
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
            
            # Calculate speed
            local current_time=$(date +%s)
            local elapsed=$((current_time - start_time))
            local speed_mb=0
            
            if [[ $elapsed -gt 0 && $current_time != $last_time ]]; then
                local size_diff=$((current_size - last_size))
                local time_diff=$((current_time - last_time))
                if [[ $time_diff -gt 0 ]]; then
                    speed_mb=$((size_diff / 1024 / 1024 / time_diff))
                fi
                last_size=$current_size
                last_time=$current_time
            fi
            
            # Calculate ETA
            local eta="calculating..."
            if [[ $speed_mb -gt 0 && $progress_percent -gt 3 ]]; then
                local remaining_mb=$((total_mb - current_mb))
                local eta_seconds=$((remaining_mb / speed_mb))
                local eta_minutes=$((eta_seconds / 60))
                if [[ $eta_minutes -gt 0 ]]; then
                    eta="${eta_minutes} min"
                else
                    eta="${eta_seconds}s"
                fi
            fi
            
            # Create progress bar
            local bar=""
            local bar_length=50
            local filled=$((progress_percent * bar_length / 100))
            for ((i=0; i<filled; i++)); do bar+="█"; done
            for ((i=filled; i<bar_length; i++)); do bar+="░"; done
            
                  
                   # ███████████████████████████████████████████████████████████████████████████████████████████████

            # Display
            echo "┌─ Installation Progress ─────────────────────────────────────────────────────────────────────────┐"
            printf "│ [%s] %3d%% │\n" "$bar" "$progress_percent"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────────────┘"
            printf "│ Files: %'d / %'d ¦ Data: %'dMB / %'dMB ¦ Time: %ds elapsed | ETA: %s │\n" \
                "$current_files" "$total_files" "$current_mb" "$total_mb" "$elapsed" "$eta"
            echo "└─────────────────────────────────────────────────────────────────────────────────────────────────┘"
            
            # Clear rest of screen
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
        echo "UUID=$(blkid -o value -s UUID "$DATA_PARTITION") / $(blkid -o value -s TYPE "$DATA_PARTITION") defaults 0 1"
        
        if [[ "$INSTALL_TYPE" == "uefi" && -n "$EFI_PARTITION" ]]; then
            echo "UUID=$(blkid -o value -s UUID "$EFI_PARTITION") /boot/efi vfat umask=0077 0 2"
        fi
        
        echo "tmpfs /tmp tmpfs defaults,noatime,mode=1777 0 0"
    } > "$MOUNT_TARGET/etc/fstab"
    
    print_success "fstab updated"
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
        
        mkdir -p "$MOUNT_TARGET/boot/live"
        
        if [[ -n "$ORIGINAL_SQUASHFS" && -f "$ORIGINAL_SQUASHFS" ]]; then
            print_progress "Copying squashfs to target system..."
            cp "$ORIGINAL_SQUASHFS" "$MOUNT_TARGET/boot/live/filesystem.squashfs"
            print_success "Squashfs copied to /boot/live/filesystem.squashfs"
        elif [[ -f "/run/live/medium/live/filesystem.squashfs" ]]; then
            print_progress "Copying default squashfs to target system..."
            cp "/run/live/medium/live/filesystem.squashfs" "$MOUNT_TARGET/boot/live/filesystem.squashfs"
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
    
    if [[ -f "$MOUNT_TARGET/etc/fstab" ]] && grep -q "$(blkid -o value -s UUID "$DATA_PARTITION")" "$MOUNT_TARGET/etc/fstab"; then
        print_success "✓ fstab configured correctly"
    else
        print_error "✗ fstab configuration issue"
        ((errors++))
    fi
    
    if [[ "$INSTALL_TYPE" == "uefi" ]]; then
        if [[ -f "$MOUNT_TARGET/boot/efi/EFI/BOOT/bootx64.efi" ]] || [[ -d "$MOUNT_TARGET/boot/efi/EFI/debian" ]] || [[ -d "$MOUNT_TARGET/boot/efi/EFI/Debian" ]]; then
            print_success "✓ UEFI bootloader found"
        else
            print_warning "⚠ UEFI bootloader may not be properly installed"
        fi
    fi
    
    if [[ -f "$MOUNT_TARGET/live/filesystem.squashfs" ]]; then
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
    umount "$MOUNT_TARGET/dev/pts" 2>/dev/null || true
    umount "$MOUNT_TARGET/run" 2>/dev/null || true
    umount "$MOUNT_TARGET/sys" 2>/dev/null || true
    umount "$MOUNT_TARGET/proc" 2>/dev/null || true
    umount "$MOUNT_TARGET/dev" 2>/dev/null || true
    
    if [[ "$INSTALL_TYPE" == "uefi" && -n "$EFI_PARTITION" ]]; then
        umount "$MOUNT_TARGET/boot/efi" 2>/dev/null || true
    fi
    umount "$MOUNT_TARGET" 2>/dev/null || true
    
    if [[ "$INSTALL_SOURCE" == "$MOUNT_LIVE" ]]; then
        umount "$MOUNT_LIVE" 2>/dev/null || true
    fi
}

show_completion() {
    clear_and_header
    
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║${NC}${WHITE}INSTALLATION COMPLETED SUCCESSFULLY!${NC}            ${GREEN}║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════╝${NC}"
    echo
    
    print_main "Installation Details:"
    echo -e "  ${CYAN}•${NC} Target Device:   ${WHITE}$TARGET_DEVICE${NC}" 
    echo -e "  ${CYAN}•${NC} Data Partition:  ${WHITE}$DATA_PARTITION${NC}"
    [[ -n "$EFI_PARTITION" ]] && echo -e "  ${CYAN}•${NC} EFI Partition:   ${WHITE}$EFI_PARTITION${NC}"
    echo -e "  ${CYAN}•${NC} Boot Type:       ${WHITE}$INSTALL_TYPE${NC}"
    [[ -f "$MOUNT_TARGET/live/filesystem.squashfs" ]] && echo -e "  ${CYAN}•${NC} Live Boot:       ${WHITE}Enabled${NC}"
    echo
    
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
