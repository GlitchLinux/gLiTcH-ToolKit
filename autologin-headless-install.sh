#!/bin/bash

# Automatically get the current user (who invoked sudo or the script)
CURRENT_USER=$(logname)

# Check if the user exists (just to be safe)
if ! id "$CURRENT_USER" &>/dev/null; then
    echo "Error: Current user '$CURRENT_USER' does not exist or cannot be determined!"
    exit 1
fi

# Create systemd override for getty@tty1 to enable autologin
echo "Configuring autologin for $CURRENT_USER..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/

cat <<EOF | sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $CURRENT_USER --noclear %I \$TERM
EOF

# Reload systemd and restart getty service
sudo systemctl daemon-reload
sudo systemctl restart getty@tty1

# Success message
sleep 3
echo "Autologin configured successfully for $CURRENT_USER"
echo "$CURRENT_USER will be logged in automatically on next reboot."
