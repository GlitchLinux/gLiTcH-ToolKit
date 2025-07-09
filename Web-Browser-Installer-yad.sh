#!/bin/bash

# Simple Web Browser Installer with YAD

# Check if yad is installed
if ! command -v yad &> /dev/null; then
    echo "YAD is not installed. Please install it first:"
    echo "sudo apt update && sudo apt install yad"
    exit 1
fi

# Browser selection dialog
BROWSER=$(yad --list \
    --radiolist \
    --width=500 \
    --height=300 \
    --title="Browser Installer" \
    --text="Select a browser to install:" \
    --column="Select" \
    --column="Browser" \
    --column="Description" \
    FALSE "thorium" "Thorium Browser (Chromium-based)" \
    FALSE "brave" "Brave Browser (Privacy-focused)" \
    FALSE "tor" "Tor Browser Launcher" \
    --button="Install:0" \
    --button="Cancel:1")

# Exit if cancelled
if [ $? -ne 0 ]; then
    exit 0
fi

# Extract browser choice
CHOICE=$(echo $BROWSER | cut -d'|' -f2)

# Create temp directory
TEMP_DIR="/tmp/browser_install_$$"
mkdir -p "$TEMP_DIR"

# Function to install browser
install_browser() {
    case $CHOICE in
        "thorium")
            URL="https://github.com/Alex313031/thorium/releases/download/M130.0.6723.174/thorium-browser_130.0.6723.174_AVX.deb"
            FILE="thorium-browser.deb"
            ;;
        "brave")
            URL="https://github.com/brave/brave-browser/releases/download/v1.80.115/brave-browser_1.80.115_amd64.deb"
            FILE="brave-browser.deb"
            ;;
        "tor")
            URL="http://ftp.us.debian.org/debian/pool/contrib/t/torbrowser-launcher/torbrowser-launcher_0.3.7-3_amd64.deb"
            FILE="torbrowser-launcher.deb"
            ;;
        *)
            yad --error --text="Invalid selection!"
            exit 1
            ;;
    esac
    
    # Download
    yad --info --timeout=2 --text="Downloading $CHOICE browser..."
    
    if wget -O "$TEMP_DIR/$FILE" "$URL"; then
        yad --info --timeout=2 --text="Installing $CHOICE browser..."
        
        # Install
        if sudo dpkg -i "$TEMP_DIR/$FILE"; then
            sudo apt-get install -f -y
            yad --info --text="$CHOICE browser installed successfully!"
        else
            yad --error --text="Installation failed!"
        fi
    else
        yad --error --text="Download failed! Check your internet connection."
    fi
}

# Install the selected browser
install_browser

# Cleanup
rm -rf "$TEMP_DIR"
