# Setup GRUB2 configuration with system name
setup_grub_config() {
    local system_path="$1"
    local system_name="$2"
    
    echo -e "${BLUE}Creating GRUB2 configuration for: $system_name${NC}"
    
    # Create grub.cfg with default entries and optional custom.cfg chainload
    cat > "$system_path/boot/grub/grub.cfg" <<EOF
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

set default=0
set timeout=10

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

# Optional custom configuration (only appears if custom.cfg exists)
if [ -s \$prefix/custom.cfg ]; then
    menuentry "Custom Menu" {
        configfile \$prefix/custom.cfg
    }
fi
EOF

    echo -e "${GREEN}✅ GRUB2 configuration created${NC}"
}

# Create ISO file
create_iso_file() {
    local system_path="$1"
    local system_name="$2"
    
    echo -e "\n${BLUE}=== ISO Creation ===${NC}"
    
    # Get output filename
    local parent_dir=$(dirname "$system_path")
    local default_name="${system_name}.iso"
    read -p "Enter ISO filename [$default_name]: " iso_filename
    iso_filename=${iso_filename:-$default_name}
    [[ "$iso_filename" != *.iso ]] && iso_filename="${iso_filename}.iso"
    
    local output_file="$parent_dir/$iso_filename"
    
    # Get volume label
    local volume_default=$(echo "$system_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    read -p "Enter ISO volume label [$volume_default]: " volume_label
    volume_label=${volume_label:-$volume_default}
    volume_label=$(echo "$volume_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    
    echo -e "${BLUE}Creating ISO: $output_file${NC}"
    echo -e "${BLUE}Volume label: $volume_label${NC}"
    
    # Check for MBR file
    local mbr_file="$system_path/isolinux/isohdpfx.bin"
    if [ ! -f "$mbr_file" ]; then
        mbr_file="/usr/lib/ISOLINUX/isohdpfx.bin"
    fi
    if [ ! -f "$mbr_file" ]; then
        mbr_file="/usr/lib/syslinux/bios/isohdpfx.bin"
    fi
    
    # Create hybrid ISO
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$volume_label" \
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
        -append_partition 2 0xEF "$system_path/boot/grub/efi.img" \
        -o "$output_file" \
        "$system_path" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local file_size=$(du -h "$output_file" | cut -f1)
        echo -e "\n${GREEN}🎉 ISO created successfully!${NC}"
        echo -e "${GREEN}📁 Location: $output_file${NC}"
        echo -e "${GREEN}📏 Size: $file_size${NC}"
        echo -e "\n${BLUE}Your hybrid ISO supports:${NC}"
        echo -e "  ✅ BIOS Legacy boot (ISOLINUX → GRUB2)"
        echo -e "  ✅ UEFI boot (Direct GRUB2)"
        echo -e "  ✅ USB/HDD boot (Hybrid mode)"
    else
        echo -e "\n${RED}❌ ISO creation failed${NC}"
        return 1
    fi
}

# Main function
main() {
    echo -e "${YELLOW}=== Simple ISO Creator - Core Bootloader Setup ===${NC}"
    echo -e "${BLUE}Sets up BIOS (ISOLINUX) + UEFI (GRUB2) with instant chainload${NC}\n"
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please run as regular user (script will use sudo when needed)${NC}"
        exit 1
    fi
    
    # Execute core installation
    execute_core_install
    
    # Get system path from user
    echo -e "\n${YELLOW}=== System Path Configuration ===${NC}"
    read -p "Enter the system path where ISO will be built: " system_path
    
    # Validate and create system path
    if [ -z "$system_path" ]; then
        echo -e "${RED}Error: Empty system path${NC}"
        exit 1
    fi
    
    # Expand tilde and resolve path
    system_path="${system_path/#\~/$HOME}"
    system_path=$(realpath "$system_path" 2>/dev/null || echo "$system_path")
    
    # Create directory if it doesn't exist
    if [ ! -d "$system_path" ]; then
        echo -e "${BLUE}Creating directory: $system_path${NC}"
        mkdir -p "$system_path"
    fi
    
    echo -e "${GREEN}Working with: $system_path${NC}"
    
    # Get system name from user
    echo -e "\n${YELLOW}=== System Name Configuration ===${NC}"
    read -p "Enter the system name (e.g., My-Linux-Distro): " system_name
    
    if [ -z "$system_name" ]; then
        system_name="Custom-Linux"
        echo -e "${YELLOW}Using default name: $system_name${NC}"
    fi
    
    echo -e "${GREEN}System name: $system_name${NC}"
    
    # Copy base files
    copy_base_files "$system_path"
    
    # Setup bootloaders
    setup_grub_uefi "$system_path"
    setup_isolinux_bios "$system_path"
    setup_grub_config "$system_path" "$system_name"
    
    echo -e "\n${GREEN}=== Setup Complete ===${NC}"
    echo -e "${GREEN}✅ UEFI (GRUB2) bootloader ready${NC}"
    echo -e "${GREEN}✅ BIOS (ISOLINUX) bootloader ready${NC}"
    echo -e "${GREEN}✅ Instant chainload configured${NC}"
    echo -e "${GREEN}✅ GRUB2 menu configured for: $system_name${NC}"
    echo -e "${BLUE}System ready at: $system_path${NC}"
    
    echo -e "\n${YELLOW}Boot sequence:${NC}"
    echo -e "  ${BLUE}UEFI:${NC} Direct GRUB2 boot"
    echo -e "  ${BLUE}BIOS:${NC} ISOLINUX (1 sec) → GRUB2 chainload"
    
    echo -e "\n${YELLOW}=== Customization Options ===${NC}"
    echo -e "${BLUE}You can now customize your ISO by adding:${NC}"
    echo -e "  • ${GREEN}Live system files${NC} in $system_path/live/ (vmlinuz, initrd, filesystem.squashfs)"
    echo -e "  • ${GREEN}Custom splash.png${NC} in $system_path/boot/grub/ or $system_path/"
    echo -e "  • ${GREEN}Custom GRUB menu${NC} in $system_path/boot/grub/custom.cfg"
    echo -e "  • ${GREEN}Additional tools${NC} in EFI/, isolinux/, or root directories"
    echo -e "  • ${GREEN}Any other files${NC} you want in the ISO"
    
    echo -e "\n${YELLOW}Optional: Add custom.cfg${NC}"
    echo -e "  ${BLUE}Place custom.cfg in $system_path/boot/grub/ for additional menu options${NC}"
    
    echo -e "\n${YELLOW}=== Ready for ISO Creation ===${NC}"
    echo -e "${BLUE}System prepared at: $system_path${NC}"
    read -p "Configure any custom settings now, then press ENTER to start ISO creation (or Ctrl+C to exit): " -r
    
    # Continue with ISO creation
    create_iso_file "$system_path" "$system_name"
    
    # Final cleanup
    sudo rm -rf /tmp/bootfiles /tmp/core-install.sh
    
    echo -e "\n${GREEN}All done! 🎉${NC}"
}

# Run main function
main "$@"# Setup GRUB2 configuration with system name
setup_grub_#!/bin/bash

# Simple ISO Creator - Core Bootloader Setup
# BIOS (ISOLINUX) + UEFI (GRUB2) with instant chainload

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Execute core installation
execute_core_install() {
    echo -e "${BLUE}=== Core Installation ===${NC}"
    
    # Create and execute core-install.sh
    cat > /tmp/core-install.sh <<'EOF'
#!/bin/bash
# LINUX LIVE - BIOS & UEFI 
# Isolinux & grub2 Chainload

sudo apt update && sudo apt install -y syslinux-utils grub-efi-amd64-bin mtools wget lzma xorriso

sudo rm -rf /tmp/bootfiles && sudo mkdir /tmp/bootfiles && cd /tmp/bootfiles
sudo wget https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/HYBRID-BASE.tar.lzma
sudo unlzma HYBRID-BASE.tar.lzma && sudo tar -xvf HYBRID-BASE.tar
sudo rm HYBRID-BASE.tar && cd HYBRID-BASE
EOF
    
    chmod +x /tmp/core-install.sh
    echo -e "${BLUE}Executing core installation...${NC}"
    /tmp/core-install.sh
    
    if [ ! -d "/tmp/bootfiles/HYBRID-BASE" ]; then
        echo -e "${RED}Error: Core installation failed${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ Core installation complete${NC}"
}

# Copy base files to system path
copy_base_files() {
    local system_path="$1"
    
    echo -e "${BLUE}Copying base files to: $system_path${NC}"
    
    # Copy all HYBRID-BASE contents to system path
    sudo cp -r /tmp/bootfiles/HYBRID-BASE/* "$system_path/"
    
    # Set proper permissions
    sudo chown -R $USER:$USER "$system_path"
    
    echo -e "${GREEN}✅ Base files copied${NC}"
}

# Setup GRUB2 for UEFI (GPT mode)
setup_grub_uefi() {
    local system_path="$1"
    
    echo -e "${BLUE}Setting up GRUB2 for UEFI (GPT mode)...${NC}"
    
    # Create UEFI bootloader
    mkdir -p "$system_path/EFI/BOOT"
    
    if [ -d "$system_path/boot/grub/x86_64-efi" ]; then
        grub-mkimage -O x86_64-efi \
            -o "$system_path/EFI/BOOT/bootx64.efi" \
            -p /boot/grub \
            -d "$system_path/boot/grub/x86_64-efi" \
            boot linux ext2 fat iso9660 part_gpt part_msdos normal configfile \
            loopback chain efifwsetup efi_gop efi_uga ls search search_label \
            search_fs_uuid search_fs_file gfxterm gfxmenu font echo video all_video
    else
        echo -e "${YELLOW}Warning: GRUB x86_64-efi modules not found, using existing bootx64.efi${NC}"
    fi
    
    # Create EFI boot image
    mkdir -p "$system_path/boot/grub"
    dd if=/dev/zero of="$system_path/boot/grub/efi.img" bs=1M count=10 2>/dev/null
    mkfs.vfat -F 12 "$system_path/boot/grub/efi.img" > /dev/null 2>&1
    
    # Mount and copy EFI files
    mmd -i "$system_path/boot/grub/efi.img" ::/EFI ::/EFI/BOOT
    mcopy -i "$system_path/boot/grub/efi.img" "$system_path/EFI/BOOT/bootx64.efi" ::/EFI/BOOT/
    
    echo -e "${GREEN}✅ GRUB2 UEFI setup complete${NC}"
}

# Setup ISOLINUX for BIOS with instant GRUB2 chainload
setup_isolinux_bios() {
    local system_path="$1"
    
    echo -e "${BLUE}Setting up ISOLINUX for BIOS (MBR mode) with instant GRUB2 chainload...${NC}"
    
    # Create instant chainload isolinux.cfg
    cat > "$system_path/isolinux/isolinux.cfg" <<'EOF'
# ISOLINUX Configuration - Instant GRUB2 Chainload
default grub2_chainload
timeout 1
prompt 0

label grub2_chainload
  linux /boot/grub/lnxboot.img
  initrd /boot/grub/core.img
EOF
    
    # Create GRUB2 core image for chainloading
    if [ -d "$system_path/boot/grub/i386-pc" ]; then
        echo -e "${BLUE}Creating GRUB2 core image for BIOS chainloading...${NC}"
        
        # Create embedded config
        cat > /tmp/grub_embed.cfg <<'EOF'
search --no-floppy --set=root --file /boot/grub/grub.cfg
set prefix=($root)/boot/grub
configfile /boot/grub/grub.cfg
EOF
        
        # Create core.img
        grub-mkimage -O i386-pc \
            -o "$system_path/boot/grub/core.img" \
            -p /boot/grub \
            -c /tmp/grub_embed.cfg \
            -d "$system_path/boot/grub/i386-pc" \
            biosdisk iso9660 part_msdos fat ext2 normal boot linux configfile \
            loopback chain search search_label search_fs_file search_fs_uuid \
            ls echo cat help reboot halt gfxterm gfxmenu png font video all_video
        
        rm -f /tmp/grub_embed.cfg
        echo -e "${GREEN}✅ GRUB2 core image created${NC}"
    else
        echo -e "${YELLOW}Warning: GRUB i386-pc modules not found, using existing core.img${NC}"
    fi
    
    echo -e "${GREEN}✅ ISOLINUX BIOS setup complete with instant GRUB2 chainload${NC}"
}

# Main function
main() {
    echo -e "${YELLOW}=== Simple ISO Creator - Core Bootloader Setup ===${NC}"
    echo -e "${BLUE}Sets up BIOS (ISOLINUX) + UEFI (GRUB2) with instant chainload${NC}\n"
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        echo -e "${RED}Please run as regular user (script will use sudo when needed)${NC}"
        exit 1
    fi
    
    # Execute core installation
    execute_core_install
    
    # Get system path from user
    echo -e "\n${YELLOW}=== System Path Configuration ===${NC}"
    read -p "Enter the system path where ISO will be built: " system_path
    
    # Validate and create system path
    if [ -z "$system_path" ]; then
        echo -e "${RED}Error: Empty system path${NC}"
        exit 1
    fi
    
    # Expand tilde and resolve path
    system_path="${system_path/#\~/$HOME}"
    system_path=$(realpath "$system_path" 2>/dev/null || echo "$system_path")
    
    # Create directory if it doesn't exist
    if [ ! -d "$system_path" ]; then
        echo -e "${BLUE}Creating directory: $system_path${NC}"
        mkdir -p "$system_path"
    fi
    
    echo -e "${GREEN}Working with: $system_path${NC}"
    
    # Get system name from user
    echo -e "\n${YELLOW}=== System Name Configuration ===${NC}"
    read -p "Enter the system name (e.g., My-Linux-Distro): " system_name
    
    if [ -z "$system_name" ]; then
        system_name="Custom-Linux"
        echo -e "${YELLOW}Using default name: $system_name${NC}"
    fi
    
    echo -e "${GREEN}System name: $system_name${NC}"
    
    # Copy base files
    copy_base_files "$system_path"
    
    # Setup bootloaders
    setup_grub_uefi "$system_path"
    setup_isolinux_bios "$system_path"
    setup_grub_config "$system_path" "$system_name"
    
    echo -e "\n${GREEN}=== Setup Complete ===${NC}"
    echo -e "${GREEN}✅ UEFI (GRUB2) bootloader ready${NC}"
    echo -e "${GREEN}✅ BIOS (ISOLINUX) bootloader ready${NC}"
    echo -e "${GREEN}✅ Instant chainload configured${NC}"
    echo -e "${GREEN}✅ GRUB2 menu configured for: $system_name${NC}"
    echo -e "${BLUE}System ready at: $system_path${NC}"
    
    echo -e "\n${YELLOW}Boot sequence:${NC}"
    echo -e "  ${BLUE}UEFI:${NC} Direct GRUB2 boot"
    echo -e "  ${BLUE}BIOS:${NC} ISOLINUX (1 sec) → GRUB2 chainload"
    
    # Cleanup
    sudo rm -rf /tmp/bootfiles /tmp/core-install.sh
    
    echo -e "\n${GREEN}Ready for next steps (live system setup, ISO creation, etc.)${NC}"
}

# Run main function
main "$@"