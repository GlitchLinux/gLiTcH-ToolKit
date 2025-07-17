#!/bin/bash

# jgmenu CSV Menu Installation Script
# For Debian/Ubuntu based systems

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if jgmenu is installed
if ! command -v jgmenu &> /dev/null; then
    print_error "jgmenu is not installed. Please install it first:"
    echo "sudo apt update && sudo apt install jgmenu"
    exit 1
fi

# Create jgmenu config directory if it doesn't exist
JGMENU_DIR="$HOME/.config/jgmenu"
mkdir -p "$JGMENU_DIR"

# Backup existing prepend file if it exists
if [ -f "$JGMENU_DIR/prepend.csv" ]; then
    print_warning "Backing up existing prepend.csv to prepend.csv.backup"
    cp "$JGMENU_DIR/prepend.csv" "$JGMENU_DIR/prepend.csv.backup"
fi

# Create the prepend.csv file
print_status "Creating jgmenu prepend.csv file..."

cat > "$JGMENU_DIR/prepend.csv" << 'EOF'
# Custom Debian Linux jgmenu CSV Configuration
# Simplified structure with subcategories

# Main Applications Menu - opens all apps submenu
Applications,^tag(applications),applications-other

# Main Categories with submenus
Accessories,^tag(accessories),applications-accessories
Graphics,^tag(graphics),applications-graphics
Internet,^tag(internet),applications-internet
Multimedia,^tag(multimedia),applications-multimedia
Office,^tag(office),applications-office
System,^tag(system),applications-system
Development,^tag(development),applications-development
Administration,^tag(administration),applications-system
Utilities,^tag(utilities),applications-utilities
Quick Actions,^tag(quickactions),applications-accessories

^sep()

# Applications submenu tag
^tag(applications)
Text Editor,l3afpad,accessories-text-editor
Archive Manager,peazip,package-x-generic
File Manager,thunar,folder-manager
File Manager (Root),thunar-root,folder-manager
Clipboard Manager,clipper,edit-paste
Screenshot Tool,flameshot,applets-screenshooter
Task Manager,btop,utilities-system-monitor
^sep()
# Custom Entries
Glitch Toolkit,glitch-toolkit,applications-development
QEMU QuickBoot,QEMU-QuickBoot,computer
Terminal,xfce4-terminal,utilities-terminal
Terminal (Root),^pipe(pkexec xfce4-terminal),utilities-terminal
DD CLI,dd-cli,drive-harddisk
DD GUI,dd_gui,drive-harddisk
^sep()
Back,^back(),go-previous

# Accessories submenu
^tag(accessories)
Text Editor,l3afpad,accessories-text-editor
Archive Manager,peazip,package-x-generic
File Manager,thunar,folder-manager
File Manager (Root),thunar-root,folder-manager
Clipboard Manager,clipper,edit-paste
Screenshot Tool,flameshot,applets-screenshooter
Task Manager,btop,utilities-system-monitor
^sep()
Back,^back(),go-previous

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
Network Tools,^pipe(xfce4-terminal -e 'bash -c "echo Available tools: ping wget curl netstat; bash"'),network-wired
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

# Office submenu
^tag(office)
Calculator (Advanced),^pipe(xfce4-terminal -e qalc),accessories-calculator
Calculator (GUI),galculator,accessories-calculator
^sep()
Back,^back(),go-previous

# System submenu
^tag(system)
Disk Utility,gnome-disks,drive-harddisk
Disk Utility (GParted),gparted,drive-harddisk
System Information,^pipe(xfce4-terminal -e fastfetch),computer
Hardware Sensors,xfce4-sensors,hardware-info
System Backup,systemback-installer,document-save
Power Management,power-menu,system-shutdown
Session Manager,lxsession,preferences-system
Appearance Settings,lxappearance,preferences-desktop-theme
Display Settings,arandr,preferences-desktop-display
^sep()
Back,^back(),go-previous

