#!/bin/bash

# Enhanced ISO Creator with Rebuild and Preconfigured Path Support

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Install minimal dependencies
install_dependencies() {
    local missing_deps=()
    for cmd in xorriso wget lzma tar; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${BLUE}Installing required packages: ${missing_deps[*]}${NC}"
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update && sudo apt-get install -y xorriso wget xz-utils tar isolinux
        elif [ -x "$(command -v dnf)" ]; then
            sudo dnf install -y xorriso wget xz tar syslinux
        elif [ -x "$(command -v pacman)" ]; then
            sudo pacman -S --noconfirm xorriso wget xz tar syslinux
        else
            echo -e "${RED}Error: Cannot install dependencies automatically${NC}"
            exit 1
        fi
    fi
}

download_bootfiles() {
    local target_dir="$1"
    local temp_dir="/tmp/nano_bootfiles_$RANDOM"
    
    echo -e "${BLUE}Downloading ISO base structure...${NC}"
    mkdir -p "$temp_dir"
    
    if ! wget -q --progress=bar:force \
        "https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/HYBRID-BOOTFILES.tar.lzma" \
        -O "$temp_dir/bootfiles.tar.lzma"; then
        echo -e "${RED}Error: Failed to download base ISO files${NC}"
        rm -rf "$temp_dir"
        return 1
    fi
    
    echo -e "${BLUE}Building ISO structure in: $target_dir${NC}"
    unlzma "$temp_dir/bootfiles.tar.lzma"
    tar -xf "$temp_dir/bootfiles.tar" -C "$target_dir" --strip-components=1
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✅ Base ISO files installed${NC}"
    return 0
}

create_grub_config() {
    local iso_dir="$1"
    local name="$2"
    local vmlinuz="$3"
    local initrd="$4"
    local live_dir="$5"
    
    mkdir -p "$iso_dir/boot/grub"
    
    cat > "$iso_dir/boot/grub/grub.cfg" <<EOF
# GRUB2 Configuration
set timeout=10
set default=0

menuentry "$name - LIVE" {
    linux /$live_dir/$vmlinuz boot=$live_dir quiet splash
    initrd /$live_dir/$initrd
}

menuentry "$name - Safe Graphics" {
    linux /$live_dir/$vmlinuz boot=$live_dir nomodeset
    initrd /$live_dir/$initrd
}

menuentry "Reboot" {
    reboot
}

menuentry "Power Off" {
    halt
}
EOF
    echo -e "${GREEN}GRUB configuration created${NC}"
}

create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local volume_label="$3"
    
    echo -e "${BLUE}Building ISO: $output_file${NC}"
    
    xorriso -as mkisofs \
        -volid "$volume_label" \
        -isohybrid-mbr /usr/lib/ISOLINUX/isohdpfx.bin \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -o "$output_file" \
        "$source_dir" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✅ ISO created: $output_file${NC}"
        return 0
    else
        echo -e "${RED}❌ ISO creation failed${NC}"
        return 1
    fi
}

build_from_existing() {
    local target_dir="$1"
    
    echo -e "\n${YELLOW}=== BUILD FROM EXISTING DIRECTORY ===${NC}"
    echo -e "Using preconfigured path: $target_dir"
    
    # Detect live system
    local live_dir=""
    [ -d "$target_dir/live" ] && live_dir="live"
    [ -d "$target_dir/casper" ] && live_dir="casper"
    
    if [ -z "$live_dir" ]; then
        echo -e "${RED}Error: No live/ or casper/ directory found${NC}"
        return 1
    fi
    
    # Find kernel/initrd
    local vmlinuz=$(find "$target_dir/$live_dir" -name 'vmlinuz*' -printf '%f\n' | head -1)
    local initrd=$(find "$target_dir/$live_dir" -name 'initrd*' -printf '%f\n' | head -1)
    
    if [ -z "$vmlinuz" ] || [ -z "$initrd" ]; then
        echo -e "${RED}Error: Missing kernel or initrd in $live_dir/${NC}"
        return 1
    fi
    
    echo -e "${GREEN}Detected system: $live_dir/"
    echo -e "Kernel: $vmlinuz"
    echo -e "Initrd: $initrd${NC}"
    
    # Get ISO config
    read -p "Enter ISO name: " iso_name
    iso_name="${iso_name:-output}.iso"
    
    read -p "Enter volume label [${iso_name%.iso}]: " vol_label
    vol_label="${vol_label:-${iso_name%.iso}}"
    
    # Create GRUB config
    create_grub_config "$target_dir" "${iso_name%.iso}" "$vmlinuz" "$initrd" "$live_dir"
    
    # Build loop
    while true; do
        create_iso "$target_dir" "$(dirname "$target_dir")/$iso_name" "$vol_label"
        
        echo -e "\n${YELLOW}=== BUILD OPTIONS ===${NC}"
        echo "1) Rebuild ISO"
        echo "2) Edit files and rebuild"
        echo "3) Test ISO in QEMU (if installed)"
        echo "4) Finish"
        
        read -p "Select option: " choice
        case $choice in
            1) continue ;;
            2)
                echo -e "${YELLOW}Edit files in $target_dir then press ENTER to rebuild${NC}"
                read -r
                ;;
            3)
                if command -v qemu-system-x86_64 >/dev/null; then
                    echo -e "${BLUE}Testing ISO in QEMU...${NC}"
                    qemu-system-x86_64 -cdrom "$(dirname "$target_dir")/$iso_name" -m 2048
                else
                    echo -e "${RED}QEMU not installed. Install with:"
                    echo -e "  sudo apt install qemu-system-x86${NC}"
                fi
                ;;
            4) break ;;
            *) echo -e "${RED}Invalid option${NC}" ;;
        esac
    done
}

build_from_scratch() {
    local target_dir="$1"
    
    echo -e "\n${YELLOW}=== FRESH BUILD ===${NC}"
    if ! download_bootfiles "$target_dir"; then
        return 1
    fi
    
    echo -e "${YELLOW}Add your kernel/initrd to live/ or casper/ then press ENTER${NC}"
    read -r
    
    build_from_existing "$target_dir"
}

main() {
    install_dependencies
    
    while true; do
        echo -e "\n${YELLOW}=== ISO CREATOR ===${NC}"
        echo "1) Build from existing directory"
        echo "2) Fresh build (download bootfiles)"
        echo "3) Exit"
        
        read -p "Select option: " main_choice
        
        case $main_choice in
            1)
                read -p "Enter path to existing directory: " path
                path="${path/#\~/$HOME}"
                path=$(realpath "$path" 2>/dev/null)
                
                if [ -d "$path" ]; then
                    build_from_existing "$path"
                else
                    echo -e "${RED}Directory not found${NC}"
                fi
                ;;
            2)
                read -p "Enter target directory: " path
                path="${path/#\~/$HOME}"
                path=$(realpath "$path" 2>/dev/null)
                
                if [ ! -d "$path" ]; then
                    mkdir -p "$path" || {
                        echo -e "${RED}Failed to create directory${NC}"
                        continue
                    }
                fi
                
                build_from_scratch "$path"
                ;;
            3)
                echo -e "${GREEN}Exiting...${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option${NC}"
                ;;
        esac
    done
}

main "$@"
