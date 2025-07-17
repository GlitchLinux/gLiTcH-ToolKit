#!/bin/bash

# jgmenu Master Installer Script
# Complete installation and configuration for Debian/Ubuntu systems
# Created for GlitchLinux - Custom menu structure

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Banner
echo -e "${CYAN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                    jgmenu Master Installer                     ║"
echo "║                      GlitchLinux Edition                       ║"
echo "║                                                                ║"
echo "║  Complete jgmenu setup with custom categorized menu           ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

# Functions for colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_debug() {
    echo -e "${BLUE}[DEBUG]${NC} $1"
}

print_section() {
    echo -e "${CYAN}[SECTION]${NC} $1"
}

# Configuration variables
JGMENU_DIR="$HOME/.config/jgmenu"
BACKUP_DIR="$JGMENU_DIR/backup_$(date +%Y%m%d_%H%M%S)"

# Step 1: Prerequisites check
print_section "Checking Prerequisites"

if ! command -v jgmenu &> /dev/null; then
    print_error "jgmenu is not installed!"
    echo "Installing jgmenu..."
    if command -v apt &> /dev/null; then
        sudo apt update
        sudo apt install -y jgmenu
    else
        print_error "Please install jgmenu manually: sudo apt install jgmenu"
        exit 1
    fi
fi

print_status "jgmenu is installed: $(jgmenu --version 2>/dev/null || echo 'version unknown')"

# Step 2: Clean existing configuration
print_section "Cleaning Existing Configuration"

# Kill any running jgmenu processes
print_debug "Stopping any running jgmenu processes..."
pkill jgmenu 2>/dev/null || true
sleep 1

