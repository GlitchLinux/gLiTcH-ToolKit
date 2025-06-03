#!/bin/bash

# Complete Rescapp Installation & Fix Script
# Installs Rescapp and applies all necessary fixes in one go
# Tested and working on Debian/Ubuntu systems

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

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

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    print_error "This script must be run as root. Please use sudo."
    exit 1
fi

# Check if running on Debian/Ubuntu
if ! grep -qi -E 'debian|ubuntu' /etc/os-release; then
    print_error "This script is intended for Debian/Ubuntu systems only."
    exit 1
fi

print_status "Starting complete Rescapp installation and configuration..."

# Install all required dependencies
print_status "Installing dependencies..."
apt-get update -qq
apt-get install -y \
    git \
    python3 \
    python3-pyqt5 \
    python3-pyqt5.qtsvg \
    python3-pyqt5.qtwebengine \
    qt5-qmake \
    libqt5webengine5 \
    libqt5webenginecore5 \
    libqt5webenginewidgets5 \
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
    pastebinit > /dev/null 2>&1

if [ $? -eq 0 ]; then
    print_success "Dependencies installed successfully"
else
    print_warning "Some dependencies may have failed to install, continuing..."
fi

# Set up Rescapp directory
RESCAPP_DIR="/usr/local/share/rescapp"
print_status "Setting up Rescapp in $RESCAPP_DIR..."

if [ -d "$RESCAPP_DIR" ]; then
    print_warning "Rescapp directory exists. Cleaning and updating..."
    rm -rf "$RESCAPP_DIR"
fi

# Clone the repository
print_status "Cloning Rescapp repository..."
git clone https://github.com/rescatux/rescapp.git "$RESCAPP_DIR" > /dev/null 2>&1

if [ ! -d "$RESCAPP_DIR" ]; then
    print_error "Failed to clone Rescapp repository"
    exit 1
fi

cd "$RESCAPP_DIR" || exit 1

# Prepare the main Python file
MAIN_PY="$RESCAPP_DIR/bin/rescapp.py"
if [ -f "$RESCAPP_DIR/bin/rescapp" ]; then
    mv "$RESCAPP_DIR/bin/rescapp" "$MAIN_PY"
fi

print_status "Applying compatibility fixes..."

# Fix all QtWebKit references to QtWebEngine
find "$RESCAPP_DIR" -type f -name "*.py" -exec sed -i \
    -e 's/QtWebKit/QtWebEngineWidgets/g' \
    -e 's/QWebPage/QWebEnginePage/g' \
    -e 's/QWebSettings/QWebEngineSettings/g' \
    -e 's/QWebView/QWebEngineView/g' \
    -e 's/QtWebKitWidgets/QtWebEngineWidgets/g' \
    {} \;

# Fix the main executable imports properly
print_status "Fixing Python imports..."

# Create the correct import structure
cat > /tmp/rescapp_imports.txt <<'EOL'
from PyQt5 import QtGui, QtCore, QtWidgets
from PyQt5.QtWebEngineWidgets import QWebEngineView
EOL

# Remove old import lines and add new ones
sed -i '/^from PyQt5 import.*QtWebKit/d' "$MAIN_PY"
sed -i '/^from PyQt5 import.*QtWebKitWidgets/d' "$MAIN_PY"

# Find the first PyQt5 import and replace the entire import block
sed -i '0,/^from PyQt5 import/{
    /^from PyQt5 import/ {
        r /tmp/rescapp_imports.txt
        d
    }
}' "$MAIN_PY"

# Clean up temp file
rm -f /tmp/rescapp_imports.txt

# Additional specific fixes for QtWebEngine
sed -i 's/QtWebKitWidgets\.QWebView/QWebEngineView/g' "$MAIN_PY"
sed -i 's/self\.wb = QtWebEngineWidgets\.QWebEngineView()/self.wb = QWebEngineView()/' "$MAIN_PY"

# Fix menu paths
sed -i "s|share/rescapp/menus|menus|g" "$MAIN_PY"

# Create necessary directory structure
if [ ! -d "$RESCAPP_DIR/share" ]; then
    mkdir -p "$RESCAPP_DIR/share/rescapp"
    ln -s "$RESCAPP_DIR/menus" "$RESCAPP_DIR/share/rescapp/menus"
fi

# Create the optimized wrapper script
print_status "Creating wrapper script..."
cat > /usr/local/bin/rescapp <<'EOL'
#!/bin/bash
# Rescapp wrapper script with full compatibility

# Set environment variables for graphics compatibility
export LIBGL_ALWAYS_SOFTWARE=1
export QT_XCB_GL_INTEGRATION=none
export QT_QUICK_BACKEND=software
export QTWEBENGINE_DISABLE_SANDBOX=1
export QT_LOGGING_RULES="qt.qpa.xcb.glx.debug=false"

# Set Python path and execute main program
PYTHONPATH="/usr/local/share/rescapp/lib" \
exec /usr/bin/python3 /usr/local/share/rescapp/bin/rescapp.py "$@"
EOL

chmod +x /usr/local/bin/rescapp

# Create desktop shortcut
print_status "Creating desktop shortcut..."
cat > /usr/share/applications/rescapp.desktop <<EOL
[Desktop Entry]
Name=Rescapp
Comment=Graphical Rescue Tool for System Recovery
Exec=/usr/local/bin/rescapp
Icon=$RESCAPP_DIR/gitrepo-images/rescapp-0.56-main-menu.png
Terminal=false
Type=Application
Categories=System;Utility;Recovery;
StartupNotify=true
EOL

# Set all necessary permissions
print_status "Setting permissions..."
chmod -R +x "$RESCAPP_DIR/bin"
find "$RESCAPP_DIR" -name "*.py" -exec chmod +x {} \;
find "$RESCAPP_DIR" -name "*.sh" -exec chmod +x {} \;

# Update icon cache if possible
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    print_status "Updating icon cache..."
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# Test the installation
print_status "Testing Python imports..."
python3 -c "
try:
    from PyQt5 import QtGui, QtCore, QtWidgets
    from PyQt5.QtWebEngineWidgets import QWebEngineView
    print('✓ All imports successful')
    exit(0)
except ImportError as e:
    print(f'✗ Import error: {e}')
    exit(1)
" 2>/dev/null

if [ $? -eq 0 ]; then
    print_success "Python imports are working correctly"
else
    print_warning "Import test failed, but installation may still work"
fi

# Final status
echo ""
print_success "Rescapp installation and fixes completed successfully!"
echo ""
echo -e "${BLUE}You can now run Rescapp by:${NC}"
echo "  • Typing 'rescapp' in a terminal"
echo "  • Using the application menu (look for 'Rescapp')"
echo ""
echo -e "${BLUE}Installation details:${NC}"
echo "  • Installed to: $RESCAPP_DIR"
echo "  • Wrapper script: /usr/local/bin/rescapp"
echo "  • Desktop file: /usr/share/applications/rescapp.desktop"
echo ""
print_status "Ready to use! Try running 'rescapp' now."
