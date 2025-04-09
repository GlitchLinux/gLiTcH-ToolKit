#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Error: This script must be run as root." >&2
    exit 1
fi

# Ask for the username
read -p "Enter the username for auto-login: " USER

# Verify the user exists
if ! id "$USER" &>/dev/null; then
    echo "Error: User '$USER' does not exist." >&2
    exit 1
fi

# Create the systemd override directory
mkdir -p /etc/systemd/system/getty@tty1.service.d/

# Configure auto-login
cat > /etc/systemd/system/getty@tty1.service.d/autologin.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $USER --noclear %I \$TERM
EOF

# Reload systemd to apply changes
systemctl daemon-reload

echo "Auto-login for user '$USER' has been enabled on tty1."
echo "Changes will take effect after reboot or service restart."