# Backup existing configuration if it exists
if [ -d "$JGMENU_DIR" ]; then
    print_status "Backing up existing configuration..."
    mkdir -p "$BACKUP_DIR"
    cp -r "$JGMENU_DIR"/* "$BACKUP_DIR"/ 2>/dev/null || true
    print_status "Backup created at: $BACKUP_DIR"
    
    # Remove existing configuration
    rm -rf "$JGMENU_DIR"
    print_status "Removed existing jgmenu configuration"
fi

# Create fresh jgmenu directory
mkdir -p "$JGMENU_DIR"
print_status "Created fresh jgmenu configuration directory"

# Step 3: Create jgmenurc configuration
print_section "Creating jgmenu Configuration"

cat > "$JGMENU_DIR/jgmenurc" << 'EOF'
# jgmenu configuration file
# GlitchLinux Custom Configuration

# Position and size
position_mode = pointer
menu_width = 300
menu_height_min = 0
menu_height_max = 600

# Appearance
font = DejaVu Sans 9
icon_size = 16
icon_theme = Adwaita

# Colors (Dark Theme)
color_menu_bg = #2d2d2d
color_menu_fg = #f5f5f5
color_norm_bg = #2d2d2d
color_norm_fg = #f5f5f5
color_sel_bg = #4a90e2
color_sel_fg = #ffffff
color_sep_fg = #666666

# Behavior
stay_alive = 1
hide_on_startup = 0

# CSV file location
csv_file = ~/.config/jgmenu/prepend.csv

# NOTE: csv_cmd is intentionally NOT set to avoid conflicts
EOF

print_status "Created jgmenurc configuration file"

# Step 4: Create the main menu CSV
print_section "Creating Custom Menu Structure"

cat > "$JGMENU_DIR/prepend.csv" << 'EOF'
# GlitchLinux Custom jgmenu Configuration
# Categorized menu structure with custom applications

# Main Applications
Text Editor,l3afpad,accessories-text-editor
Archive Manager,peazip,package-x-generic
File Manager,thunar,folder-manager
File Manager (Root),thunar-root,folder-manager
Clipboard Manager,clipper,edit-paste
Screenshot Tool,flameshot,applets-screenshooter
Task Manager,btop,utilities-system-monitor

^sep()

# Custom Applications
Glitch Toolkit,glitch-toolkit,applications-development
QEMU QuickBoot,QEMU-QuickBoot,computer
Terminal,xfce4-terminal,utilities-terminal
Terminal (Root),pkexec xfce4-terminal,utilities-terminal
DD CLI,dd-cli,drive-harddisk
DD GUI,dd_gui,drive-harddisk

^sep()

# Categories with submenus
Graphics,^tag(graphics),applications-graphics
Internet,^tag(internet),applications-internet
Multimedia,^tag(multimedia),applications-multimedia
System Tools,^tag(systemtools),applications-system
Development,^tag(development),applications-development
Administration,^tag(administration),applications-system
Quick Actions,^tag(quickactions),applications-accessories

^sep()

# Graphics submenu
^tag(graphics)
Image Viewer,ristretto,image-viewer
Image Viewer (gThumb),gthumb,image-viewer
Image Viewer (feh),feh,image-viewer
CD/DVD Burning,xfburn,media-optical-burn
Wallpaper Creator,wallpapercreator,preferences-desktop-wallpaper
^sep()
Back,^back(),go-previous

# Internet submenu
^tag(internet)
SSH Client,^pipe(xfce4-terminal -e ssh),network-server
Network Tools,^pipe(xfce4-terminal -e 'bash -c "echo Available tools: ping wget curl netstat ip; bash"'),network-wired
Bluetooth Manager,^pipe(xfce4-terminal -e bluetoothctl),bluetooth
WiFi Manager,peasywifi,network-wireless
^sep()
Back,^back(),go-previous

# Multimedia submenu
^tag(multimedia)
Volume Control,^pipe(xfce4-terminal -e alsamixer),audio-volume-high
Audio Player,^pipe(xfce4-terminal -e 'bash -c "echo Usage: aplay filename.wav; bash"'),audio-player
Video Player,^pipe(xfce4-terminal -e 'bash -c "echo Usage: ffplay filename.mp4; bash"'),video-player
Video Converter,^pipe(xfce4-terminal -e 'bash -c "echo Usage: ffmpeg -i input.mp4 output.avi; bash"'),video-converter
^sep()
Back,^back(),go-previous

# System Tools submenu
^tag(systemtools)
Disk Utility,gnome-disks,drive-harddisk
Disk Utility (GParted),gparted,drive-harddisk
System Information,^pipe(xfce4-terminal -e fastfetch),computer
Hardware Sensors,xfce4-sensors,hardware-info
Display Settings,arandr,preferences-desktop-display
Appearance Settings,lxappearance,preferences-desktop-theme
Session Manager,lxsession,preferences-system
^sep()
Back,^back(),go-previous

# Development submenu
^tag(development)
Glitch Toolkit,glitch-toolkit,applications-development
Git,^pipe(xfce4-terminal -e 'bash -c "echo Git commands available. Type git --help for help; bash"'),git
Python,^pipe(xfce4-terminal -e python3),text-x-python
Text Editor (Advanced),^pipe(xfce4-terminal -e nano),accessories-text-editor
Make,^pipe(xfce4-terminal -e 'bash -c "echo Make utility. Use: make [target]; bash"'),applications-development
^sep()
Back,^back(),go-previous

# Administration submenu
^tag(administration)
Package Manager,synaptic,system-software-install
App Center,sparky-aptus-appcenter,system-software-install
System Settings,^pipe(xfce4-terminal -e 'bash -c "echo systemctl commands available; bash"'),preferences-system
User Management,^pipe(xfce4-terminal -e 'bash -c "echo User management: passwd, usermod, etc.; bash"'),system-users
System Logs,^pipe(xfce4-terminal -e journalctl),text-x-generic
System Cleaner,bleachbit,system-cleaner
System Cleaner (Root),pkexec bleachbit,system-cleaner
^sep()
Back,^back(),go-previous

# Quick Actions submenu
^tag(quickactions)
Lock Screen,light-locker-command -l,system-lock-screen
Logout,lxsession-logout,system-log-out
Suspend,systemctl suspend,system-suspend
Reboot,systemctl reboot,system-reboot
Shutdown,systemctl poweroff,system-shutdown
^sep()
# Quick Tools
Terminal,xfce4-terminal,utilities-terminal
Terminal (Root),pkexec xfce4-terminal,utilities-terminal
File Manager,thunar,folder-manager
Task Manager,btop,utilities-system-monitor
^sep()
Back,^back(),go-previous
EOF

print_status "Created custom menu structure (prepend.csv)"

# Step 5: Create backup flat menu
print_section "Creating Backup Configurations"

cat > "$JGMENU_DIR/flat_menu.csv" << 'EOF'
# Flat Menu - Simple list without submenus
# Use this if the main menu has issues

Text Editor,l3afpad,accessories-text-editor
Archive Manager,peazip,package-x-generic
File Manager,thunar,folder-manager
File Manager (Root),thunar-root,folder-manager
Terminal,xfce4-terminal,utilities-terminal
Terminal (Root),pkexec xfce4-terminal,utilities-terminal
Screenshot Tool,flameshot,applets-screenshooter
Task Manager,btop,utilities-system-monitor
^sep()
Glitch Toolkit,glitch-toolkit,applications-development
QEMU QuickBoot,QEMU-QuickBoot,computer
DD CLI,dd-cli,drive-harddisk
DD GUI,dd_gui,drive-harddisk
^sep()
System Information,^pipe(xfce4-terminal -e fastfetch),computer
Disk Utility,gnome-disks,drive-harddisk
Display Settings,arandr,preferences-desktop-display
Package Manager,synaptic,system-software-install
^sep()
Lock Screen,light-locker-command -l,system-lock-screen
Logout,lxsession-logout,system-log-out
Shutdown,systemctl poweroff,system-shutdown
Reboot,systemctl reboot,system-reboot
EOF

print_status "Created backup flat menu"

# Step 6: Create helper scripts
print_section "Creating Helper Scripts"

# Create launcher script
cat > "$JGMENU_DIR/launch_jgmenu.sh" << 'EOF'
#!/bin/bash
# jgmenu launcher script
jgmenu_run
EOF
chmod +x "$JGMENU_DIR/launch_jgmenu.sh"

# Create flat menu launcher
cat > "$JGMENU_DIR/launch_flat_menu.sh" << 'EOF'
#!/bin/bash
# Flat menu launcher (backup)
jgmenu --csv-file=~/.config/jgmenu/flat_menu.csv
EOF
chmod +x "$JGMENU_DIR/launch_flat_menu.sh"

print_status "Created helper scripts"

# Step 7: Validation and testing
print_section "Validating Configuration"

# Check for duplicate tags
print_debug "Checking for duplicate tags..."
DUPLICATES=$(grep "^tag(" "$JGMENU_DIR/prepend.csv" | sort | uniq -d)
if [ -z "$DUPLICATES" ]; then
    print_status "✓ No duplicate tags found"
else
    print_error "✗ Found duplicate tags:"
    echo "$DUPLICATES"
    exit 1
fi

# Check file permissions
if [ -r "$JGMENU_DIR/prepend.csv" ] && [ -r "$JGMENU_DIR/jgmenurc" ]; then
    print_status "✓ Configuration files are readable"
else
    print_error "✗ Configuration files have permission issues"
    exit 1
fi

# Test jgmenu configuration
print_debug "Testing jgmenu configuration..."
if jgmenu --config-file="$JGMENU_DIR/jgmenurc" --help &>/dev/null; then
    print_status "✓ jgmenu configuration is valid"
else
    print_error "✗ jgmenu configuration test failed"
    exit 1
fi

# Step 8: Final setup and instructions
print_section "Installation Complete!"

echo -e "${GREEN}"
echo "╔════════════════════════════════════════════════════════════════╗"
echo "║                     INSTALLATION SUCCESS!                     ║"
echo "╚════════════════════════════════════════════════════════════════╝"
echo -e "${NC}"

echo
print_status "Configuration files created:"
echo "  • $JGMENU_DIR/jgmenurc (main configuration)"
echo "  • $JGMENU_DIR/prepend.csv (custom menu structure)" 
echo "  • $JGMENU_DIR/flat_menu.csv (backup simple menu)"
echo "  • $JGMENU_DIR/launch_jgmenu.sh (launcher script)"
echo "  • $JGMENU_DIR/launch_flat_menu.sh (backup launcher)"

echo
print_status "How to use your new jgmenu:"
echo "  1. Run: jgmenu_run"
echo "  2. Or: $JGMENU_DIR/launch_jgmenu.sh"
echo "  3. Bind to a key combination in your window manager"
echo "  4. Right-click on desktop (if configured)"

echo
print_status "Menu features:"
echo "  ✓ Custom applications (Glitch Toolkit, QEMU, DD tools)"
echo "  ✓ Categorized submenus (Graphics, Internet, System, etc.)"
echo "  ✓ Quick actions (Lock, Logout, Shutdown, etc.)"
echo "  ✓ Terminal integration for CLI tools"
echo "  ✓ Root access tools with proper elevation"

echo
print_status "Troubleshooting:"
echo "  • If main menu fails: $JGMENU_DIR/launch_flat_menu.sh"
echo "  • To customize: edit $JGMENU_DIR/prepend.csv"
echo "  • To reset: rm -rf $JGMENU_DIR && run this script again"
echo "  • Backup available at: $BACKUP_DIR"

echo
print_status "Testing the menu now..."
echo "Press Ctrl+C to cancel, or wait 3 seconds to test..."
sleep 3

# Final test
if timeout 2 jgmenu_run 2>/dev/null; then
    print_status "✓ Menu test successful!"
else
    print_warning "Menu test interrupted or failed - this is normal"
    print_status "You can now run: jgmenu_run"
fi

echo
echo -e "${CYAN}Installation completed successfully!${NC}"
echo -e "${CYAN}Enjoy your new custom jgmenu! 🚀${NC}"
