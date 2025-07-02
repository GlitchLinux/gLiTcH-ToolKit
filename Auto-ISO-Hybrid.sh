#!/bin/bash
# Reliable ISO Creator - BIOS/UEFI Hybrid Bootloader

# Color setup
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Core installation function
install_core() {
    echo -e "${YELLOW}=== Installing Required Packages ===${NC}"
    sudo apt update && sudo apt install -y syslinux-utils grub-efi-amd64-bin mtools wget lzma xorriso
    
    echo -e "${BLUE}Downloading bootfiles...${NC}"
    sudo rm -rf /tmp/bootfiles
    sudo mkdir -p /tmp/bootfiles
    cd /tmp/bootfiles
    
    wget -q https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/HYBRID-BASE.tar.lzma
    unlzma HYBRID-BASE.tar.lzma
    tar -xf HYBRID-BASE.tar
    rm HYBRID-BASE.tar
    
    echo -e "${GREEN}✅ Core files downloaded${NC}"
}

# Setup UEFI bootloader
setup_uefi() {
    local sys_path="$1"
    echo -e "${YELLOW}=== Configuring UEFI Boot (GRUB2) ===${NC}"
    
    # Create EFI image
    dd if=/dev/zero of="$sys_path/boot/grub/efi.img" bs=1M count=10 &>/dev/null
    mkfs.vfat -n "GRUBEFI" "$sys_path/boot/grub/efi.img" &>/dev/null
    
    # Mount and copy EFI files
    sudo mmd -i "$sys_path/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
    sudo mcopy -i "$sys_path/boot/grub/efi.img" "$sys_path/EFI/BOOT/bootx64.efi" ::/EFI/BOOT/
    
    echo -e "${GREEN}✅ UEFI bootloader ready${NC}"
}

# Setup BIOS bootloader with instant chainload
setup_bios() {
    local sys_path="$1"
    echo -e "${YELLOW}=== Configuring BIOS Boot (ISOLINUX) ===${NC}"
    
    # Create instant chainload config
    cat > "$sys_path/isolinux/isolinux.cfg" <<EOF
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

    grub-mkimage -O i386-pc -c /tmp/embed.cfg -o "$sys_path/boot/grub/core.img" \
        -p /boot/grub biosdisk iso9660 configfile normal chain
    rm /tmp/embed.cfg
    
    echo -e "${GREEN}✅ BIOS bootloader ready (1s chainload to GRUB2)${NC}"
}

# Create GRUB configuration with theme support
create_grub_config() {
    local sys_path="$1"
    local sys_name="$2"
    
    cat > "$sys_path/boot/grub/grub.cfg" <<EOF
# GRUB2 Configuration - $sys_name

# Font and graphics setup
if loadfont \$prefix/fonts/font.pf2 ; then
  set gfxmode=800x600
  set gfxpayload=keep
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod gfxterm
  insmod png
  terminal_output gfxterm
fi

# Theme configuration
if background_image "/boot/grub/splash.png"; then
  set color_normal=light-gray/black
  set color_highlight=white/black
elif background_image "/splash.png"; then
  set color_normal=light-gray/black
  set color_highlight=white/black
else
  set menu_color_normal=cyan/blue
  set menu_color_highlight=white/blue
fi

# Basic settings
set default=0
set timeout=10

# Menu entries
menuentry "$sys_name - LIVE" {
    linux /live/vmlinuz boot=live config quiet splash
    initrd /live/initrd
}

menuentry "$sys_name - Boot to RAM" {
    linux /live/vmlinuz boot=live config quiet splash toram
    initrd /live/initrd
}

menuentry "$sys_name - Encrypted Persistence" {
    linux /live/vmlinuz boot=live components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/initrd
}

menuentry "Power Off" {
    halt
}

menuentry "Reboot" {
    reboot
}

# Custom config chainload
if [ -f /boot/grub/custom.cfg ]; then
    menuentry "Custom Options" {
        configfile /boot/grub/custom.cfg
    }
fi
EOF
    echo -e "${GREEN}✅ GRUB menu configured${NC}"
}

# Create ISO
create_iso() {
    local sys_path="$1"
    local sys_name="$2"
    
    echo -e "${YELLOW}=== Creating ISO ===${NC}"
    local vol_label=$(echo "$sys_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    local output_dir=$(dirname "$sys_path")
    local iso_name="${sys_name}.iso"
    
    echo -e "${BLUE}Output: ${GREEN}${output_dir}/${iso_name}${NC}"
    echo -e "${BLUE}Volume label: ${GREEN}${vol_label}${NC}"
    
    # Find MBR file
    local mbr_file="$sys_path/isolinux/isohdpfx.bin"
    [ ! -f "$mbr_file" ] && mbr_file="/usr/lib/ISOLINUX/isohdpfx.bin"
    [ ! -f "$mbr_file" ] && mbr_file="/usr/lib/syslinux/bios/isohdpfx.bin"
    
    # Create hybrid ISO
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$vol_label" \
        -full-iso9660-filenames \
        -R -J -joliet-long \
        -isohybrid-mbr "$mbr_file" \
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
        "$sys_path" 2>/dev/null
    
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
    install_core
    
    # Get build directory
    echo -e "\n${YELLOW}=== Build Configuration ===${NC}"
    read -p "Enter build directory: " build_dir
    build_dir="${build_dir/#\~/$HOME}"
    mkdir -p "$build_dir"
    build_dir=$(realpath "$build_dir")
    
    # Get system name
    read -p "Enter system name: " sys_name
    sys_name="${sys_name:-Custom-Linux}"
    
    # Copy files
    echo -e "\n${BLUE}Copying boot files...${NC}"
    cp -r /tmp/bootfiles/HYBRID-BASE/* "$build_dir/"
    chown -R $USER:$USER "$build_dir"
    
    # Setup bootloaders
    setup_uefi "$build_dir"
    setup_bios "$build_dir"
    create_grub_config "$build_dir" "$sys_name"
    
    # Customization phase
    echo -e "\n${YELLOW}=== Customization Phase ===${NC}"
    echo -e "System prepared at: ${GREEN}$build_dir${NC}"
    echo -e "Add your files to these locations:"
    echo -e "  • Live system:   ${BLUE}/live/${NC} (vmlinuz, initrd, filesystem.squashfs)"
    echo -e "  • Custom menu:   ${BLUE}/boot/grub/custom.cfg${NC}"
    echo -e "  • Splash screen: ${BLUE}/boot/grub/splash.png${NC} or ${BLUE}/splash.png${NC}"
    echo -e "\nPress ENTER when ready to create ISO"
    read -r
    
    # Create ISO
    create_iso "$build_dir" "$sys_name"
    
    # Rebuild option
    echo -e "\n${YELLOW}=== Rebuild Option ===${NC}"
    read -p "Create another ISO from same files? [y/N]: " rebuild
    if [[ "$rebuild" =~ ^[Yy] ]]; then
        create_iso "$build_dir" "$sys_name"
    fi
    
    # Cleanup
    rm -rf /tmp/bootfiles
    echo -e "\n${GREEN}=== Process Complete ===${NC}"
}

# Start main process
main