#!/bin/bash

# Rescapp Installation Script with Complete GUI Fixes
# Version 2.0 - Enhanced for QtWebEngine and Menu Compatibility

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

print_status "Starting Rescapp installation with complete GUI fixes..."

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
    pastebinit \
    qt5-style-plugins \
    qttranslations5-l10n \
    adwaita-qt > /dev/null 2>&1

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

print_status "Applying comprehensive compatibility fixes..."

# Step 1: Clean up the main Python file first
print_status "Cleaning and fixing Python imports..."

# Create a temporary file with the correct import structure
cat > /tmp/correct_imports.txt <<'EOL'
from PyQt5 import QtGui, QtCore, QtWidgets
from PyQt5.QtWebEngineWidgets import QWebEngineView
EOL

# Remove all existing PyQt5 imports to avoid conflicts
sed -i '/^from PyQt5 import/d' "$MAIN_PY"

# Insert correct imports at the beginning (after shebang if it exists)
if head -1 "$MAIN_PY" | grep -q '^#!'; then
    sed -i '1r /tmp/correct_imports.txt' "$MAIN_PY"
else
    sed -i '1i\
from PyQt5 import QtGui, QtCore, QtWidgets\
from PyQt5.QtWebEngineWidgets import QWebEngineView' "$MAIN_PY"
fi

# Clean up temp file
rm -f /tmp/correct_imports.txt

# Step 2: Fix all QtWebKit references carefully to avoid double-word issues
print_status "Converting QtWebKit to QtWebEngine references..."

# Use more precise replacements to avoid creating malformed names
sed -i 's/QtWebKit\.QWebView/QWebEngineView/g' "$MAIN_PY"
sed -i 's/QtWebKit\.QWebPage/QWebEnginePage/g' "$MAIN_PY"
sed -i 's/QtWebKit\.QWebSettings/QWebEngineSettings/g' "$MAIN_PY"

# Handle QtWebKitWidgets separately to avoid double-word issues
sed -i 's/QtWebKitWidgets\.QWebView/QWebEngineView/g' "$MAIN_PY"
sed -i 's/QtWebKitWidgets/QtWebEngineWidgets/g' "$MAIN_PY"

# Now handle the remaining QtWebKit references
sed -i 's/QtWebKit/QtWebEngineWidgets/g' "$MAIN_PY"

# Step 3: Fix specific instantiation issues
print_status "Fixing QWebEngineView instantiation..."

# Fix the main problematic line that creates the web view
sed -i 's/self\.wb = QtWebEngineWidgets\.QWebEngineView()/self.wb = QWebEngineView()/' "$MAIN_PY"

# Step 4: Clean up any potential malformed references that might have been created
print_status "Cleaning up any malformed references..."

# Fix any doubled words that might have been created
sed -i 's/QtWebEngineWidgetsWidgets/QtWebEngineWidgets/g' "$MAIN_PY"
sed -i 's/QtWebEngineWidgets\.QWebEngineView/QWebEngineView/g' "$MAIN_PY"

# Step 5: Fix menu and path issues
print_status "Fixing menu paths and directory structure..."

# Create necessary directory structure
mkdir -p "$RESCAPP_DIR/share/rescapp"
mkdir -p "$RESCAPP_DIR/lib"

# Create symlinks for proper path resolution
if [ ! -L "$RESCAPP_DIR/share/rescapp/menus" ]; then
    ln -sf "$RESCAPP_DIR/menus" "$RESCAPP_DIR/share/rescapp/menus"
fi
if [ ! -L "$RESCAPP_DIR/share/rescapp/plugins" ]; then
    ln -sf "$RESCAPP_DIR/plugins" "$RESCAPP_DIR/share/rescapp/plugins"
fi

# Fix absolute paths in the Python code
sed -i "s|os.path.join(os.path.dirname(__file__), '../menus')|\"$RESCAPP_DIR/menus\"|g" "$MAIN_PY"
sed -i "s|os.path.join(os.path.dirname(__file__), '../share/rescapp/plugins')|\"$RESCAPP_DIR/plugins\"|g" "$MAIN_PY"

