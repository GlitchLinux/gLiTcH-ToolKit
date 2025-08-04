#!/bin/bash

# 🎨 GLITCH Supreme GRUB Theme Installer
# Downloads and installs complete GRUB environment from glitchlinux.wtf

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

# Define backup directory
SUPREME_DIR="/usr/local/supreme_grub"

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

# Create backup directories and files
create_backup_structure() {
    print_status "$GEAR" "Creating backup structure..."
    
    # Create supreme directory
    mkdir -p "$SUPREME_DIR"
    
    # Backup original 10_linux
    if [ -f "/etc/grub.d/10_linux" ]; then
        cp "/etc/grub.d/10_linux" "$SUPREME_DIR/10_linux.backup"
        print_success "Backed up 10_linux to $SUPREME_DIR"
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
    
    print_success "Created squashfs detection files"
}

# Download the package
download_package() {
    local url="https://github.com/GlitchLinux/Multibooters-agFM-rEFInd-GRUBFM/raw/refs/heads/main/GLITCH_Supreme_grub_theme.tar.gz"
    local destination="/tmp/GLITCH_Supreme_grub_theme.tar.gz"
    
    print_status "$DOWNLOAD" "Downloading GLITCH Supreme GRUB Theme..."
    echo -e "${BLUE}Source: ${WHITE}$url${NC}"
    echo -e "${BLUE}Destination: ${WHITE}$destination${NC}\n"
    
    if curl -L --progress-bar "$url" -o "$destination"; then
        print_success "Download completed successfully"
        
        # Verify file size
        local file_size=$(stat -f%z "$destination" 2>/dev/null || stat -c%s "$destination" 2>/dev/null || echo "0")
        if [ "$file_size" -gt 1000 ]; then
            print_success "Package size: $(echo "$file_size" | numfmt --to=iec-i --suffix=B --format="%.1f" 2>/dev/null || echo "$file_size bytes")"
        else
            print_error "Downloaded file seems too small, may be corrupted"
            exit 1
        fi
    else
        print_error "Download failed - Please check the URL and try again"
        exit 1
    fi
}

