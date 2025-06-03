#!/bin/bash

# Final Rescapp Installation Script with Proper Wrapper Separation
# Fixes all known issues including QtWebEngine, OpenGL, and execution problems

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

# Install required dependencies
echo "Installing dependencies..."
apt-get update
apt-get install -y \
    git \
    python3 \
    python3-pyqt5 \
    python3-pyqt5.qtsvg \
    python3-pyqt5.qtwebengine \
    qt5-qmake \
    libgl1-mesa-dri \
    libgl1-mesa-glx \
    libegl1-mesa \
    libllvm15 \
    gparted \
    testdisk \
    inxi \
    ntfs-3g \
    chntpw \
    gdisk \
    dosfstools \
    mtools \
    pastebinit

# Set up Rescapp
RESCAPP_DIR="/usr/local/share/rescapp"
echo "Setting up Rescapp in $RESCAPP_DIR..."

if [ -d "$RESCAPP_DIR" ]; then
    echo "Rescapp directory exists. Cleaning and updating..."
    rm -rf "$RESCAPP_DIR"
fi

git clone https://github.com/rescatux/rescapp.git "$RESCAPP_DIR"
cd "$RESCAPP_DIR" || exit 1

# Apply all necessary fixes
echo "Applying fixes..."

# 1. Fix QtWebKit to QtWebEngine in all Python files
find "$RESCAPP_DIR" -type f -name "*.py" -exec sed -i \
    -e 's/QtWebKit/QtWebEngineWidgets/g' \
    -e 's/QWebPage/QWebEnginePage/g' \
    -e 's/QWebSettings/QWebEngineSettings/g' \
    -e 's/QWebView/QWebEngineView/g' \
    {} \;

# 2. Fix main executable imports
MAIN_PY="$RESCAPP_DIR/bin/rescapp.py"
mv "$RESCAPP_DIR/bin/rescapp" "$MAIN_PY"
sed -i 's/from PyQt5 import QtGui, QtCore, QtWebKit, QtWidgets, QtWebKitWidgets/from PyQt5 import QtGui, QtCore, QtWidgets\nfrom PyQt5.QtWebEngineWidgets import QWebEngineView as QWebView/' "$MAIN_PY"

# 3. Fix menu paths
sed -i "s|share/rescapp/menus|menus|g" "$MAIN_PY"
if [ ! -d "$RESCAPP_DIR/share" ]; then
    mkdir -p "$RESCAPP_DIR/share/rescapp"
    ln -s "$RESCAPP_DIR/menus" "$RESCAPP_DIR/share/rescapp/menus"
fi

# 4. Create proper wrapper script
cat > /usr/local/bin/rescapp <<'EOL'
#!/bin/bash
# Rescapp wrapper script to ensure proper environment

# Set environment variables for graphics
export LIBGL_ALWAYS_SOFTWARE=1
export QT_XCB_GL_INTEGRATION=none

# Set Python path and execute main program
PYTHONPATH="/usr/local/share/rescapp/lib" \
/usr/bin/python3 /usr/local/share/rescapp/bin/rescapp.py "$@"
EOL
chmod +x /usr/local/bin/rescapp

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

# Set permissions
echo "Setting permissions..."
chmod -R +x "$RESCAPP_DIR/bin"
find "$RESCAPP_DIR" -name "*.py" -exec chmod +x {} \;
find "$RESCAPP_DIR" -name "*.sh" -exec chmod +x {} \;

# Update icon cache
if [ -x "$(command -v gtk-update-icon-cache)" ]; then
    echo "Updating icon cache..."
    gtk-update-icon-cache -f /usr/share/icons/hicolor
fi

# Fixes all remaining QtWebEngine and OpenGL issues

# 1. Install missing dependencies
sudo apt-get update
sudo apt-get install -y \
    python3-pyqt5.qtwebengine \
    python3-pyqt5.qtsvg \
    libqt5webengine5 \
    libqt5webenginecore5 \
    libqt5webenginewidgets5 \
    libgl1-mesa-dri \
    libegl1-mesa \
    libllvm15

# 2. Fix the main Python file imports
sudo sed -i 's/QtWebKitWidgets.QWebView/QtWebEngineWidgets.QWebEngineView/g' /usr/local/share/rescapp/bin/rescapp.py
sudo sed -i 's/from PyQt5 import QtWebKitWidgets/from PyQt5 import QtWebEngineWidgets/g' /usr/local/share/rescapp/bin/rescapp.py

# 3. Add missing import at the top of the file
if ! grep -q "QtWebEngineWidgets" /usr/local/share/rescapp/bin/rescapp.py; then
    sudo sed -i '/from PyQt5 import/ s/$/, QtWebEngineWidgets/' /usr/local/share/rescapp/bin/rescapp.py
fi

# 4. Update the wrapper script
sudo tee /usr/local/bin/rescapp >/dev/null <<'EOL'
#!/bin/bash
# Rescapp wrapper with proper environment

# Set OpenGL fallback
export LIBGL_ALWAYS_SOFTWARE=1
export QT_XCB_GL_INTEGRATION=xcb_egl

# Set Python path and run
PYTHONPATH="/usr/local/share/rescapp/lib" \
/usr/bin/python3 /usr/local/share/rescapp/bin/rescapp.py "$@"
EOL

# 5. Fix permissions
sudo chmod +x /usr/local/bin/rescapp
sudo chmod +x /usr/local/share/rescapp/bin/rescapp.py

# 6. Create required symlinks
sudo mkdir -p /usr/local/share/rescapp/share/rescapp
sudo ln -sf /usr/local/share/rescapp/menus /usr/local/share/rescapp/share/rescapp/menus

echo "All fixes applied. Try running 'rescapp' now."

echo "All fixes applied. Try running 'rescapp' now."

echo ""
echo "Rescapp installation complete with all fixes applied!"
echo "You can now run Rescapp by:"
echo "1. Typing 'rescapp' in a terminal"
echo "2. Or through your application menu (look for 'Rescapp')"
echo ""
echo "Note: The software renderer is being used to avoid graphics issues."
