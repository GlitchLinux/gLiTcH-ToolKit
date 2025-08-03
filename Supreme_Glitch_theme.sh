#!/bin/bash

# 🎨 GLITCH Supreme GRUB Theme Installer - Hybrid Edition
# Downloads bootmanagers directly + uses theme from glitchlinux.wtf

set -e

# Colors for beautiful output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
PURPLE='\033[0;35m'
CYAN='\033[0;36m'
WHITE='\033[1;37m'
NC='\033[0m' # No Color

# Unicode symbols for visual appeal
CHECK="✅"
CROSS="❌"
ROCKET="🚀"
DOWNLOAD="📥"
INSTALL="🔧"
THEME="🎨"
BOOT="💾"
SPARKLE="✨"
GEAR="⚙️"
FIRE="🔥"

# Define directories
SUPREME_DIR="/usr/local/supreme_grub"
TEMP_DIR="/tmp/glitch-supreme-install"
EFI_TARGET="/boot/EFI"
BIOS_TARGET="/boot/grubfm"
IMAGES_DIR="/boot/images"

# Bootmanager URLs
REFIND_URL="https://github.com/GlitchLinux/Multibooters-agFM-rEFInd-GRUBFM/raw/main/refind-cd-0.14.2.zip"
GRUBFM_UEFI_URL="https://github.com/GlitchLinux/Multibooters-agFM-rEFInd-GRUBFM/raw/main/grubfmx64.efi"
GRUBFM_BIOS_URL="https://github.com/GlitchLinux/Multibooters-agFM-rEFInd-GRUBFM/raw/main/grubfm_multiarch.iso"
NETBOOT_URL="https://boot.netboot.xyz/ipxe/netboot.xyz.iso"
MEMDISK_URL="https://boot.netboot.xyz/memdisk"

