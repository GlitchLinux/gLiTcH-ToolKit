#!/bin/bash

# Install (requires root):
# sudo ./rescapp.sh --install

# Repair existing installation:
# sudo ./rescapp.sh --fix

# Normal run (default):
# ./rescapp.sh

# Rescapp Ultimate Installer & Runner
# Version 3.0 - Complete solution in one script

# ========================
# CONFIGURATION
# ========================
RESCAPP_DIR="/usr/local/share/rescapp"
DESKTOP_FILE="/usr/share/applications/rescapp.desktop"
BIN_PATH="/usr/local/bin/rescapp"

# ========================
# FUNCTIONS
# ========================
RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; NC='\033[0m'

die() { echo -e "${RED}$1${NC}"; exit 1; }
status() { echo -e "${BLUE}[+]${NC} $1"; }
success() { echo -e "${GREEN}[✓]${NC} $1"; }
warning() { echo -e "${YELLOW}[!]${NC} $1"; }

# ========================
# INSTALLATION SECTION
# ========================
install_rescapp() {
    # Verify root
    [ "$(id -u)" -ne 0 ] && die "Must run as root. Use sudo."
    
    status "Installing dependencies..."
    apt-get update -qq && apt-get install -y \
        git python3 python3-pyqt5 python3-pyqt5.qtsvg python3-pyqt5.qtwebengine \
        qt5-qmake libqt5webengine5 libqt5webenginecore5 libqt5webenginewidgets5 \
        gparted testdisk inxi ntfs-3g chntpw gdisk dosfstools mtools pastebinit \
        qt5-style-plugins adwaita-qt > /dev/null || warning "Some dependencies may have issues"

    # Clone or update repository
    if [ -d "$RESCAPP_DIR" ]; then
        status "Updating existing installation..."
        cd "$RESCAPP_DIR" || die "Couldn't enter Rescapp directory"
        git pull || warning "Git pull failed - using existing files"
    else
        status "Cloning Rescapp repository..."
        git clone https://github.com/rescatux/rescapp.git "$RESCAPP_DIR" || die "Clone failed"
    fi

    # Fix main executable
    [ -f "$RESCAPP_DIR/bin/rescapp" ] && mv "$RESCAPP_DIR/bin/rescapp" "$RESCAPP_DIR/bin/rescapp.py"

    # Create launcher
    status "Creating launcher..."
    cat > "$RESCAPP_DIR/bin/rescapp-launcher" <<'EOL'
#!/bin/bash
export RESCAPP_DIR="$(dirname "$(dirname "$(readlink -f "$0")")"
export QT_AUTO_SCREEN_SCALE_FACTOR=0
export QT_STYLE_OVERRIDE=fusion
export QT_QPA_PLATFORM=xcb
export LIBGL_ALWAYS_SOFTWARE=1
exec python3 "$RESCAPP_DIR/bin/rescapp.py" "$@"
EOL
    chmod +x "$RESCAPP_DIR/bin/rescapp-launcher"

    # Apply critical patches
    status "Applying compatibility fixes..."
    sed -i 's/QtWebKit/QtWebEngineWidgets/g' "$RESCAPP_DIR/bin/rescapp.py"
    sed -i '1i\from PyQt5.QtWebEngineWidgets import QWebEngineView' "$RESCAPP_DIR/bin/rescapp.py"

    # Create system symlink
    status "Creating system integration..."
    cat > "$BIN_PATH" <<'EOL'
#!/bin/bash
export RESCAPP_DIR="/usr/local/share/rescapp"
export QT_QPA_PLATFORMTHEME=qt5ct
export QT_QUICK_BACKEND=software
exec python3 "$RESCAPP_DIR/bin/rescapp.py" "$@"
EOL
    chmod +x "$BIN_PATH"

    # Desktop file
    status "Creating desktop shortcut..."
    cat > "$DESKTOP_FILE" <<EOL
[Desktop Entry]
Name=Rescapp
Comment=Graphical Rescue Tool
Exec=$BIN_PATH
Icon=$RESCAPP_DIR/gitrepo-images/rescapp-0.56-main-menu.png
Terminal=false
Type=Application
Categories=System;Utility;
EOL

    # Set permissions
    chmod -R a+r "$RESCAPP_DIR"
    find "$RESCAPP_DIR/bin" -type f -exec chmod +x {} \;

    success "Installation complete!"
    echo -e "Run with: ${GREEN}rescapp${NC} or ${GREEN}$BIN_PATH${NC}"
}

# ========================
# EXECUTION SECTION
# ========================
run_rescapp() {
    # Optimized environment for running
    export RESCAPP_DIR="/usr/local/share/rescapp"
    export QT_QPA_PLATFORM=xcb
    export QT_STYLE_OVERRIDE=Adwaita
    export QT_QUICK_BACKEND=software
    export LIBGL_ALWAYS_SOFTWARE=1
    
    # Verify installation
    [ ! -f "$RESCAPP_DIR/bin/rescapp.py" ] && die "Rescapp not installed! Run with --install first"
    
    # Execute
    exec python3 "$RESCAPP_DIR/bin/rescapp.py" "$@"
}

# ========================
# MAIN LOGIC
# ========================
case "$1" in
    --install)
        install_rescapp
        ;;
    --fix)
        install_rescapp  # Same as install but doesn't error if existing
        ;;
    *)
        run_rescapp "$@"
        ;;
esac
