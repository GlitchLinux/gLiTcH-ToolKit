#!/bin/bash

# Complete Debian Headless to Desktop Environment Setup Script
# Handles bare systems with no additional tools installed

# Check for root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Try: sudo bash $0"
    exit 1
fi

# Function to install essential base tools
install_base_tools() {
    echo "Installing essential system tools..."
    apt-get update
    apt-get install -y --no-install-recommends \
        wget curl nano sudo apt-utils dialog \
        software-properties-common gnupg2 \
        locales keyboard-configuration \
        network-manager dbus-x11
}

# Function to configure basic system settings
configure_system() {
    echo "Configuring basic system settings..."
    
    # Set locale
    sed -i '/en_US.UTF-8/s/^# //g' /etc/locale.gen
    locale-gen
    update-locale LANG=en_US.UTF-8
    
    # Ensure sudo is properly configured
    if ! grep -q '^%sudo.*ALL$' /etc/sudoers; then
        echo "%sudo ALL=(ALL:ALL) ALL" >> /etc/sudoers
    fi
    
    # Enable non-free repos if needed
    if ! grep -q "non-free" /etc/apt/sources.list; then
        sed -i '/^deb / s/$/ non-free contrib/' /etc/apt/sources.list
    fi
    
    # Update again with new repos
    apt-get update
}

# Function to install tasksel properly
install_tasksel() {
    if ! command -v tasksel >/dev/null; then
        echo "Installing tasksel..."
        apt-get install -y tasksel
    fi
    
    # Verify tasksel installation
    if ! tasksel --list-tasks >/dev/null 2>&1; then
        echo "Failed to install tasksel properly. Trying manual fix..."
        apt-get install --reinstall tasksel debconf-utils -y
    fi
}

# Function to select desktop environment using dialog
select_desktop() {
    DE=""
    DM=""
    
    # Install dialog if not present
    if ! command -v dialog >/dev/null; then
        apt-get install -y dialog
    fi
    
    while [ -z "$DE" ]; do
        choice=$(dialog --clear --backtitle "Debian Desktop Installer" \
            --title "Select Desktop Environment" \
            --menu "Choose your preferred desktop environment:" 15 50 6 \
            1 "GNOME (Modern, full-featured)" \
            2 "KDE Plasma (Feature-rich, customizable)" \
            3 "XFCE (Lightweight, stable)" \
            4 "LXQt (Very lightweight, modern)" \
            5 "MATE (Traditional GNOME 2 fork)" \
            6 "Cinnamon (Modern, traditional layout)" \
            2>&1 >/dev/tty)
        
        case $choice in
            1) DE="gnome-desktop"; DM="gdm3" ;;
            2) DE="kde-desktop"; DM="sddm" ;;
            3) DE="xfce-desktop"; DM="lightdm" ;;
            4) DE="lxqt-desktop"; DM="sddm" ;;
            5) DE="mate-desktop"; DM="lightdm" ;;
            6) DE="cinnamon-desktop"; DM="lightdm" ;;
            *) echo "Invalid option"; continue ;;
        esac
    done
    
    # Special case for LXDE (not in standard tasksel)
    if [ "$DE" = "lxqt-desktop" ]; then
        DE="task-lxqt-desktop"
    fi
    
    clear
}

# Function to install the selected desktop
install_desktop() {
    echo "Installing $DE..."
    
    # Install tasksel first if not done already
    install_tasksel
    
    # Special handling for LXQt
    if [ "$DE" = "task-lxqt-desktop" ]; then
        apt-get install -y task-lxqt-desktop
    else
        tasksel install $DE
    fi
    
    # Install display manager
    echo "Installing display manager: $DM"
    apt-get install -y $DM
    
    # Basic xorg and audio
    echo "Installing core graphical components..."
    apt-get install -y \
        xserver-xorg xinit x11-xserver-utils \
        pulseaudio pavucontrol \
        fonts-dejavu fonts-liberation \
        network-manager-gnome
    
    # Common utilities
    echo "Installing common desktop utilities..."
    apt-get install -y \
        firefox-esr libreoffice \
        thunar file-roller gvfs-backends \
        gnome-disk-utility gparted \
        vlc mpv \
        synaptic software-properties-gtk
    
    # Set graphical target
    systemctl set-default graphical.target
    systemctl enable $DM
}

# Function to install recommended extras
install_extras() {
    echo "Installing recommended extras..."
    
    # Hardware support
    apt-get install -y \
        firmware-linux firmware-linux-nonfree \
        firmware-realtek firmware-atheros \
        firmware-amd-graphics
    
    # Remote access
    apt-get install -y \
        xrdp remmina
    
    # Printer support
    apt-get install -y \
        cups system-config-printer
    
    # Development tools
    apt-get install -y \
        build-essential git
}

# Main installation process
main() {
    # Phase 1: Base system setup
    install_base_tools
    configure_system
    
    # Phase 2: Desktop selection and installation
    select_desktop
    install_desktop
    
    # Phase 3: Optional extras
    if dialog --yesno "Install recommended extras (hardware support, remote access, printing)?" 8 50; then
        install_extras
    fi
    
    # Final cleanup
    apt-get autoremove -y
    apt-get clean
    
    # Completion message
    clear
    echo "Desktop environment installation complete!"
    echo ""
    echo "Installed: $DE"
    echo "Display Manager: $DM"
    echo ""
    echo "You can now reboot into your new desktop environment:"
    echo "  sudo reboot"
    echo ""
    echo "For remote access, you can use:"
    echo "  SSH with X11 forwarding or xrdp (port 3389)"
}

# Execute main function
main