# Function to print colored headers
print_header() {
    echo -e "\n${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}$1${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Function to print status messages
print_status() {
    echo -e "${CYAN}$1${NC} $2"
}

# Function to print success messages
print_success() {
    echo -e "${GREEN}$CHECK $1${NC}"
}

# Function to print error messages
print_error() {
    echo -e "${RED}$CROSS $1${NC}"
}

# Function to print warning messages
print_warning() {
    echo -e "${YELLOW}⚠️  $1${NC}"
}

# ASCII Art Banner
print_banner() {
    echo -e "${WHITE}"
    cat << 'EOF'                    
 +-+-+-+-+-+-+-+-+-+-+-+-+
 |G|L|I|T|C|H|-|L|I|N|U|X|
 +-+-+-+-+-+-+-+-+-+-+-+-+  
   +-+-+-+-+-+-+-+-+-+-+  
   |G|R|U|B|-|T|H|E|M|E|  
   +-+-+-+-+-+-+-+-+-+-+                               
EOF
    echo -e "${NC}"
}

# Check if running as root
check_root() {
    if [ "$EUID" -ne 0 ]; then
        print_error "This script must be run as root (use sudo)"
        echo -e "${YELLOW}Please run: ${WHITE}sudo $0${NC}"
        exit 1
    fi
}

# Check internet connectivity
check_internet() {
    print_status "$DOWNLOAD" "Checking internet connectivity..."
    if ! curl -s --head https://glitchlinux.wtf >/dev/null 2>&1; then
        print_error "Cannot reach glitchlinux.wtf - Please check your internet connection"
        exit 1
    fi
    print_success "Internet connection verified"
}

# Install required tools
install_required_tools() {
    print_status "$GEAR" "Installing required tools..."
    
    # Check and install p7zip
    if ! command -v 7z &> /dev/null && ! command -v 7za &> /dev/null; then
        echo "Installing 7zip for extraction..."
        if command -v apt-get &> /dev/null; then
            apt-get update && apt-get install -y p7zip-full
        elif command -v dnf &> /dev/null; then
            dnf install -y p7zip
        elif command -v yum &> /dev/null; then
            yum install -y p7zip
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm p7zip
        else
            print_warning "Could not install 7zip automatically - please install manually"
        fi
    fi
    
    # Check and install xorriso for ISO extraction
    if ! command -v xorriso &> /dev/null; then
        echo "Installing xorriso for ISO extraction..."
        if command -v apt-get &> /dev/null; then
            apt-get install -y xorriso
        elif command -v dnf &> /dev/null; then
            dnf install -y xorriso
        elif command -v yum &> /dev/null; then
            yum install -y xorriso
        elif command -v pacman &> /dev/null; then
            pacman -Sy --noconfirm xorriso
        else
            print_warning "Could not install xorriso automatically - please install manually"
        fi
    fi
    
    print_success "Required tools ready"
}

# Create backup directories and files
create_backup_structure() {
    print_status "$GEAR" "Creating backup structure..."
    
    # Create supreme directory
    mkdir -p "$SUPREME_DIR"
    rm -rf "$TEMP_DIR"
    mkdir -p "$TEMP_DIR"
    
    # Backup original files
    if [ -f "/etc/grub.d/10_linux" ]; then
        cp "/etc/grub.d/10_linux" "$SUPREME_DIR/10_linux.backup"
        print_success "Backed up 10_linux"
    fi
    
    if [ -f "/etc/default/grub" ]; then
        cp "/etc/default/grub" "$SUPREME_DIR/grub.backup"
        print_success "Backed up GRUB config"
    fi
    
    # Create .no_squashs.sh
    cat > "$SUPREME_DIR/.no_squashs.sh" << 'EOF'
#!/bin/sh
exec tail -n +3 $0
# This file provides custom boot manager entries

menuentry "Bootloaders" {
    configfile /boot/grub/custom.cfg
}

menuentry "Power Off" {
    halt
}

menuentry "Reboot" {
    reboot
}
EOF
    chmod +x "$SUPREME_DIR/.no_squashs.sh"
    
    # Create .squashs_exists.sh
    cat > "$SUPREME_DIR/.squashs_exists.sh" << 'EOF'
#!/bin/sh
exec tail -n +3 $0
# This file provides custom boot manager entries

menuentry "Bootloaders" {
    configfile /boot/grub/custom.cfg
}

menuentry "Live Boot" {
    configfile /boot/grub/live-boot.cfg
}

menuentry "Power Off" {
    halt
}

menuentry "Reboot" {
    reboot
}
EOF
    chmod +x "$SUPREME_DIR/.squashs_exists.sh"
    
    print_success "Created backup structure and squashfs detection files"
}

# Download theme package from glitchlinux.wtf
download_theme_package() {
    local url="https://glitchlinux.wtf/FILES/GLITCH_Supreme_grub_theme.tar.gz"
    local destination="$TEMP_DIR/GLITCH_Supreme_grub_theme.tar.gz"
    
    print_status "$DOWNLOAD" "Downloading GLITCH Supreme theme package..."
    
    if curl -L --progress-bar "$url" -o "$destination"; then
        print_success "Theme package downloaded"
        
        # Extract theme package
        cd "$TEMP_DIR"
        if tar -xzf "GLITCH_Supreme_grub_theme.tar.gz"; then
            print_success "Theme package extracted"
        else
            print_error "Failed to extract theme package"
            exit 1
        fi
    else
        print_error "Failed to download theme package"
        exit 1
    fi
}

# Download bootmanagers directly
download_bootmanagers() {
    print_status "$DOWNLOAD" "Downloading bootmanagers..."
    
    cd "$TEMP_DIR"
    
    # Download rEFInd
    print_status "$DOWNLOAD" "Downloading rEFInd..."
    if wget -q --show-progress -O "refind-cd-0.14.2.zip" "$REFIND_URL"; then
        print_success "rEFInd downloaded"
    else
        print_error "Failed to download rEFInd"
        exit 1
    fi
    
    # Download GRUBFM UEFI
    print_status "$DOWNLOAD" "Downloading GRUBFM UEFI..."
    if wget -q --show-progress -O "grubfmx64.efi" "$GRUBFM_UEFI_URL"; then
        print_success "GRUBFM UEFI downloaded"
    else
        print_error "Failed to download GRUBFM UEFI"
        exit 1
    fi
    
    # Download GRUBFM BIOS
    print_status "$DOWNLOAD" "Downloading GRUBFM BIOS..."
    if wget -q --show-progress -O "grubfm_multiarch.iso" "$GRUBFM_BIOS_URL"; then
        print_success "GRUBFM BIOS downloaded"
    else
        print_error "Failed to download GRUBFM BIOS"
        exit 1
    fi
    
    # Download Netboot.xyz
    print_status "$DOWNLOAD" "Downloading Netboot.xyz..."
    if wget -q --show-progress -O "netboot.xyz.iso" "$NETBOOT_URL"; then
        print_success "Netboot.xyz downloaded"
    else
        print_error "Failed to download Netboot.xyz"
        exit 1
    fi
    
    # Download memdisk
    print_status "$DOWNLOAD" "Downloading memdisk..."
    if wget -q --show-progress -O "memdisk" "$MEMDISK_URL"; then
        print_success "Memdisk downloaded"
    else
        print_error "Failed to download memdisk"
        exit 1
    fi
}

# Install bootmanagers
install_bootmanagers() {
    print_status "$INSTALL" "Installing bootmanagers..."
    
    cd "$TEMP_DIR"
    
    # Clean previous installations
    rm -rf "$EFI_TARGET/refind" "$EFI_TARGET/grubfm" "$EFI_TARGET/Netboot" "$BIOS_TARGET" "$IMAGES_DIR"
    
    # Create directories
    mkdir -p "$EFI_TARGET"/{refind,grubfm,Netboot} "$BIOS_TARGET" "$IMAGES_DIR"
    
    # Install rEFInd
    print_status "$INSTALL" "Installing rEFInd..."
    if command -v 7z &> /dev/null; then
        7z x "refind-cd-0.14.2.zip" >/dev/null
    elif command -v 7za &> /dev/null; then
        7za x "refind-cd-0.14.2.zip" >/dev/null
    else
        unzip -q "refind-cd-0.14.2.zip"
    fi
    
    # Mount and extract rEFInd ISO
    mkdir -p "refind-mount"
    if mount -o loop "refind-cd-0.14.2.iso" "refind-mount" 2>/dev/null; then
        cp -r "refind-mount/EFI/boot/"* "$EFI_TARGET/refind/"
        umount "refind-mount"
        print_success "rEFInd installed"
    else
        print_warning "Could not mount rEFInd ISO, trying alternative extraction"
        if command -v xorriso &> /dev/null; then
            xorriso -osirrox on -indev "refind-cd-0.14.2.iso" -extract /EFI/boot/ "$EFI_TARGET/refind/" >/dev/null 2>&1
            print_success "rEFInd installed (alternative method)"
        else
            print_error "Failed to install rEFInd"
        fi
    fi
    
    # Install GRUBFM UEFI
    cp "grubfmx64.efi" "$EFI_TARGET/grubfm/"
    print_success "GRUBFM UEFI installed"
    
    # Install GRUBFM BIOS
    if command -v xorriso &> /dev/null; then
        mkdir -p "grubfm-bios"
        xorriso -osirrox on -indev "grubfm_multiarch.iso" -extract / "grubfm-bios" >/dev/null 2>&1
        if [ -f "grubfm-bios/grubfm.elf" ]; then
            cp "grubfm-bios/grubfm.elf" "$BIOS_TARGET/"
            print_success "GRUBFM BIOS installed"
        else
            print_warning "GRUBFM BIOS installation may have issues"
        fi
    else
        print_warning "Cannot extract GRUBFM BIOS - xorriso not available"
    fi
    
    # Install Netboot.xyz
    cp "netboot.xyz.iso" "$IMAGES_DIR/"
    cp "netboot.xyz.iso" "$EFI_TARGET/Netboot/BOOTX64.EFI" 2>/dev/null || true
    cp "memdisk" "$IMAGES_DIR/"
    print_success "Netboot.xyz installed"
}

# Create custom.cfg with correct paths
create_custom_cfg() {
    print_status "$GEAR" "Creating custom bootloader configuration..."
    
    cat > "/boot/grub/custom.cfg" << 'EOF'
menuentry "Netboot.xyz - BIOS" {
    insmod part_gpt
    insmod ext2
    linux16 /boot/images/memdisk iso
    initrd16 /boot/images/netboot.xyz.iso
}

menuentry "Netboot.xyz - UEFI" {
    insmod part_gpt
    insmod fat
    insmod chain
    search --file --no-floppy --set=root /boot/EFI/Netboot/BOOTX64.EFI
    chainloader /boot/EFI/Netboot/BOOTX64.EFI
}

menuentry "rEFInd - UEFI" --class refind {
    insmod part_gpt
    insmod fat
    insmod chain
    search --file --no-floppy --set=root /boot/EFI/refind/bootx64.efi
    chainloader /boot/EFI/refind/bootx64.efi
}

menuentry "GRUBFM - UEFI" --class grubfm {
    insmod part_gpt
    insmod fat
    insmod chain
    search --file --no-floppy --set=root /boot/EFI/grubfm/grubfmx64.efi
    chainloader /boot/EFI/grubfm/grubfmx64.efi
}

menuentry "GRUBFM (BIOS)" --class grubfm {
    insmod multiboot
    insmod ext2
    search --file --no-floppy --set=root /boot/grubfm/grubfm.elf
    multiboot /boot/grubfm/grubfm.elf
    boot
}

menuentry "Main Menu" {
    configfile /boot/grub/grub.cfg
}
EOF
    
    print_success "Custom bootloader configuration created"
}

# Install theme from package
install_theme() {
    print_status "$THEME" "Installing GLITCH Supreme theme..."
    
    # Create theme directory
    mkdir -p "/boot/grub/themes/custom-theme"
    
    # Install enhanced theme.cfg with improved layout
    cat > "/boot/grub/themes/custom-theme/theme.cfg" << 'EOF'
title-color: "white"
title-text: " "
title-font: "Sans Regular 18"
desktop-color: "black"
desktop-image: "/boot/grub/splash.png"
message-color: "white"
message-bg-color: "black"
terminal-font: "Sans Regular 14"
+ boot_menu {
  top = 120
  left = 10%
  width = 75%
  height = 250
  item_font = "Sans Regular 14"
  item_color = "grey"
  selected_item_color = "white"
  item_height = 24
  item_padding = 15
  item_spacing = 5
}
+ vbox {
  top = 100%
  left = 2%
  + label {text = "Press 'E' key to edit" font = "Sans 12" color = "white" align = "left"}
}
EOF
    
    # Install theme fonts if available from package
    if [ -d "$TEMP_DIR/theme/fonts" ]; then
        cp -r "$TEMP_DIR/theme/fonts" "/boot/grub/themes/custom-theme/"
        print_success "Theme fonts installed"
    fi
    
    # Create fallback splash if needed
    if [ ! -f "/boot/grub/splash.png" ]; then
        print_status "$GEAR" "Creating fallback splash image..."
        echo -n "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==" | base64 -d > "/boot/grub/splash.png"
    fi
    
    print_success "GLITCH Supreme theme installed"
}

# Get distro name from user
get_distro_name() {
    echo -e "\n${THEME} ${WHITE}DISTRIBUTION SETUP${NC}"
    echo -e "${CYAN}Please enter your distribution name for live boot entries:${NC}"
    echo -e "${YELLOW}Examples: 'GLITCH Linux', 'Ubuntu Custom', 'Debian Live'${NC}"
    echo -e "${BLUE}This will appear in your GRUB live boot menu${NC}\n"
    
    read -p "$(echo -e ${WHITE}Distribution name: ${NC})" DISTRO_NAME
    
    if [ -z "$DISTRO_NAME" ]; then
        DISTRO_NAME="GLITCH Linux"
        print_warning "Using default name: $DISTRO_NAME"
    else
        print_success "Using distribution name: $DISTRO_NAME"
    fi
}

# Install GRUB configuration files
install_grub_configs() {
    print_status "$GEAR" "Installing GRUB configuration files..."
    
    # Install live-boot templates with distro name
    sed "s/\$distro_name/$DISTRO_NAME/g" > "/etc/grub.d/live-boot-1" << 'EOF'
# This file gets copied to /boot/grub/live-boot.cfg if /live/filesystem.squashfs exists

menuentry "$distro_name - LIVE" {
    linux /live/vmlinuz boot=live config quiet
    initrd /live/initrd.img
}

menuentry "$distro_name - Boot ISO to RAM" {
    linux /live/vmlinuz boot=live config quiet toram
    initrd /live/initrd.img
}

menuentry "$distro_name - Encrypted Persistence" {
    linux /live/vmlinuz boot=live components quiet splash noeject findiso=${iso_path} persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/initrd.img
}

menuentry "Main Menu" {
    configfile /boot/grub/grub.cfg
}
EOF

    sed "s/\$distro_name/$DISTRO_NAME/g" > "/etc/grub.d/live-boot-2" << 'EOF'
# This file gets copied to /boot/grub/live-boot.cfg if /boot/live/filesystem.squashfs exists

menuentry "$distro_name - LIVE" {
    linux /boot/live/vmlinuz boot=live config quiet
    initrd /boot/live/initrd.img
}

menuentry "$distro_name - Boot ISO to RAM" {
    linux /boot/live/vmlinuz boot=live config quiet toram
    initrd /boot/live/initrd.img
}

menuentry "$distro_name - Encrypted Persistence" {
    linux /boot/live/vmlinuz boot=live components quiet splash noeject findiso=${iso_path} persistent=cryptsetup persistence-encryption=luks persistence
    initrd /boot/live/initrd.img
}

menuentry "Main Menu" {
    configfile /boot/grub/grub.cfg
}
EOF

    chmod 644 "/etc/grub.d/live-boot-1" "/etc/grub.d/live-boot-2"
    
    # Create enhanced 69_Custom_grub with FIXED logic
    cat > "/etc/grub.d/69_Custom_grub" << 'EOF'
#!/bin/bash

# Enhanced GLITCH Supreme GRUB - Squashfs detection and menu management
# Automatically detects live filesystems and manages boot menus

SUPREME_DIR="/usr/local/supreme_grub"

# Function to safely copy files
safe_copy() {
    if [ -f "$1" ]; then
        cp -f "$1" "$2" 2>/dev/null || true
    fi
}

# Function to safely copy directories  
safe_copy_dir() {
    if [ -d "$1" ]; then
        mkdir -p "$2"
        cp -rf "$1"/* "$2/" 2>/dev/null || true
    fi
}

# Function to find and copy kernel/initrd
find_and_copy_kernel() {
    local dest_dir="$1"
    local dest_kernel="$2"
    local dest_initrd="$3"
    
    # Try multiple kernel names
    for kernel in vmlinuz vmlinux kernel bzImage; do
        if [ -f "/boot/$kernel" ]; then
            cp "/boot/$kernel" "$dest_kernel"
            break
        elif [ -f "/boot/vmlinuz-$(uname -r)" ]; then
            cp "/boot/vmlinuz-$(uname -r)" "$dest_kernel"
            break
        fi
    done
    
    # Try multiple initrd names
    for initrd in initrd.img initrd initramfs.img initramfs; do
        if [ -f "/boot/$initrd" ]; then
            cp "/boot/$initrd" "$dest_initrd"
            break
        elif [ -f "/boot/initrd.img-$(uname -r)" ]; then
            cp "/boot/initrd.img-$(uname -r)" "$dest_initrd"
            break
        fi
    done
}

# Check for squashfs existence and setup menus
if [ -e /boot/live/filesystem.squashfs ]; then
    echo "Found /boot/live/filesystem.squashfs - Setting up boot live environment"
    find_and_copy_kernel "/boot/live" "/boot/live/vmlinuz" "/boot/live/initrd.img"
    safe_copy /etc/grub.d/live-boot-2 /boot/grub/live-boot.cfg
    
    # Use squashs_exists menu
    if [ -f "$SUPREME_DIR/.squashs_exists.sh" ]; then
        cp "$SUPREME_DIR/.squashs_exists.sh" "/etc/grub.d/40_custom_bootmanagers"
    fi
    
elif [ -e /live/filesystem.squashfs ]; then
    echo "Found /live/filesystem.squashfs - Setting up live environment"
    mkdir -p /live 2>/dev/null || true
    find_and_copy_kernel "/live" "/live/vmlinuz" "/live/initrd.img"
    safe_copy /etc/grub.d/live-boot-1 /boot/grub/live-boot.cfg
    
    # Use squashs_exists menu
    if [ -f "$SUPREME_DIR/.squashs_exists.sh" ]; then
        cp "$SUPREME_DIR/.squashs_exists.sh" "/etc/grub.d/40_custom_bootmanagers"
    fi
    
else
    echo "No filesystem.squashfs found - removing live boot config and using no-squash menu"
    
    # CRITICAL FIX: Remove live-boot.cfg if it exists
    rm -f /boot/grub/live-boot.cfg
    
    # Use no_squashs menu
    if [ -f "$SUPREME_DIR/.no_squashs.sh" ]; then
        cp "$SUPREME_DIR/.no_squashs.sh" "/etc/grub.d/40_custom_bootmanagers"
    fi
fi

# Create /boot/boot/ structure for separate boot partition compatibility
echo "Creating /boot/boot/ structure for partition compatibility"
rm -rf /boot/boot/ 2>/dev/null || true
mkdir -p /boot/boot/{grub,images,EFI,grubfm}

# Copy essential grub files
safe_copy /boot/grub/custom.cfg /boot/boot/grub/
safe_copy /boot/grub/grub.cfg /boot/boot/grub/
safe_copy /boot/grub/live-boot.cfg /boot/boot/grub/
safe_copy /boot/grub/splash.png /boot/boot/grub/

# Copy boot images and EFI tools
safe_copy_dir /boot/images /boot/boot/images
safe_copy_dir /boot/EFI /boot/boot/EFI
safe_copy_dir /boot/grubfm /boot/boot/grubfm

echo "GLITCH Supreme GRUB structure setup complete"
exit 0
EOF

    chmod +x "/etc/grub.d/69_Custom_grub"
    
    print_success "GRUB configuration files installed"
}

# Create uninstall script
create_uninstall_script() {
    print_status "$GEAR" "Creating uninstall script..."
    
    cat > "$SUPREME_DIR/UN-supreme-your-theme.sh" << 'EOF'
#!/bin/bash

# 🗑️ GLITCH Supreme GRUB Theme Uninstaller
# Removes all GLITCH Supreme GRUB components and restores original configuration

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
WHITE='\033[1;37m'
NC='\033[0m'

SUPREME_DIR="/usr/local/supreme_grub"

echo -e "${BLUE}🗑️  GLITCH Supreme GRUB Uninstaller${NC}\n"

# Check if running as root
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}❌ This script must be run as root (use sudo)${NC}"
    exit 1
fi

echo -e "${YELLOW}⚠️  This will remove all GLITCH Supreme GRUB components and bootmanagers${NC}"
echo -e "${WHITE}Press Enter to continue, or Ctrl+C to cancel...${NC}"
read -r

echo -e "${BLUE}📋 Removing GLITCH Supreme components...${NC}"

# Remove theme
rm -rf "/boot/grub/themes/custom-theme" 2>/dev/null || true
echo -e "${GREEN}✅ Removed custom theme${NC}"

# Remove bootmanagers
rm -rf "/boot/EFI/refind" "/boot/EFI/grubfm" "/boot/EFI/Netboot" 2>/dev/null || true
rm -rf "/boot/grubfm" "/boot/images" 2>/dev/null || true
echo -e "${GREEN}✅ Removed bootmanagers${NC}"

# Remove custom configurations
rm -f "/boot/grub/custom.cfg" "/boot/grub/live-boot.cfg" 2>/dev/null || true
echo -e "${GREEN}✅ Removed custom configurations${NC}"

# Remove GRUB scripts
rm -f "/etc/grub.d/40_custom_bootmanagers" 2>/dev/null || true
rm -f "/etc/grub.d/69_Custom_grub" 2>/dev/null || true
rm -f "/etc/grub.d/live-boot-1" "/etc/grub.d/live-boot-2" 2>/dev/null || true
echo -e "${GREEN}✅ Removed GRUB scripts${NC}"

# Restore original GRUB config
if [ -f "$SUPREME_DIR/grub.backup" ]; then
    cp "$SUPREME_DIR/grub.backup" "/etc/default/grub"
    echo -e "${GREEN}✅ Restored original GRUB configuration${NC}"
fi

# Remove /boot/boot structure
rm -rf "/boot/boot" 2>/dev/null || true
echo -e "${GREEN}✅ Removed /boot/boot structure${NC}"

# Remove aliases from bashrc
if [ -f "/etc/bash.bashrc" ]; then
    sed -i '/supreme-theme/d' "/etc/bash.bashrc"
    sed -i '/unsupreme-theme/d' "/etc/bash.bashrc"
    echo -e "${GREEN}✅ Removed aliases from bashrc${NC}"
fi

# Remove system scripts
rm -f "/usr/local/bin/supreme-theme" "/usr/local/bin/unsupreme-theme" 2>/dev/null || true
echo -e "${GREEN}✅ Removed system scripts${NC}"

# Update GRUB
echo -e "${BLUE}🔄 Updating GRUB...${NC}"
update-grub

echo -e "\n${GREEN}🎉 GLITCH Supreme GRUB has been completely removed!${NC}"
echo -e "${BLUE}📝 Your system has been restored to its original configuration${NC}"
echo -e "${YELLOW}🔄 Please reboot to see the changes${NC}\n"

# Ask if user wants to remove the supreme directory
echo -e "${WHITE}Do you want to remove the backup directory $SUPREME_DIR? (y/N)${NC}"
read -r remove_dir
if [[ $remove_dir =~ ^[Yy]$ ]]; then
    rm -rf "$SUPREME_DIR"
    echo -e "${GREEN}✅ Removed $SUPREME_DIR${NC}"
fi

echo -e "${BLUE}🎯 Uninstallation complete!${NC}"
EOF

    chmod +x "$SUPREME_DIR/UN-supreme-your-theme.sh"
    print_success "Uninstall script created"
}

# Install system scripts and aliases
install_system_integration() {
    print_status "$GEAR" "Installing system integration..."
    
    # Copy installer to supreme directory
    cp "$0" "$SUPREME_DIR/supreme-your-theme.sh"
    chmod +x "$SUPREME_DIR/supreme-your-theme.sh"
    
    # Copy installer to system PATH
    cp "$0" "/usr/local/bin/supreme-theme"
    chmod +x "/usr/local/bin/supreme-theme"
    
    # Create uninstall symlink
    ln -sf "$SUPREME_DIR/UN-supreme-your-theme.sh" "/usr/local/bin/unsupreme-theme"
    
    # Add bash aliases
    if ! grep -q "supreme-theme" "/etc/bash.bashrc" 2>/dev/null; then
        echo "" >> "/etc/bash.bashrc"
        echo "# GLITCH Supreme GRUB aliases" >> "/etc/bash.bashrc"
        echo "alias supreme-theme='sudo supreme-theme'" >> "/etc/bash.bashrc"
        echo "alias unsupreme-theme='sudo unsupreme-theme'" >> "/etc/bash.bashrc"
        print_success "Added system aliases and scripts"
    else
        print_success "System integration already configured"
    fi
}

# Configure GRUB theme
configure_grub_theme() {
    print_status "$GEAR" "Configuring GRUB theme..."
    
    # Update /etc/default/grub
    local grub_config="/etc/default/grub"
    
    # Remove existing GRUB_THEME line
    sed -i '/^GRUB_THEME=/d' "$grub_config"
    
    # Add theme configuration
    echo "" >> "$grub_config"
    echo "# GLITCH Supreme GRUB Theme Configuration" >> "$grub_config"
    echo "GRUB_THEME=\"/boot/grub/themes/custom-theme/theme.cfg\"" >> "$grub_config"
    
    print_success "GRUB theme configured"
}

# Final steps and cleanup
finalize_installation() {
    print_status "$BOOT" "Finalizing installation..."
    
    # Set proper permissions
    find /boot -name "*.cfg" -exec chmod 644 {} \; 2>/dev/null || true
    find /boot -name "*.efi" -exec chmod 755 {} \; 2>/dev/null || true
    find /boot -name "*.elf" -exec chmod 755 {} \; 2>/dev/null || true
    find /boot -name "*.iso" -exec chmod 644 {} \; 2>/dev/null || true
    find /boot -name "*.png" -exec chmod 644 {} \; 2>/dev/null || true
    
    # Execute our custom GRUB script to detect squashfs
    if [ -x "/etc/grub.d/69_Custom_grub" ]; then
        print_status "$GEAR" "Running initial squashfs detection..."
        /etc/grub.d/69_Custom_grub || print_warning "Squashfs detection had warnings"
    fi
    
    # Final GRUB update
    print_status "$BOOT" "Updating GRUB configuration..."
    update-grub
    
    # Cleanup temporary files
    rm -rf "$TEMP_DIR"
    
    print_success "Installation finalized and cleanup completed"
}

# Success message
print_success_message() {
    echo -e "\n${GREEN}${SPARKLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${SPARKLE}${NC}"
    echo -e "${WHITE}🎉 GLITCH SUPREME GRUB INSTALLATION COMPLETE! 🎉${NC}"
    echo -e "${GREEN}${SPARKLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${SPARKLE}${NC}\n"
    
    echo -e "${CYAN}${FIRE} What's installed:${NC}"
    echo -e "  ${CHECK} ${WHITE}Enhanced GRUB theme with larger fonts and better layout${NC}"
    echo -e "  ${CHECK} ${WHITE}rEFInd Boot Manager (UEFI) - Graphical boot interface${NC}"
    echo -e "  ${CHECK} ${WHITE}GRUBFM File Manager (UEFI & BIOS) - Browse and boot files${NC}"
    echo -e "  ${CHECK} ${WHITE}Netboot.xyz (UEFI & BIOS) - Network boot environment${NC}"
    echo -e "  ${CHECK} ${WHITE}Live boot support with '$DISTRO_NAME' branding${NC}"
    echo -e "  ${CHECK} ${WHITE}Automatic squashfs detection and menu management${NC}"
    echo -e "  ${CHECK} ${WHITE}Power management options${NC}\n"
    
    echo -e "${CYAN}${ROCKET} Your new GRUB menu includes:${NC}"
    echo -e "  ${THEME} ${WHITE}Enhanced theme with 10+ visible menu items${NC}"
    echo -e "  ${GEAR} ${WHITE}'Bootloaders' → Access to all boot tools${NC}"
    echo -e "  ${BOOT} ${WHITE}'Live Boot' → $DISTRO_NAME live options (if detected)${NC}"
    echo -e "  ${FIRE} ${WHITE}'Power Off' and 'Reboot' options${NC}\n"
    
    echo -e "${CYAN}${GEAR} System commands:${NC}"
    echo -e "  ${WHITE}supreme-theme${NC}       → Reinstall GLITCH Supreme GRUB"
    echo -e "  ${WHITE}unsupreme-theme${NC}     → Completely remove GLITCH Supreme GRUB"
    echo -e "  ${BLUE}(Available immediately from any terminal)${NC}\n"
    
    echo -e "${CYAN}🔧 Bootloaders installed:${NC}"
    echo -e "  ${WHITE}• rEFInd${NC}            → /boot/EFI/refind/"
    echo -e "  ${WHITE}• GRUBFM UEFI${NC}       → /boot/EFI/grubfm/"
    echo -e "  ${WHITE}• GRUBFM BIOS${NC}       → /boot/grubfm/"
    echo -e "  ${WHITE}• Netboot.xyz${NC}       → /boot/images/ & /boot/EFI/Netboot/"
    echo -e "  ${WHITE}• Memdisk${NC}           → /boot/images/\n"
    
    echo -e "${YELLOW}${ROCKET} Next steps:${NC}"
    echo -e "  ${WHITE}1.${NC} ${CYAN}Reboot your system to see the new GRUB theme${NC}"
    echo -e "  ${WHITE}2.${NC} ${CYAN}Select 'Bootloaders' to access all boot tools${NC}"
    echo -e "  ${WHITE}3.${NC} ${CYAN}Use 'Live Boot' if you have a live filesystem${NC}"
    echo -e "  ${WHITE}4.${NC} ${CYAN}Use 'unsupreme-theme' if you want to uninstall${NC}\n"
    
    echo -e "${GREEN}${SPARKLE} Enjoy your GLITCH Supreme GRUB experience! ${SPARKLE}${NC}\n"
    
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}Visit: ${BLUE}https://glitchlinux.wtf${WHITE} for more awesome tools!${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Main installation flow
main() {
    clear
    print_banner
    
    echo -e "${PURPLE}  ━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}  https://glitchlinux.wtf${NC}"
    echo -e "${PURPLE}  ━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "${WHITE} ${CHECK} ENTER will start Install${NC}"
    echo -e "${WHITE} ${CROSS} CTRL+C to cancel Install${NC}"
    echo ""
    read -r
    
    # Installation steps
    check_root
    check_internet
    install_required_tools
    create_backup_structure
    download_theme_package
    download_bootmanagers
    install_bootmanagers
    create_custom_cfg
    install_theme
    get_distro_name
    install_grub_configs
    create_uninstall_script
    install_system_integration
    configure_grub_theme
    finalize_installation
    
    print_success_message
}

# Handle interruption gracefully
trap 'echo -e "\n${RED}Installation cancelled by user${NC}"; exit 1' INT

# Run the installer
main "$@"
