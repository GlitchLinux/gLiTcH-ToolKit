#!/bin/bash

# Rescapp Installation Script for Debian with QtWebKit to QtWebEngine fixes
# Version 1.1

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Check if running on Debian
if ! grep -qi 'debian' /etc/os-release; then
    echo "This script is intended for Debian systems only."
    exit 1
fi

# Update package lists
echo "Updating package lists..."
apt-get update

# Install required dependencies
echo "Installing dependencies..."
apt-get install -y \
    git \
    python3 \
    python3-pyqt5 \
    python3-pyqt5.qtsvg \
    python3-pyqt5.qtwebengine \
    qt5-qmake \
    gparted \
    testdisk \
    inxi \
    ntfs-3g \
    chntpw \
    gdisk \
    dosfstools \
    mtools \
    pastebinit

# Clone or update the Rescapp repository
RESCAPP_DIR="/usr/local/share/rescapp"
echo "Setting up Rescapp in $RESCAPP_DIR..."

if [ -d "$RESCAPP_DIR" ]; then
    echo "Rescapp directory already exists. Pulling latest changes..."
    cd "$RESCAPP_DIR" || exit 1
    git pull
else
    git clone https://github.com/rescatux/rescapp.git "$RESCAPP_DIR"
    cd "$RESCAPP_DIR" || exit 1
fi

# Find the main executable
MAIN_EXECUTABLE="$RESCAPP_DIR/bin/rescapp"
if [ ! -f "$MAIN_EXECUTABLE" ]; then
    echo "Error: Could not find main Rescapp executable."
    exit 1
fi

# Apply QtWebKit to QtWebEngine fixes
echo "Applying QtWebKit to QtWebEngine compatibility fixes..."

# Fix 1: Main executable
sed -i 's/from PyQt5 import QtGui, QtCore, QtWebKit, QtWidgets, QtWebKitWidgets/from PyQt5 import QtGui, QtCore, QtWidgets\nfrom PyQt5.QtWebEngineWidgets import QWebEngineView as QWebView/' "$MAIN_EXECUTABLE"

# Fix 2: Find and fix all Python files using QtWebKit
find "$RESCAPP_DIR" -type f -name "*.py" -exec sed -i \
    -e 's/QtWebKit/QtWebEngineWidgets/g' \
    -e 's/QWebPage/QWebEnginePage/g' \
    -e 's/QWebSettings/QWebEngineSettings/g' \
    -e 's/QWebView/QWebEngineView/g' \
    {} \;

# Create desktop shortcut
echo "Creating desktop shortcut..."
cat > /usr/share/applications/rescapp.desktop <<EOL
[Desktop Entry]
Name=Rescapp
Comment=Graphical Rescue Tool
Exec=/usr/local/bin/rescapp
Icon=$RESCAPP_DIR/gitrepo-images/rescapp-0.56-main-menu.png
Terminal=false
Type=Application
Categories=System;Utility;
EOL

# Create symlink in /usr/local/bin
echo "Creating symlink in /usr/local/bin..."
ln -sf "$MAIN_EXECUTABLE" /usr/local/bin/rescapp

# Set permissions
echo "Setting permissions..."
chmod +x "$MAIN_EXECUTABLE"
find "$RESCAPP_DIR" -name "*.py" -exec chmod +x {} \;
find "$RESCAPP_DIR" -name "*.sh" -exec chmod +x {} \;

# Update icon cache (if desktop environment is present)
if [ -x "$(command -v gtk-update-icon-cache)" ]; then
    echo "Updating icon cache..."
    gtk-update-icon-cache -f /usr/share/icons/hicolor
fi

# Create wrapper script as fallback
echo "Creating compatibility wrapper..."
cat > /usr/local/bin/rescapp-wrapper <<EOL
#!/usr/bin/python3
import os
import sys
from PyQt5 import QtGui, QtCore, QtWidgets
from PyQt5.QtWebEngineWidgets import QWebEngineView as QWebView

sys.path.insert(0, '/usr/local/share/rescapp/bin')
from rescapp import main

if __name__ == '__main__':
    main()
EOL
chmod +x /usr/local/bin/rescapp-wrapper

echo ""
echo "Rescapp installation complete with all fixes applied!"
echo "You can now run Rescapp by:"
echo "1. Typing 'rescapp' in a terminal"
echo "2. Or through your application menu (look for 'Rescapp')"
echo ""
echo "If you encounter any issues, try running 'rescapp-wrapper' instead."
echo ""
echo "Note: Some features require additional configuration or may not work"
echo "perfectly outside of the Rescatux live environment."
