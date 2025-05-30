#!/bin/bash
# GRUBFM Hybrid ISO Creator - Complete Solution
# Handles clone, extraction, and ISO creation with full error checking

set -euo pipefail

# Configuration
REPO_URL="https://github.com/GlitchLinux/Multibooters-agFM-rEFInd-GRUBFM.git"
REPO_DIR="Multibooters-agFM-rEFInd-GRUBFM"
ARCHIVE="GRUB_FM_FILES.tar.lzma"
ISO_NAME="GRUBFM_Hybrid"
OUTPUT_DIR="GRUBFM_Output"
BUILD_DIR="/tmp/grubfm_build"

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
    
    local deps=("xorriso" "grub-mkimage" "git" "lzma")
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
            sudo apt-get install -y "${missing[@]}" grub-common grub-pc-bin grub-efi-amd64-bin xz-utils
        elif [ -f /etc/redhat-release ]; then
            echo -e "${GREEN}Attempting to install on RHEL-based system...${NC}"
            sudo yum install -y "${missing[@]}" grub2-efi-x64 grub2-pc xz
        elif [ -f /etc/arch-release ]; then
            echo -e "${GREEN}Attempting to install on Arch Linux...${NC}"
            sudo pacman -Sy --noconfirm "${missing[@]}" grub xz
        else
            echo -e "${RED}Unsupported distribution. Please install these packages manually:"
            echo -e "${missing[*]} grub-common grub-pc-bin grub-efi-amd64-bin xz-utils${NC}"
            exit 1
        fi
    fi
}

# Clone repository and extract archive
setup_files() {
    echo -e "${GREEN}Setting up repository...${NC}"
    
    if [ -d "$REPO_DIR" ]; then
        echo -e "${YELLOW}Repository exists, updating...${NC}"
        cd "$REPO_DIR"
        git pull
        cd ..
    else
        git clone --depth 1 "$REPO_URL" "$REPO_DIR"
    fi

    if [ ! -f "$REPO_DIR/$ARCHIVE" ]; then
        echo -e "${RED}Archive $ARCHIVE not found in repository!${NC}"
        exit 1
    fi

    echo -e "${GREEN}Extracting $ARCHIVE...${NC}"
    mkdir -p "$BUILD_DIR"
    tar --lzma -xvf "$REPO_DIR/$ARCHIVE" -C "$BUILD_DIR"
    
    # Verify essential files
    local essential_files=(
        "grubfmx64.efi"
        "efi.img"
        "grubfm.elf"
        "fmldr"
    )
    
    for file in "${essential_files[@]}"; do
        if [ ! -f "$BUILD_DIR/$file" ]; then
            echo -e "${RED}Missing essential file: $file${NC}"
            exit 1
        fi
    done
}

# Create BIOS boot components
create_bios_boot() {
    echo -e "${GREEN}Creating BIOS boot components...${NC}"
    
    mkdir -p "$BUILD_DIR/boot/grub"
    grub-mkimage -O i386-pc -o "$BUILD_DIR/core.img" \
        -p /boot/grub \
        biosdisk iso9660 configfile normal multiboot
    
    cat /usr/lib/grub/i386-pc/cdboot.img "$BUILD_DIR/core.img" > "$BUILD_DIR/boot/grub/bios.img"
}

# Create UEFI boot structure
create_uefi_boot() {
    echo -e "${GREEN}Setting up UEFI boot...${NC}"
    mkdir -p "$BUILD_DIR/efi/boot"
    cp "$BUILD_DIR/grubfmx64.efi" "$BUILD_DIR/efi/boot/bootx64.efi"
}

# Build the hybrid ISO
build_iso() {
    echo -e "${GREEN}Building hybrid ISO...${NC}"
    
    mkdir -p "$OUTPUT_DIR"
    
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$ISO_NAME" \
        -eltorito-boot boot/grub/bios.img \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        --eltorito-catalog boot/grub/boot.cat \
        --grub2-boot-info \
        --grub2-mbr /usr/lib/grub/i386-pc/boot_hybrid.img \
        -append_partition 2 0xef "$BUILD_DIR/efi.img" \
        -joliet -joliet-long \
        -o "$OUTPUT_DIR/$ISO_NAME.iso" \
        "$BUILD_DIR"
    
    echo -e "${GREEN}\nISO successfully created at: $OUTPUT_DIR/$ISO_NAME.iso${NC}"
    echo -e "${YELLOW}To burn to USB:"
    echo -e "dd if=$OUTPUT_DIR/$ISO_NAME.iso of=/dev/sdX bs=4M status=progress${NC}"
}

# Main execution
main() {
    install_deps
    setup_files
    create_bios_boot
    create_uefi_boot
    
    # Create minimal grub.cfg
    cat > "$BUILD_DIR/boot/grub/grub.cfg" << 'EOF'
set timeout=5
set default=0

menuentry "GRUB File Manager" {
    insmod all_video
    linux /boot/grub/grubfm.elf
}
EOF

    build_iso
}

main "$@"
