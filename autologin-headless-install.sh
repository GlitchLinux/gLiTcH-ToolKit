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

# Get username for autologin
read -p "Enter username for autologin (NOT root unless absolutely necessary): " TARGET_USER

# Verify user exists
if ! id -u "$TARGET_USER" >/dev/null 2>&1; then
    echo "Error: User '$TARGET_USER' does not exist!" >&2
    exit 1
fi

# Security warning for root
if [ "$TARGET_USER" = "root" ]; then
    read -p "WARNING: Configuring autologin as root is a security risk! Continue? (y/N) " -r
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "Aborted by user."
        exit 1
    fi
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

echo ""
echo "Autologin configuration complete for:"
echo "- Regular console (tty1)"
echo "- Serial console (ttyS0 @ 115200 baud)"
echo ""
echo "================================================"
echo "Security Note:"
echo "Autologin should ONLY be used on secured systems!"
echo "Configure a password for $TARGET_USER if not set:"
echo "  passwd $TARGET_USER"
echo "================================================"
echo ""
echo "Reboot the system to apply changes:"
echo "  systemctl reboot"
