#!/bin/bash

# Prompt user to enter the username for autologin
read -p "Enter the username for autologin: " SELECTED_USER

# Check if the user exists
if ! id "$SELECTED_USER" &>/dev/null; then
    echo "Error: User '$SELECTED_USER' does not exist!"
    exit 1
fi

# Create systemd override for getty@tty1 to enable autologin
echo "Configuring autologin for $SELECTED_USER..."
sudo mkdir -p /etc/systemd/system/getty@tty1.service.d/

cat <<EOF | sudo tee /etc/systemd/system/getty@tty1.service.d/override.conf > /dev/null
[Service]
ExecStart=
ExecStart=-/sbin/agetty --autologin $SELECTED_USER --noclear %I \$TERM
EOF

# Reload systemd and restart getty service
sudo systemctl daemon-reload
sudo systemctl restart getty@tty1

# Success message
sleep 3
echo "Autologin configured successfully for $SELECTED_USER"
echo "$SELECTED_USER will be logged in automatically on next reboot."
