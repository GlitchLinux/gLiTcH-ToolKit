#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Verify GRUB installation
if ! command -v grub-mkconfig &> /dev/null; then
    echo "GRUB is not installed. Please install it first." >&2
    exit 1
fi

# Set file locations
GRUB_CONFIG_SRC="https://raw.githubusercontent.com/GlitchLinux/Grub-Custom-Files/main/grub.d/10_linux"
GRUB_CONFIG_DEST="/etc/grub.d/10_linux"
GRUB_BACKGROUND="/boot/grub/splash.png"
GRUB_DEFAULT_CONFIG="/etc/default/grub"

# Install wget if missing
if ! command -v wget &> /dev/null; then
    apt-get update && apt-get install -y wget
fi

# Completely remove old config
echo "Removing old GRUB configuration..."
rm -f "$GRUB_CONFIG_DEST"

# Download new config
echo "Downloading new GRUB configuration..."
wget -q "$GRUB_CONFIG_SRC" -O "$GRUB_CONFIG_DEST" || {
    echo "Failed to download GRUB configuration" >&2
    exit 1
}

# Set permissions
chmod 755 "$GRUB_CONFIG_DEST"

# Download and set background
echo "Setting GRUB background..."
wget -q "https://raw.githubusercontent.com/GlitchLinux/Grub-Custom-Files/main/grub.d/splash.png" -O "$GRUB_BACKGROUND" || {
    echo "Failed to download background image" >&2
}

# Force GRUB to use the background
sed -i '/GRUB_BACKGROUND/d' "$GRUB_DEFAULT_CONFIG"
echo "GRUB_BACKGROUND=\"$GRUB_BACKGROUND\"" >> "$GRUB_DEFAULT_CONFIG"

# Disable os-prober to prevent duplicates
sed -i '/GRUB_DISABLE_OS_PROBER/d' "$GRUB_DEFAULT_CONFIG"
echo "GRUB_DISABLE_OS_PROBER=true" >> "$GRUB_DEFAULT_CONFIG"

# Update GRUB
echo "Generating new GRUB configuration..."
grub-mkconfig -o /boot/grub/grub.cfg || {
    echo "Failed to update GRUB configuration" >&2
    exit 1
}

#update-grub
update-grub

echo "GRUB configuration successfully replaced!"
echo "New configuration: $GRUB_CONFIG_DEST"
echo "Background image: $GRUB_BACKGROUND"
echo "You should reboot to see all changes."
