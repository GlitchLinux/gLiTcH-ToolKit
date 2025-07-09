#!/bin/bash

# DWM Installation Script with LightDM for Debian/Ubuntu
# This script downloads, compiles, and installs DWM with LightDM configuration

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Configuration
DWM_VERSION="6.5"
DWM_URL="https://dl.suckless.org/dwm/dwm-${DWM_VERSION}.tar.gz"
BUILD_DIR="/tmp/dwm-build"
INSTALL_PREFIX="/usr/local"

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Function to check if running as root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        print_error "This script should not be run as root. Please run as a regular user."
        print_status "The script will use sudo when needed."
        exit 1
    fi
}

# Function to check if running on Debian/Ubuntu
check_distro() {
    if ! command -v apt &> /dev/null; then
        print_error "This script is designed for Debian/Ubuntu systems with apt package manager."
        exit 1
    fi
}

# Function to update package lists
update_packages() {
    print_status "Updating package lists..."
    sudo apt update
    print_success "Package lists updated"
}

# Function to install dependencies
install_dependencies() {
    print_status "Installing build dependencies and LightDM..."
    
    local packages=(
        "build-essential"
        "libx11-dev"
        "libxft-dev"
        "libxinerama-dev"
        "libxrandr-dev"
        "libxss-dev"
        "pkg-config"
        "make"
        "gcc"
        "libc6-dev"
        "lightdm"
        "lightdm-gtk-greeter"
        "xorg"
        "xinit"
        "wget"
        "tar"
    )
    
    for package in "${packages[@]}"; do
        print_status "Installing $package..."
        sudo apt install -y "$package"
    done
    
    print_success "All dependencies installed"
}

# Function to create build directory
create_build_dir() {
    print_status "Creating build directory..."
    rm -rf "$BUILD_DIR"
    mkdir -p "$BUILD_DIR"
    cd "$BUILD_DIR"
    print_success "Build directory created: $BUILD_DIR"
}

# Function to download DWM source
download_dwm() {
    print_status "Downloading DWM ${DWM_VERSION}..."
    wget -O "dwm-${DWM_VERSION}.tar.gz" "$DWM_URL"
    
    print_status "Extracting DWM source..."
    tar -xzf "dwm-${DWM_VERSION}.tar.gz"
    cd "dwm-${DWM_VERSION}"
    
    print_success "DWM source downloaded and extracted"
}

# Function to configure DWM build
configure_dwm() {
    print_status "Configuring DWM build..."
    
    # Backup original config.mk
    cp config.mk config.mk.backup
    
    # Update config.mk to use proper install prefix
    sed -i "s|PREFIX = /usr/local|PREFIX = $INSTALL_PREFIX|g" config.mk
    
    # Show current configuration
    print_status "Current DWM configuration:"
    echo "PREFIX: $(grep '^PREFIX' config.mk)"
    echo "MANPREFIX: $(grep '^MANPREFIX' config.mk)"
    
    print_success "DWM configuration updated"
}

# Function to compile DWM
compile_dwm() {
    print_status "Compiling DWM..."
    make clean
    make
    print_success "DWM compiled successfully"
}

# Function to install DWM
install_dwm() {
    print_status "Installing DWM..."
    sudo make install
    print_success "DWM installed to $INSTALL_PREFIX"
}

# Function to create DWM desktop entry
create_desktop_entry() {
    print_status "Creating DWM desktop entry..."
    
    sudo tee /usr/share/xsessions/dwm.desktop > /dev/null <<EOF
[Desktop Entry]
Name=DWM
Comment=Dynamic Window Manager
Exec=$INSTALL_PREFIX/bin/dwm
Type=XSession
DesktopNames=DWM
EOF
    
    print_success "DWM desktop entry created"
}

# Function to configure LightDM
configure_lightdm() {
    print_status "Configuring LightDM..."
    
    # Backup original LightDM configuration
    if [[ -f /etc/lightdm/lightdm.conf ]]; then
        sudo cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
    fi
    
    # Create or update LightDM configuration
    sudo tee /etc/lightdm/lightdm.conf > /dev/null <<EOF
[Seat:*]
autologin-guest=false
autologin-user=
autologin-user-timeout=0
autologin-session=
greeter-session=lightdm-gtk-greeter
user-session=dwm
EOF
    
    print_success "LightDM configured"
}

