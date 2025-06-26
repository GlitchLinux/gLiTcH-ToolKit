#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Check if system is using systemd
if ! command -v systemctl >/dev/null 2>&1; then
    echo "This script requires systemd" >&2
    exit 1
fi

# Get the default target user (usually the first user created)
TARGET_USER=$(ls /home | head -n 1)

if [ -z "$TARGET_USER" ]; then
    echo "No user found in /home directory" >&2
    exit 1
fi

echo "Configuring autologin for user: $TARGET_USER"

# Configure getty automatic login for tty1 (regular console)
mkdir -p /etc/systemd/system/getty@tty1.service.d

cat > /etc/systemd/system/getty@tty1.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --noclear %I \$TERM
EOF

# Configure getty automatic login for ttyS0 (serial console)
mkdir -p /etc/systemd/system/serial-getty@ttyS0.service.d

cat > /etc/systemd/system/serial-getty@ttyS0.service.d/override.conf <<EOF
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $TARGET_USER --keep-baud 115200,38400,9600 %I \$TERM
EOF

# Enable serial console if not already enabled
if ! grep -q "console=ttyS0" /etc/default/grub; then
    echo "Adding serial console to GRUB configuration..."
    sed -i 's/GRUB_CMDLINE_LINUX="\(.*\)"/GRUB_CMDLINE_LINUX="\1 console=ttyS0,115200"/' /etc/default/grub
    update-grub
fi

# Reload systemd to apply changes
systemctl daemon-reload

echo "Autologin configuration complete for:"
echo "- Regular console (tty1)"
echo "- Serial console (ttyS0 @ 115200 baud)"
echo ""
echo "The system will need to be rebooted for changes to take effect."
echo "After reboot, you should be able to login via:"
echo "1. Direct console access (autologin to $TARGET_USER)"
echo "2. Serial connection (autologin to $TARGET_USER at 115200 baud)"
