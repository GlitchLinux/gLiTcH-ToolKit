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

# Download the package
download_package() {
    local url="https://glitchlinux.wtf/FILES/GLITCH_Supreme_grub_theme.tar.gz"
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

echo "sudo rm -f /tmp/69_grub" >> /etc/grub.d/10_linux
echo 'echo "sleep 4 && sudo bash /etc/grub.d/69_Custom_grub" > /tmp/69_grub' >> /etc/grub.d/10_linux
echo "nohup bash /tmp/69_grub > /dev/null" >> /etc/grub.d/10_linux

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
    echo -e "  ${CHECK} ${WHITE}Automatic live system detection${NC}"
    echo -e "  ${CHECK} ${WHITE}Power management options${NC}\n"
    
    echo -e "${CYAN}${ROCKET} Your new GRUB menu includes:${NC}"
    echo -e "  ${THEME} ${WHITE}Enhanced theme with 10+ visible menu items${NC}"
    echo -e "  ${GEAR} ${WHITE}'Bootloaders' → Access to Netboot.xyz, rEFInd, GRUBFM${NC}"
    echo -e "  ${BOOT} ${WHITE}'Live Boot' → $DISTRO_NAME live options (if detected)${NC}"
    echo -e "  ${FIRE} ${WHITE}'Power Off' and 'Reboot' options${NC}\n"
    
    echo -e "${YELLOW}${ROCKET} Next steps:${NC}"
    echo -e "  ${WHITE}1.${NC} ${CYAN}Reboot your system to see the new GRUB theme${NC}"
    echo -e "  ${WHITE}2.${NC} ${CYAN}Explore the 'Bootloaders' menu for additional tools${NC}"
    echo -e "  ${WHITE}3.${NC} ${CYAN}Use 'Live Boot' if you have a live filesystem${NC}\n"
    
    echo -e "${GREEN}${SPARKLE} Enjoy your GLITCH Supreme GRUB experience! ${SPARKLE}${NC}\n"
    
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}Visit: ${BLUE}https://glitchlinux.wtf${WHITE} for more awesome tools!${NC}"
    echo -e "${PURPLE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
}

# Main installation flow
main() {
    clear
    print_banner
    
    #print_header "${ROCKET} GLITCH SUPREME GRUB INSTALLER ${ROCKET}"
    #echo -e "${CYAN}This installer will download and install the complete GLITCH Supreme GRUB environment${NC}"
    #echo -e "${CYAN}including enhanced theme, bootmanagers, and live boot support.${NC}\n"
    echo -e "${PURPLE}  ━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "${WHITE}${WHITE}  https://glitchlinux.wtf${WHITE}${NC}"
    echo -e "${PURPLE}  ━━━━━━━━━━━━━━━━━━━━━━━${NC}\n"
    echo -e "${WHITE} ${CHECK} ENTER will start Install ${NC}"
    echo -e "${WHITE} ${CROSS} CTRL+C to cancel Install ${NC}"
    echo ""
    read -r
    
    # Installation steps
    check_root
    check_internet
    download_package
    extract_package
    get_distro_name
    run_installation
    finalize_installation
    
    print_success_message
}

# Handle interruption gracefully
trap 'echo -e "\n${RED}Installation cancelled by user${NC}"; exit 1' INT

# Run the installer
main "$@"
