#!/bin/bash
# GRUBFM Hybrid ISO Creator - Complete Automated Version
# Handles cloning, dependencies, and ISO creation in one script

set -euo pipefail

# Configuration
REPO_URL="https://github.com/GlitchLinux/Multibooters-agFM-rEFInd-GRUBFM.git"
REPO_DIR="Multibooters-agFM-rEFInd-GRUBFM"
ISO_NAME="GRUBFM_Hybrid"
OUTPUT_DIR="GRUBFM_Output"
BUILD_DIR="build_iso"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Cleanup function
cleanup() {
    echo -e "${YELLOW}Cleaning up...${NC}"
    [ -d "$BUILD_DIR" ] && rm -rf "$BUILD_DIR"
    exit 0
}

# Error handler
error_handler() {
    echo -e "${RED}Error on line $1${NC}" >&2
    cleanup
    exit 1
}

trap 'error_handler $LINENO' ERR
trap cleanup EXIT

# Check and install dependencies
install_deps() {
    echo -e "${GREEN}Checking dependencies...${NC}"
    
    local deps=("xorriso" "grub-mkimage" "git" "mtools")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -gt 0 ]; then
        echo -e "${YELLOW}Missing dependencies: ${missing[*]}${NC}"
        
        if [ -f /etc/debian_version ]; then
            echo -e "${GREEN}Attempting to install on Debian-based system...${NC}"
            sudo apt-get update
            sudo apt-get install -y "${missing[@]}" grub-common grub-pc-bin grub-efi-amd64-bin
        elif [ -f /etc/redhat-release ]; then
            echo -e "${GREEN}Attempting to install on RHEL-based system...${NC}"
            sudo yum install -y "${missing[@]}" grub2-efi-x64 grub2-pc
        elif [ -f /etc/arch-release ]; then
            echo -e "${GREEN}Attempting to install on Arch Linux...${NC}"
            sudo pacman -Sy --noconfirm "${missing[@]}" grub
        else
            echo -e "${RED}Unsupported distribution. Please install these packages manually:"
            echo -e "${missing[*]} grub-common grub-pc-bin grub-efi-amd64-bin${NC}"
            exit 1
        fi
    fi
}

# Clone repository
clone_repo() {
    if [ -d "$REPO_DIR" ]; then
        echo -e "${YELLOW}Repository already exists. Updating...${NC}"
        cd "$REPO_DIR"
        git pull
        cd ..
    else
        echo -e "${GREEN}Cloning repository...${NC}"
        git clone --depth 1 "$REPO_URL" "$REPO_DIR"
    fi
}

# Prepare build directory
prepare_build() {
    echo -e "${GREEN}Preparing build directory...${NC}"
    rm -rf "$BUILD_DIR" "$OUTPUT_DIR"
    mkdir -p "$BUILD_DIR" "$OUTPUT_DIR"
    
    # Copy required files
    cp "$REPO_DIR"/{grubfm.elf,grubfmx64.efi,fmldr,efi.img,ventoy.dat} "$BUILD_DIR/" || {
        echo -e "${RED}Missing required files in repository${NC}"
        exit 1
    }
    
    # Use multiarch ISO as primary
    cp "$REPO_DIR"/grubfm_multiarch.iso "$BUILD_DIR/grubfm.iso"
}

# Create BIOS bootable components
create_bios_boot() {
    echo -e "${GREEN}Creating BIOS boot components...${NC}"
    
    # Create GRUB core image
    grub-mkimage -O i386-pc -o "$BUILD_DIR/core.img" \
        -p /boot/grub \
        biosdisk iso9660 configfile normal multiboot
    
    # Combine with boot image
    cat /usr/lib/grub/i386-pc/cdboot.img "$BUILD_DIR/core.img" > "$BUILD_DIR/bios.img"
}

# Create UEFI bootable components
create_uefi_boot() {
    echo -e "${GREEN}Creating UEFI boot components...${NC}"
    
    # Prepare EFI directory structure
    mkdir -p "$BUILD_DIR/efi/boot"
    cp "$BUILD_DIR/grubfmx64.efi" "$BUILD_DIR/efi/boot/bootx64.efi"
    
    # Process efi.img if exists
    if [ -f "$BUILD_DIR/efi.img" ]; then
        echo -e "${GREEN}Setting up EFI partition image...${NC}"
        mkdir -p efi_mount
        sudo mount -o loop "$BUILD_DIR/efi.img" efi_mount
        sudo cp "$BUILD_DIR/grubfmx64.efi" efi_mount/EFI/BOOT/bootx64.efi
        sudo umount efi_mount
        rm -rf efi_mount
    fi
}

# Create ISO structure
create_iso_structure() {
    echo -e "${GREEN}Creating ISO structure...${NC}"
    
    mkdir -p "$BUILD_DIR/boot/grub"
    cp "$BUILD_DIR/grubfm.elf" "$BUILD_DIR/boot/grub/"
    cp "$BUILD_DIR/fmldr" "$BUILD_DIR/boot/"
    
    # Create basic grub.cfg
    cat > "$BUILD_DIR/boot/grub/grub.cfg" << 'EOF'
set timeout=5
set default=0

menuentry "GRUB File Manager" {
    insmod all_video
    linux /boot/grub/grubfm.elf
}

menuentry "GRUB Console" {
    configfile /boot/grub/grub.cfg
}
EOF
}

# Build the hybrid ISO
build_iso() {
    echo -e "${GREEN}Building hybrid ISO...${NC}"
    
    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -volid "$ISO_NAME" \
        -eltorito-boot boot/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog boot/boot.cat \
        --grub2-boot-info \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -append_partition 2 0xef "$BUILD_DIR/efi.img" \
        -appended_part_as_gpt \
        -o "$OUTPUT_DIR/$ISO_NAME.iso" \
        "$BUILD_DIR"
    
    echo -e "${GREEN}\nISO successfully created at: $OUTPUT_DIR/$ISO_NAME.iso${NC}"
    echo -e "${YELLOW}You can burn this to USB with:"
    echo -e "dd if=$OUTPUT_DIR/$ISO_NAME.iso of=/dev/sdX bs=4M status=progress${NC}"
}

# Main execution
main() {
    echo -e "${GREEN}=== GRUBFM Hybrid ISO Creator ===${NC}"
    install_deps
    clone_repo
    prepare_build
    create_bios_boot
    create_uefi_boot
    create_iso_structure
    build_iso
}

main "$@"