# Development submenu
^tag(development)
Glitch Toolkit,glitch-toolkit,applications-development
Git,^pipe(xfce4-terminal -e 'bash -c "echo Git commands available. Type git --help; bash"'),git
Python,^pipe(xfce4-terminal -e python3.11),text-x-python
Perl,^pipe(xfce4-terminal -e perl),text-x-perl
Text Editor (Advanced),^pipe(xfce4-terminal -e nano),accessories-text-editor
Make,^pipe(xfce4-terminal -e 'bash -c "echo Make utility. Use: make [target]; bash"'),applications-development
^sep()
Back,^back(),go-previous

# Administration submenu
^tag(administration)
Package Manager,synaptic,system-software-install
App Center,sparky-aptus-appcenter,system-software-install
System Settings,^pipe(xfce4-terminal -e 'bash -c "echo systemctl commands available; bash"'),preferences-system
User Accounts,^pipe(xfce4-terminal -e 'bash -c "echo User management: passwd, usermod, etc.; bash"'),system-users
System Logs,^pipe(xfce4-terminal -e journalctl),text-x-generic
^sep()
Back,^back(),go-previous

# Utilities submenu
^tag(utilities)
System Cleaner,bleachbit,system-cleaner
System Cleaner (Root),pkexec bleachbit,system-cleaner
Application Launcher,ulauncher,applications-accessories
Menu System,jgmenu,applications-accessories
Panel,vala-panel,panel
Volume Icon,volumeicon,audio-volume-high
Battery Monitor,cbatticon,battery
Terminal File Manager,^pipe(xfce4-terminal -e mc),folder-manager
Tree View,^pipe(xfce4-terminal -e 'bash -c "echo Usage: tree [directory]; bash"'),folder-manager
Process Viewer,^pipe(xfce4-terminal -e btop),utilities-system-monitor
^sep()
Back,^back(),go-previous

# Quick Actions submenu
^tag(quickactions)
Lock Screen,light-locker-command -l,system-lock-screen
Logout,lxsession-logout,system-log-out
Shutdown,systemctl poweroff,system-shutdown
Reboot,systemctl reboot,system-reboot
Suspend,systemctl suspend,system-suspend
^sep()
# Custom Quick Actions
Terminal,xfce4-terminal,utilities-terminal
Terminal (Root),pkexec xfce4-terminal,utilities-terminal
DD CLI,dd-cli,drive-harddisk
DD GUI,dd_gui,drive-harddisk
QEMU QuickBoot,QEMU-QuickBoot,computer
^sep()
Back,^back(),go-previous
EOF

print_status "prepend.csv file created successfully!"

# Check if jgmenu config file exists, if not create a basic one
if [ ! -f "$JGMENU_DIR/jgmenurc" ]; then
    print_status "Creating basic jgmenurc configuration..."
    cat > "$JGMENU_DIR/jgmenurc" << 'EOF'
# jgmenu configuration file

# Position and size
position_mode = pointer
menu_width = 300
menu_height_min = 0
menu_height_max = 600

# Appearance
font = DejaVu Sans 9
icon_size = 16
icon_theme = Adwaita

# Colors (dark theme)
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
csv_cmd = pmenu
EOF
    print_status "Basic jgmenurc created!"
fi

# Test the configuration
print_status "Testing jgmenu configuration..."
if jgmenu --config-file="$JGMENU_DIR/jgmenurc" --csv-file="$JGMENU_DIR/prepend.csv" --help &> /dev/null; then
    print_status "Configuration test passed!"
else
    print_warning "Configuration test failed, but files were created."
fi

# Instructions
print_status "Installation complete!"
echo
echo "To use your new jgmenu:"
echo "1. Run: jgmenu_run"
echo "2. Or bind it to a key combination in your window manager"
echo "3. Right-click on desktop (if configured)"
echo
echo "Configuration files created:"
echo "- $JGMENU_DIR/prepend.csv"
echo "- $JGMENU_DIR/jgmenurc"
echo
echo "To customize further, edit these files or run: jgmenu init"
echo
print_status "Enjoy your new organized menu!"
EOF