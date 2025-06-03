#!/bin/bash

# Debian Headless to Desktop Environment Setup Script
# This script installs a desktop environment using tasksel

# Ensure the script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Try 'sudo ./install-desktop.sh'"
    exit 1
fi

# Function to display menu and get user choice
function select_desktop() {
    echo "Available Desktop Environments:"
    echo "1. GNOME (Default Debian desktop)"
    echo "2. KDE Plasma"
    echo "3. XFCE (Lightweight)"
    echo "4. LXDE (Very lightweight)"
    echo "5. MATE"
    echo "6. Cinnamon"
    echo "7. Exit"
    
    read -p "Enter your choice (1-7): " choice
    
    case $choice in
        1) 
            DE="gnome-desktop"
            DM="gdm3"
            ;;
        2) 
            DE="kde-desktop"
            DM="sddm"
            ;;
        3) 
            DE="xfce-desktop"
            DM="lightdm"
            ;;
        4) 
            DE="lxde-desktop"
            DM="lightdm"
            ;;
        5) 
            DE="mate-desktop"
            DM="lightdm"
            ;;
        6) 
            DE="cinnamon-desktop"
            DM="lightdm"
            ;;
        7) 
            echo "Exiting..."
            exit 0
            ;;
        *) 
            echo "Invalid choice. Please try again."
            select_desktop
            ;;
    esac
}

# Main installation function
function install_desktop() {
    echo "Starting desktop environment installation..."
    
    # Update system
    echo "Updating package lists..."
    apt update -y
    
    echo "Upgrading system..."
    apt upgrade -y
    
    # Install tasksel if not installed
    if ! command -v tasksel &> /dev/null; then
        echo "Installing tasksel..."
        apt install tasksel -y
    fi
    
    # Select desktop environment
    select_desktop
    
    # Install selected desktop
    echo "Installing $DE..."
    tasksel install $DE
    
    # Install display manager
    echo "Installing display manager ($DM)..."
    apt install $DM -y
    
    # Install common components
    echo "Installing additional components..."
    apt install xorg network-manager-gnome pulseaudio pavucontrol -y
    
    # Install recommended applications
    echo "Installing recommended applications..."
    apt install firefox-esr libreoffice thunar file-roller vlc gparted -y
    
    # Set graphical target
    echo "Configuring system to boot to graphical interface..."
    systemctl set-default graphical.target
    
    # Enable display manager
    echo "Enabling display manager..."
    systemctl enable $DM
    
    # Install remote access tools (optional)
    echo "Installing remote desktop tools..."
    apt install xrdp -y
    
    # Clean up
    echo "Cleaning up..."
    apt autoremove -y
    
    echo "Installation complete!"
    echo "Your system will now boot into $DE."
    echo "You can reboot now with: sudo reboot"
}

# Execute main function
install_desktop