# Function to create user .xinitrc
create_xinitrc() {
    print_status "Creating .xinitrc for user..."
    
    local xinitrc_content="#!/bin/bash

# Load X resources
if [ -f ~/.Xresources ]; then
    xrdb -merge ~/.Xresources
fi

# Set up display
xrandr --auto

# Start some useful background processes
# Uncomment and modify as needed:
# xsetroot -solid '#222222'  # Set background color
# exec dwm

# Status bar loop (optional)
while xsetroot -name \"\$(date '+%Y-%m-%d %H:%M:%S') \$(uptime | sed 's/.*,//')\"
do
    sleep 1
done &

# Start DWM
exec $INSTALL_PREFIX/bin/dwm"

    echo "$xinitrc_content" > ~/.xinitrc
    chmod +x ~/.xinitrc
    
    print_success ".xinitrc created in home directory"
}

# Function to create basic .Xresources
create_xresources() {
    print_status "Creating basic .Xresources..."
    
    cat > ~/.Xresources <<EOF
! DWM X Resources Configuration
! Terminal colors and fonts

*foreground: #ffffff
*background: #000000
*cursorColor: #ffffff

! Black
*color0: #000000
*color8: #555555

! Red
*color1: #ff0000
*color9: #ff5555

! Green
*color2: #00ff00
*color10: #55ff55

! Yellow
*color3: #ffff00
*color11: #ffff55

! Blue
*color4: #0000ff
*color12: #5555ff

! Magenta
*color5: #ff00ff
*color13: #ff55ff

! Cyan
*color6: #00ffff
*color14: #55ffff

! White
*color7: #bbbbbb
*color15: #ffffff

! Font settings
*font: -*-fixed-medium-r-*-*-14-*-*-*-*-*-*-*
EOF
    
    print_success ".Xresources created"
}

# Function to enable LightDM service
enable_lightdm() {
    print_status "Enabling LightDM service..."
    
    # Disable other display managers
    sudo systemctl disable gdm3 2>/dev/null || true
    sudo systemctl disable sddm 2>/dev/null || true
    sudo systemctl disable xdm 2>/dev/null || true
    
    # Enable LightDM
    sudo systemctl enable lightdm
    
    print_success "LightDM service enabled"
}

# Function to provide post-installation instructions
post_install_instructions() {
    print_success "DWM installation completed successfully!"
    echo
    print_status "Post-installation notes:"
    echo "1. DWM is now installed in $INSTALL_PREFIX/bin/dwm"
    echo "2. LightDM is configured and enabled"
    echo "3. A desktop entry has been created for DWM"
    echo "4. .xinitrc and .Xresources have been created in your home directory"
    echo
    print_warning "To complete the installation:"
    echo "1. Reboot your system: sudo reboot"
    echo "2. Select 'DWM' from the session menu in LightDM"
    echo "3. Log in with your credentials"
    echo
    print_status "DWM Key Bindings (default):"
    echo "• Alt+p: Open application launcher (dmenu)"
    echo "• Alt+Shift+Enter: Open terminal"
    echo "• Alt+j/k: Focus next/previous window"
    echo "• Alt+h/l: Decrease/increase master area"
    echo "• Alt+Enter: Move window to master area"
    echo "• Alt+Shift+c: Close window"
    echo "• Alt+Shift+q: Quit DWM"
    echo "• Alt+t: Tiled layout"
    echo "• Alt+f: Floating layout"
    echo "• Alt+m: Monocle layout"
    echo "• Alt+[1-9]: Switch to workspace"
    echo "• Alt+Shift+[1-9]: Move window to workspace"
    echo
    print_status "Configuration files:"
    echo "• DWM config: Recompile source after editing config.h"
    echo "• User session: ~/.xinitrc"
    echo "• X resources: ~/.Xresources"
    echo "• LightDM config: /etc/lightdm/lightdm.conf"
}

# Function to handle cleanup on exit
cleanup() {
    if [[ -d "$BUILD_DIR" ]]; then
        print_status "Cleaning up build directory..."
        rm -rf "$BUILD_DIR"
    fi
}

# Set up trap for cleanup
trap cleanup EXIT

# Main execution
main() {
    print_status "Starting DWM installation with LightDM..."
    echo "This script will install DWM ${DWM_VERSION} with LightDM on Debian/Ubuntu"
    echo
    
    check_root
    check_distro
    
    # Ask for confirmation
    read -p "Do you want to proceed with the installation? [y/N]: " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        print_status "Installation cancelled by user."
        exit 0
    fi
    
    update_packages
    fix_apt_issues
    install_dependencies
    create_build_dir
    download_dwm
    configure_dwm
    compile_dwm
    install_dwm
    create_desktop_entry
    configure_lightdm
    create_xinitrc
    create_xresources
    enable_lightdm
    post_install_instructions
}

# Run main function
main "$@"
