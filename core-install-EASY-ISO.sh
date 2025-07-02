#!/bin/bash
# Simple ISO Creator - BIOS/UEFI Hybrid Bootloader

# Color setup
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Core installation function
core_install() {
    echo -e "${YELLOW}=== Downloading Core Boot Files ===${NC}"
    sudo apt update && sudo apt install -y syslinux-utils grub-efi-amd64-bin mtools wget lzma xorriso
    
    echo -e "${BLUE}Downloading HYBRID-BASE...${NC}"
    sudo rm -rf /tmp/bootfiles
    sudo mkdir -p /tmp/bootfiles
    cd /tmp/bootfiles
    
    sudo wget -q https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/HYBRID-BASE.tar.lzma
    sudo unlzma HYBRID-BASE.tar.lzma
    sudo tar -xf HYBRID-BASE.tar
    sudo rm HYBRID-BASE.tar
    echo -e "${GREEN}✅ Core files downloaded${NC}"
}

# Setup UEFI bootloader
setup_uefi() {
    local system_path="$1"
    echo -e "${YELLOW}=== Configuring UEFI Boot (GRUB2) ===${NC}"
    
    # Create EFI image
    dd if=/dev/zero of="$system_path/boot/grub/efi.img" bs=1M count=10 &>/dev/null
    mkfs.vfat -n "GRUBEFI" "$system_path/boot/grub/efi.img" &>/dev/null
    
    # Mount and copy EFI files
    sudo mmd -i "$system_path/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
    sudo mcopy -i "$system_path/boot/grub/efi.img" "$system_path/EFI/BOOT/bootx64.efi" ::/EFI/BOOT/
    
    echo -e "${GREEN}✅ UEFI bootloader ready${NC}"
}

# Setup BIOS bootloader with instant chainload
setup_bios() {
    local system_path="$1"
    echo -e "${YELLOW}=== Configuring BIOS Boot (ISOLINUX) ===${NC}"
    
    # Create instant chainload config
    cat > "$system_path/isolinux/isolinux.cfg" <<EOF
default grub_chain
timeout 1
prompt 0
label grub_chain
  kernel /boot/grub/lnxboot.img
  initrd /boot/grub/core.img
EOF

    # Create GRUB core image
    cat > /tmp/embed.cfg <<'EOF'
search --file --set=root /boot/grub/grub.cfg
configfile /boot/grub/grub.cfg
EOF

    grub-mkimage -O i386-pc -c /tmp/embed.cfg -o "$system_path/boot/grub/core.img" \
        -p /boot/grub biosdisk iso9660 configfile normal chain
    rm /tmp/embed.cfg
    
    echo -e "${GREEN}✅ BIOS bootloader ready (1s chainload to GRUB2)${NC}"
}

# Create GRUB configuration
create_grub_cfg() {
    local system_path="$1"
    local system_name="$2"
    
    cat > "$system_path/boot/grub/grub.cfg" <<EOF
set timeout=10
set default=0

menuentry "$system_name - LIVE" {
    linux /live/vmlinuz boot=live config quiet splash
    initrd /live/initrd
}

menuentry "$system_name - Boot to RAM" {
    linux /live/vmlinuz boot=live config quiet splash toram
    initrd /live/initrd
}

menuentry "$system_name - Encrypted Persistence" {
    linux /live/vmlinuz boot=live components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/initrd
}

menuentry "Power Off" {
    halt
}

menuentry "Reboot" {
    reboot
}

if [ -f /boot/grub/custom.cfg ]; then
    menuentry "Custom Options" {
        configfile /boot/grub/custom.cfg
    }
fi
EOF
    echo -e "${GREEN}✅ GRUB menu configured${NC}"
}

# Create ISO function
create_iso() {
    local system_path="$1"
    local system_name="$2"
    
    echo -e "${YELLOW}=== ISO Creation ===${NC}"
    read -p "Enter volume label [${system_name}]: " vol_label
    vol_label="${vol_label:-$system_name}"
    vol_label=$(echo "$vol_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    
    local output_dir=$(dirname "$system_path")
    local iso_name="${system_name}.iso"
    
    echo -e "${BLUE}Creating: ${GREEN}${output_dir}/${iso_name}${NC}"
    echo -e "${BLUE}Volume label: ${GREEN}${vol_label}${NC}"
    
    # Hybrid ISO creation
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$vol_label" \
        -full-iso9660-filenames \
        -R -J -joliet-long \
        -isohybrid-mbr "$system_path/isolinux/isohdpfx.bin" \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -o "${output_dir}/${iso_name}" \
        "$system_path" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "${output_dir}/${iso_name}" | cut -f1)
        echo -e "${GREEN}🎉 ISO created successfully! (${size})${NC}"
        return 0
    else
        echo -e "${RED}❌ ISO creation failed${NC}"
        return 1
    fi
}

# Main workflow
main() {
    echo -e "${YELLOW}=== BIOS/UEFI Hybrid ISO Creator ===${NC}"
    
    # Run core installation
    core_install
    
    # Get user inputs
    echo -e "\n${YELLOW}=== System Configuration ===${NC}"
    read -p "Enter build directory: " build_dir
    build_dir="${build_dir/#\~/$HOME}"
    mkdir -p "$build_dir"
    
    read -p "Enter system name: " system_name
    system_name="${system_name:-Custom-Linux}"
    
    # Copy base files
    echo -e "\n${BLUE}Copying boot files...${NC}"
    sudo cp -r /tmp/bootfiles/HYBRID-BASE/* "$build_dir/"
    sudo chown -R $USER:$USER "$build_dir"
    
    # Setup bootloaders
    setup_uefi "$build_dir"
    setup_bios "$build_dir"
    create_grub_cfg "$build_dir" "$system_name"
    
    # User customization point
    echo -e "\n${YELLOW}=== Customization Phase ===${NC}"
    echo -e "System prepared at: ${GREEN}$build_dir${NC}"
    echo -e "Add your files to the directory structure:"
    echo -e "  - Live system:   ${BLUE}/live/${NC} (vmlinuz, initrd, filesystem.squashfs)"
    echo -e "  - Custom menu:   ${BLUE}/boot/grub/custom.cfg${NC} (optional)"
    echo -e "  - Boot themes:   ${BLUE}/boot/grub/splash.png${NC} or ${BLUE}/isolinux/splash.png${NC}"
    echo -e "\nPress ENTER when ready to create ISO"
    read -r
    
    # ISO creation loop
    while true; do
        create_iso "$build_dir" "$system_name"
        
        echo -e "\n${YELLOW}=== Rebuild Options ===${NC}"
        read -p "Create another ISO from same files? [y/N]: " rebuild
        if [[ ! "$rebuild" =~ ^[Yy] ]]; then
            break
        fi
    done
    
    # Cleanup
    sudo rm -rf /tmp/bootfiles
    echo -e "\n${GREEN}=== Process Complete ===${NC}"
}

# Start main process
main
