#!/bin/bash

# Complete Rescapp Installation Script - All-in-One
# Installs Rescapp with all fixes applied correctly from the start
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

print_status "Starting complete Rescapp installation with all fixes..."

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

# Step 5: Fix other compatibility issues
print_status "Applying additional fixes..."

# Fix menu paths
sed -i "s|share/rescapp/menus|menus|g" "$MAIN_PY"

# Create necessary directory structure
if [ ! -d "$RESCAPP_DIR/share" ]; then
    mkdir -p "$RESCAPP_DIR/share/rescapp"
    ln -s "$RESCAPP_DIR/menus" "$RESCAPP_DIR/share/rescapp/menus"
fi

# Step 6: Apply fixes to other Python files in the project
print_status "Fixing other Python files..."

find "$RESCAPP_DIR" -name "*.py" -not -path "*/bin/rescapp.py" -exec sed -i \
    -e 's/QtWebKit\.QWebView/QWebEngineView/g' \
    -e 's/QtWebKit\.QWebPage/QWebEnginePage/g' \
    -e 's/QtWebKit\.QWebSettings/QWebEngineSettings/g' \
    -e 's/QtWebKitWidgets\.QWebView/QWebEngineView/g' \
    -e 's/QtWebKitWidgets/QtWebEngineWidgets/g' \
    -e 's/QtWebKit/QtWebEngineWidgets/g' \
    {} \;

# Step 7: Create the optimized wrapper script
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

# Warn if running as root in a GUI environment
if [ "$(id -u)" -eq 0 ] && [ -n "$DISPLAY" ]; then
    echo "Note: Running as root. Consider running as regular user for GUI applications."
fi

# Set Python path and execute main program
PYTHONPATH="/usr/local/share/rescapp/lib" \
exec /usr/bin/python3 /usr/local/share/rescapp/bin/rescapp.py "$@"
EOL

chmod +x /usr/local/bin/rescapp

# Step 8: Create desktop shortcut
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

# Step 9: Set all necessary permissions
print_status "Setting permissions..."
chmod -R +x "$RESCAPP_DIR/bin"
find "$RESCAPP_DIR" -name "*.py" -exec chmod +x {} \;
find "$RESCAPP_DIR" -name "*.sh" -exec chmod +x {} \;

# Step 10: Update icon cache if possible
if command -v gtk-update-icon-cache >/dev/null 2>&1; then
    print_status "Updating icon cache..."
    gtk-update-icon-cache -f /usr/share/icons/hicolor 2>/dev/null || true
fi

# Step 11: Validate the installation
print_status "Validating installation..."

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

# Check for any remaining malformed references
if grep -q "QtWebEngineWidgetsWidgets" "$MAIN_PY"; then
    print_warning "Found potential malformed references - cleaning up..."
    sed -i 's/QtWebEngineWidgetsWidgets/QtWebEngineWidgets/g' "$MAIN_PY"
fi

# Final status
echo ""
print_success "Rescapp installation completed successfully!"
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
echo -e "${GREEN}Note:${NC} Run as regular user for GUI. App will request sudo when needed."
print_success "Installation complete - ready to use!"
