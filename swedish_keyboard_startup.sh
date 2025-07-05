#!/bin/bash

# Swedish Keyboard Layout Startup Script
# This script sets the keyboard layout to Swedish (SE) on system startup
# Compatible with Debian/Ubuntu-based distributions

# Script configuration
SCRIPT_NAME="Swedish Keyboard Setup"
LOG_FILE="/var/log/swedish-keyboard-setup.log"
LAYOUT="se"

# Function to log messages
log_message() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | sudo tee -a "$LOG_FILE"
}

# Function to set keyboard layout
set_keyboard_layout() {
    log_message "Setting keyboard layout to Swedish (SE)"
    
    # Wait for X11 to be available (important for startup scripts)
    timeout=30
    while [ $timeout -gt 0 ]; do
        if [ -n "$DISPLAY" ] && command -v setxkbmap >/dev/null 2>&1; then
            break
        fi
        sleep 1
        timeout=$((timeout - 1))
    done
    
    if [ $timeout -eq 0 ]; then
        log_message "ERROR: X11 not available or setxkbmap not found"
        return 1
    fi
    
    # Set the keyboard layout
    if setxkbmap "$LAYOUT"; then
        log_message "Successfully set keyboard layout to $LAYOUT"
        
        # Verify the layout was set
        current_layout=$(setxkbmap -query | grep layout | awk '{print $2}')
        log_message "Current keyboard layout: $current_layout"
        
        # Optional: Set additional keyboard options
        # Uncomment the following line if you want to set Caps Lock as an additional Ctrl key
        # setxkbmap -option ctrl:nocaps
        
        return 0
    else
        log_message "ERROR: Failed to set keyboard layout to $LAYOUT"
        return 1
    fi
}

# Function to install the startup script
install_startup_script() {
    local script_path="/usr/local/bin/swedish-keyboard-setup.sh"
    local service_path="/etc/systemd/system/swedish-keyboard.service"
    local autostart_path="$HOME/.config/autostart/swedish-keyboard.desktop"
    
    echo "Installing Swedish keyboard startup script..."
    
    # Copy this script to /usr/local/bin
    sudo cp "$0" "$script_path"
    sudo chmod +x "$script_path"
    
    # Create systemd service (for system-wide installation)
    sudo tee "$service_path" > /dev/null << 'EOF'
[Unit]
Description=Swedish Keyboard Layout Setup
After=graphical-session.target
Wants=graphical-session.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/swedish-keyboard-setup.sh
Environment=DISPLAY=:0
User=%i
RemainAfterExit=yes

[Install]
WantedBy=graphical-session.target
EOF
    
    # Create user autostart entry (alternative method)
    mkdir -p "$HOME/.config/autostart"
    tee "$autostart_path" > /dev/null << 'EOF'
[Desktop Entry]
Type=Application
Name=Swedish Keyboard Layout
Exec=/usr/local/bin/swedish-keyboard-setup.sh
Hidden=false
NoDisplay=false
X-GNOME-Autostart-enabled=true
Comment=Set keyboard layout to Swedish on startup
EOF
    
    # Enable the systemd service
    sudo systemctl enable swedish-keyboard.service
    
    echo "Installation complete!"
    echo "The script will run automatically on next login."
    echo "To run manually: /usr/local/bin/swedish-keyboard-setup.sh"
    echo "To check logs: sudo tail -f $LOG_FILE"
}

# Function to uninstall the startup script
uninstall_startup_script() {
    echo "Uninstalling Swedish keyboard startup script..."
    
    # Stop and disable systemd service
    sudo systemctl stop swedish-keyboard.service 2>/dev/null
    sudo systemctl disable swedish-keyboard.service 2>/dev/null
    
    # Remove files
    sudo rm -f /etc/systemd/system/swedish-keyboard.service
    sudo rm -f /usr/local/bin/swedish-keyboard-setup.sh
    rm -f "$HOME/.config/autostart/swedish-keyboard.desktop"
    
    # Reload systemd
    sudo systemctl daemon-reload
    
    echo "Uninstallation complete!"
}

# Main script logic
case "${1:-}" in
    "install")
        install_startup_script
        ;;
    "uninstall")
        uninstall_startup_script
        ;;
    "test")
        log_message "Testing keyboard layout setup"
        set_keyboard_layout
        ;;
    *)
        # Default action: set keyboard layout
        set_keyboard_layout
        ;;
esac