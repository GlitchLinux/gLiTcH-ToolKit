#!/bin/bash

# Define the target file
LIGHTDM_CONF="/etc/lightdm/lightdm.conf"

# Define the username (replace 'x' with the actual username)
USERNAME="x"

# Backup the existing lightdm.conf file
sudo cp "$LIGHTDM_CONF" "$LIGHTDM_CONF.bak"

# Write the new configuration
sudo tee "$LIGHTDM_CONF" > /dev/null <<EOF
[SeatDefaults]
autologin-guest=false
autologin-user=$USERNAME
autologin-user-timeout=0
autologin-session=lightdm-autologin
autologin-session=xfce
EOF

# Restart LightDM to apply changes
sudo systemctl restart lightdm

echo "LightDM auto-login has been configured for user: $USERNAME"