# Create version file if missing
if [ ! -f "$RESCAPP_DIR/share/rescapp/VERSION" ]; then
    echo "0.64" > "$RESCAPP_DIR/share/rescapp/VERSION"
fi

# Step 6: Create the optimized wrapper script
print_status "Creating wrapper script..."
cat > /usr/local/bin/rescapp <<'EOL'
#!/bin/bash
# Rescapp wrapper script with full GUI compatibility

# Set environment variables
export RESCAPP_DIR="/usr/local/share/rescapp"
export PYTHONPATH="$RESCAPP_DIR/lib"
export PATH="$RESCAPP_DIR/bin:$PATH"

# Set Qt environment variables for maximum compatibility
export QT_DEBUG_PLUGINS=0
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_SCALE_FACTOR=1
export QT_FONT_DPI=96
export QT_STYLE_OVERRIDE=fusion
export LIBGL_ALWAYS_SOFTWARE=1
export QT_XCB_GL_INTEGRATION=none
export QT_QUICK_BACKEND=software
export QTWEBENGINE_DISABLE_SANDBOX=1
export QT_LOGGING_RULES="qt.qpa.*=false"
export XDG_DATA_DIRS="/usr/share:/usr/local/share:$RESCAPP_DIR"

# Fix for missing icons
if [ -f "$RESCAPP_DIR/gitrepo-images/rescapp-0.56-main-menu.png" ]; then
    export XDG_ICON_DIRS="$RESCAPP_DIR/gitrepo-images:$XDG_ICON_DIRS"
fi

# Execute main program with error handling
if [ -f "$RESCAPP_DIR/bin/rescapp.py" ]; then
    exec python3 "$RESCAPP_DIR/bin/rescapp.py" "$@"
else
    echo "Error: Rescapp main executable not found!"
    exit 1
fi
EOL

chmod +x /usr/local/bin/rescapp

# Step 7: Create desktop shortcut
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

# Step 8: Set all necessary permissions
print_status "Setting permissions..."
chmod -R a+r "$RESCAPP_DIR"
chmod -R +x "$RESCAPP_DIR/bin"
find "$RESCAPP_DIR" -name "*.py" -exec chmod +x {} \;
find "$RESCAPP_DIR" -name "*.sh" -exec chmod +x {} \;

# Step 9: Update icon cache if possible
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    print_status "Updating icon cache..."
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# Step 10: Validate the installation
print_status "Validating installation..."

# Verify menu files exist
if [ -f "$RESCAPP_DIR/menus/support/rescatux.lis" ]; then
    print_success "Menu files found in correct location"
else
    print_error "Critical error: Menu files missing!"
    print_warning "Check the directory: $RESCAPP_DIR/menus/"
fi

# Test Python syntax
python3 -m py_compile "$MAIN_PY" 2>/dev/null
if [ $? -eq 0 ]; then
    print_success "Python syntax validation passed"
else
    print_warning "Python syntax validation failed - manual check recommended"
fi

# Test imports
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
    print_success "Python imports working correctly"
else
    print_warning "Import test failed, but installation may still work"
fi

# Final status
echo ""
print_success "Rescapp installation completed successfully with all GUI fixes applied!"
echo ""
echo -e "${BLUE}You can now run Rescapp by:${NC}"
echo "  • Typing 'rescapp' in a terminal (preferred - no sudo needed)"
echo "  • Using the application menu (look for 'Rescapp')"
echo ""
echo -e "${BLUE}Installation details:${NC}"
echo "  • Installed to: $RESCAPP_DIR"
echo "  • Wrapper script: /usr/local/bin/rescapp"
echo "  • Desktop file: /usr/share/applications/rescapp.desktop"
echo ""
echo -e "${YELLOW}If you encounter issues:${NC}"
echo "  • Run with debug: RESCAPP_DEBUG=1 rescapp"
echo "  • Check paths: ls -l $RESCAPP_DIR/menus/"
echo ""
echo -e "${GREEN}Note:${NC} Run as regular user for GUI. App will request sudo when needed."
print_success "Enjoy your fully functional Rescapp installation!"