# Extract and verify package
extract_package() {
    local package="/tmp/GLITCH_Supreme_grub_theme.tar.gz"
    local extract_dir="/tmp/glitch-grub-install"
    
    print_status "$INSTALL" "Extracting GLITCH Supreme package..."
    
    # Clean up any existing extraction
    rm -rf "$extract_dir"
    mkdir -p "$extract_dir"
    
    if tar -xzf "$package" -C "$extract_dir"; then
        print_success "Package extracted successfully"
        
        # Verify installation script exists
        if [ -f "$extract_dir/install-complete-grub-system.sh" ]; then
            print_success "Installation script found"
            chmod +x "$extract_dir/install-complete-grub-system.sh"
        else
            print_error "Installation script not found in package"
            exit 1
        fi
    else
        print_error "Failed to extract package"
        exit 1
    fi
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

# Create enhanced 69_Custom_grub with squashfs detection (SIMPLE VERSION)
create_enhanced_69_grub() {
    print_status "$GEAR" "Creating enhanced squashfs detection script..."
    
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

# Check for squashfs existence and setup menus
if [ -e /boot/live/filesystem.squashfs ]; then
    echo "Found /boot/live/filesystem.squashfs - Setting up boot live environment"
    safe_copy /boot/vmlinuz* /boot/live/vmlinuz
    safe_copy /boot/initrd* /boot/live/initrd.img
    safe_copy /etc/grub.d/live-boot-2 /boot/grub/live-boot.cfg
    
    # Use squashs_exists menu
    if [ -f "$SUPREME_DIR/.squashs_exists.sh" ]; then
        cp "$SUPREME_DIR/.squashs_exists.sh" "/etc/grub.d/40_custom_bootmanagers"
    fi
    
elif [ -e /live/filesystem.squashfs ]; then
    echo "Found /live/filesystem.squashfs - Setting up live environment"
    safe_copy /vmlinuz* /live/vmlinuz
    safe_copy /initrd* /live/initrd.img
    safe_copy /etc/grub.d/live-boot-1 /boot/grub/live-boot.cfg
    
    # Use squashs_exists menu
    if [ -f "$SUPREME_DIR/.squashs_exists.sh" ]; then
        cp "$SUPREME_DIR/.squashs_exists.sh" "/etc/grub.d/40_custom_bootmanagers"
    fi
    
else
    echo "No filesystem.squashfs found - removing live boot config"
    
    # Remove live-boot.cfg if it exists
    rm -f "/boot/grub/live-boot.cfg" 2>/dev/null || true
    
    # Use no_squashs menu
    if [ -f "$SUPREME_DIR/.no_squashs.sh" ]; then
        cp "$SUPREME_DIR/.no_squashs.sh" "/etc/grub.d/40_custom_bootmanagers"
    fi
fi

# Create /boot/boot/ structure for separate boot partition compatibility
echo "Creating /boot/boot/ structure for partition compatibility"
rm -rf /boot/boot/ 2>/dev/null || true
mkdir -p /boot/boot/{grub,images}

# Copy essential grub files
safe_copy /boot/grub/custom.cfg /boot/boot/grub/
safe_copy /boot/grub/grub.cfg /boot/boot/grub/
safe_copy /boot/grub/live-boot.cfg /boot/boot/grub/
safe_copy /boot/grub/splash.png /boot/boot/grub/

# Copy boot images and other essential files
safe_copy_dir /boot/images /boot/boot/images
safe_copy_dir /boot/EFI /boot/boot/EFI
safe_copy_dir /boot/grubfm /boot/boot/grubfm

echo "GLITCH Supreme GRUB structure setup complete"
exit 0
EOF

    chmod +x "/etc/grub.d/69_Custom_grub"
    print_success "Enhanced 69_Custom_grub created - GRUB will execute it naturally"
}

# Run the installation
run_installation() {
    local extract_dir="/tmp/glitch-grub-install"
    local install_script="$extract_dir/install-complete-grub-system.sh"
    
    print_status "$INSTALL" "Running GLITCH Supreme GRUB installation..."
    
    # Change to extraction directory
    cd "$extract_dir"
    
    # Set the distro name and run installation
    echo "$DISTRO_NAME" | "$install_script"
    
    if [ $? -eq 0 ]; then
        print_success "GLITCH Supreme GRUB installed successfully!"
    else
        print_error "Installation failed"
        exit 1
    fi
}

# Create backup of installed configurations
create_config_backups() {
    print_status "$GEAR" "Creating configuration backups..."
    
    # Backup GRUB configurations (not bootloaders)
    if [ -f "/boot/grub/custom.cfg" ]; then
        cp "/boot/grub/custom.cfg" "$SUPREME_DIR/custom.cfg.backup"
    fi
    
    if [ -f "/boot/grub/live-boot.cfg" ]; then
        cp "/boot/grub/live-boot.cfg" "$SUPREME_DIR/live-boot.cfg.backup"
    fi
    
    if [ -f "/etc/grub.d/40_custom_bootmanagers" ]; then
        cp "/etc/grub.d/40_custom_bootmanagers" "$SUPREME_DIR/40_custom_bootmanagers.backup"
    fi
    
    if [ -f "/etc/grub.d/live-boot-1" ]; then
        cp "/etc/grub.d/live-boot-1" "$SUPREME_DIR/live-boot-1.backup"
    fi
    
    if [ -f "/etc/grub.d/live-boot-2" ]; then
        cp "/etc/grub.d/live-boot-2" "$SUPREME_DIR/live-boot-2.backup"
    fi
    
    print_success "Configuration files backed up to $SUPREME_DIR"
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

echo -e "${YELLOW}⚠️  This will remove all GLITCH Supreme GRUB components${NC}"
echo -e "${WHITE}Press Enter to continue, or Ctrl+C to cancel...${NC}"
read -r

echo -e "${BLUE}📋 Removing GLITCH Supreme components...${NC}"

# Remove theme
rm -rf "/boot/grub/themes/custom-theme" 2>/dev/null || true
echo -e "${GREEN}✅ Removed custom theme${NC}"

# Remove custom configurations
rm -f "/boot/grub/custom.cfg" 2>/dev/null || true
rm -f "/boot/grub/live-boot.cfg" 2>/dev/null || true
echo -e "${GREEN}✅ Removed custom configurations${NC}"

# Remove GRUB scripts
rm -f "/etc/grub.d/40_custom_bootmanagers" 2>/dev/null || true
rm -f "/etc/grub.d/69_Custom_grub" 2>/dev/null || true
rm -f "/etc/grub.d/live-boot-1" 2>/dev/null || true
rm -f "/etc/grub.d/live-boot-2" 2>/dev/null || true
echo -e "${GREEN}✅ Removed GRUB scripts${NC}"

# Restore original update-grub in uninstaller
if [ -f "/usr/sbin/update-grub.original" ]; then
    cp "/usr/sbin/update-grub.original" "/usr/sbin/update-grub"
    rm -f "/usr/sbin/update-grub.original"
    rm -f "/usr/local/bin/update-grub-supreme"
    echo -e "${GREEN}✅ Restored original update-grub${NC}"
fi

# Remove our hook scripts
rm -f "/etc/grub.d/05_supreme_hook" 2>/dev/null || true
echo -e "${GREEN}✅ Removed GRUB hooks${NC}"

# Restore original 10_linux
if [ -f "$SUPREME_DIR/10_linux.backup" ]; then
    cp "$SUPREME_DIR/10_linux.backup" "/etc/grub.d/10_linux"
    echo -e "${GREEN}✅ Restored original 10_linux${NC}"
fi

# Remove /boot/boot structure
rm -rf "/boot/boot" 2>/dev/null || true
echo -e "${GREEN}✅ Removed /boot/boot structure${NC}"

# Remove theme line from /etc/default/grub
if [ -f "/etc/default/grub" ]; then
    sed -i '/^GRUB_THEME=/d' "/etc/default/grub"
    echo -e "${GREEN}✅ Removed theme from GRUB configuration${NC}"
fi

# Update GRUB
echo -e "${BLUE}🔄 Updating GRUB...${NC}"
update-grub

# Remove aliases from bashrc
if [ -f "/etc/bash.bashrc" ]; then
    sed -i '/supreme-theme/d' "/etc/bash.bashrc"
    sed -i '/unsupreme-theme/d' "/etc/bash.bashrc"
    echo -e "${GREEN}✅ Removed aliases from bashrc${NC}"
fi

echo -e "\n${GREEN}🎉 GLITCH Supreme GRUB has been completely removed!${NC}"
echo -e "${BLUE}📝 Your system has been restored to its original GRUB configuration${NC}"
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
    print_success "Uninstall script created at $SUPREME_DIR/UN-supreme-your-theme.sh"
}

# Copy installer script for easy reinstall
copy_installer_script() {
    print_status "$GEAR" "Copying installer for easy reinstall..."
    
    # Copy this script to supreme directory
    cp "$0" "$SUPREME_DIR/supreme-your-theme.sh"
    chmod +x "$SUPREME_DIR/supreme-your-theme.sh"
    
    print_success "Installer copied to $SUPREME_DIR/supreme-your-theme.sh"
}

# Add bash aliases
add_bash_aliases() {
    print_status "$GEAR" "Adding bash aliases..."
    
    # Add aliases to bashrc
    if ! grep -q "supreme-theme" "/etc/bash.bashrc" 2>/dev/null; then
        echo "" >> "/etc/bash.bashrc"
        echo "# GLITCH Supreme GRUB aliases" >> "/etc/bash.bashrc"
        echo "alias supreme-theme='sudo bash /usr/local/supreme_grub/supreme-your-theme.sh'" >> "/etc/bash.bashrc"
        echo "alias unsupreme-theme='sudo bash /usr/local/supreme_grub/UN-supreme-your-theme.sh'" >> "/etc/bash.bashrc"
        print_success "Added aliases: supreme-theme and unsupreme-theme"
    else
        print_success "Aliases already exist in bashrc"
    fi
}

# Final steps and cleanup
finalize_installation() {
    print_status "$BOOT" "Finalizing installation..."
    
    # Ensure proper permissions
    find /boot -name "*.cfg" -exec chmod 644 {} \; 2>/dev/null || true
    find /boot -name "*.efi" -exec chmod 755 {} \; 2>/dev/null || true
    find /boot -name "*.elf" -exec chmod 755 {} \; 2>/dev/null || true
    
    # Execute our custom GRUB script
    if [ -x "/etc/grub.d/69_Custom_grub" ]; then
        print_status "$GEAR" "Executing GLITCH custom GRUB script..."
        /etc/grub.d/69_Custom_grub || print_warning "Custom script execution had warnings"
    fi
    
    # Final GRUB update
    print_status "$BOOT" "Updating GRUB configuration..."
    update-grub
    
    # Cleanup
    rm -rf "/tmp/glitch-grub-install"
    rm -f "/tmp/GLITCH_Supreme_grub_theme.tar.gz"
    
    print_success "Installation finalized and cleanup completed"
}

# Success message
print_success_message() {
    echo -e "\n${GREEN}${SPARKLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${SPARKLE}${NC}"
    echo -e "${WHITE}🎉 GLITCH SUPREME GRUB INSTALLATION COMPLETE! 🎉${NC}"
    echo -e "${GREEN}${SPARKLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${SPARKLE}${NC}\n"
    
    echo -e "${CYAN}${FIRE} What's installed:${NC}"
    echo -e "  ${CHECK} ${WHITE}Enhanced GRUB theme with larger fonts and better layout${NC}"
    echo -e "  ${CHECK} ${WHITE}Complete bootmanager environment (Netboot.xyz, rEFInd, GRUBFM)${NC}"
    echo -e "  ${CHECK} ${WHITE}Live boot support with '$DISTRO_NAME' branding${NC}"
    echo -e "  ${CHECK} ${WHITE}Complete EFI tools and drivers${NC}"
    echo -e "  ${CHECK} ${WHITE}Automatic squashfs detection and menu management${NC}"
    echo -e "  ${CHECK} ${WHITE}Power management options${NC}\n"
    
    echo -e "${CYAN}${ROCKET} Your new GRUB menu includes:${NC}"
    echo -e "  ${THEME} ${WHITE}Enhanced theme with 10+ visible menu items${NC}"
    echo -e "  ${GEAR} ${WHITE}'Bootloaders' → Access to Netboot.xyz, rEFInd, GRUBFM${NC}"
    echo -e "  ${BOOT} ${WHITE}'Live Boot' → $DISTRO_NAME live options (if detected)${NC}"
    echo -e "  ${FIRE} ${WHITE}'Power Off' and 'Reboot' options${NC}\n"
    
    echo -e "${CYAN}${GEAR} Management commands:${NC}"
    echo -e "  ${WHITE}supreme-theme${NC}     → Reinstall GLITCH Supreme GRUB"
    echo -e "  ${WHITE}unsupreme-theme${NC}   → Completely remove GLITCH Supreme GRUB"
    echo -e "  ${BLUE}(Available after next login or source /etc/bash.bashrc)${NC}\n"
    
    echo -e "${YELLOW}${ROCKET} Next steps:${NC}"
    echo -e "  ${WHITE}1.${NC} ${CYAN}Reboot your system to see the new GRUB theme${NC}"
    echo -e "  ${WHITE}2.${NC} ${CYAN}Explore the 'Bootloaders' menu for additional tools${NC}"
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
    create_backup_structure
    check_internet
    download_package
    extract_package
    get_distro_name
    create_enhanced_69_grub
    run_installation
    create_config_backups
    create_uninstall_script
    copy_installer_script
    add_bash_aliases
    finalize_installation
    
    print_success_message
}

# Handle interruption gracefully
trap 'echo -e "\n${RED}Installation cancelled by user${NC}"; exit 1' INT

# Run the installer
main "$@"
