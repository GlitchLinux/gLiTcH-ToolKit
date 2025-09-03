#!/bin/bash

# Intel 8265 WiFi Firmware Fix Script
# Automatically downloads and installs missing iwlwifi-8265-36.ucode firmware

set -e  # Exit on any error

echo "Starting Intel 8265 WiFi firmware fix..." | borderize -0080FF -FFFFFF

# Check if running as root or with sudo
if [[ $EUID -ne 0 ]]; then
    echo "✗ This script must be run as root or with sudo" | borderize -FF0000 -FFFFFF
    echo "Usage: sudo $0"
    exit 1
fi

# Verify Intel 8265 WiFi card is present
echo "Checking for Intel 8265 WiFi hardware..." | borderize -FFD700 -FFFFFF
if ! lspci | grep -qi "Intel.*Wireless 8265"; then
    echo "⚠ Intel 8265 WiFi card not detected" | borderize -FFA500 -FFFF00
    echo "This script is specifically for Intel 8265 WiFi cards"
    exit 1
fi

echo "✓ Intel 8265 WiFi card detected" | borderize -00FF00 -FFFFFF

# Check current firmware status
echo "Checking current firmware status..." | borderize -FFD700 -FFFFFF
if [[ -f /lib/firmware/iwlwifi-8265-36.ucode ]]; then
    CURRENT_SIZE=$(stat -c%s /lib/firmware/iwlwifi-8265-36.ucode 2>/dev/null || echo "0")
    if [[ $CURRENT_SIZE -gt 1000000 ]]; then
        echo "✓ Valid firmware already exists (${CURRENT_SIZE} bytes)" | borderize -00FF00 -FFFFFF
        echo "Reloading WiFi module anyway..." | borderize -FFD700 -FFFFFF
        modprobe -r iwlwifi 2>/dev/null || true
        sleep 2
        modprobe iwlwifi
        echo "✓ WiFi module reloaded" | borderize -00FF00 -FFFFFF
        exit 0
    else
        echo "⚠ Firmware file exists but is corrupted (${CURRENT_SIZE} bytes)" | borderize -FFA500 -FFFF00
        rm -f /lib/firmware/iwlwifi-8265-36.ucode
    fi
else
    echo "✗ Firmware file missing" | borderize -FF0000 -FFFFFF
fi

# Download firmware file
TEMP_FILE="/tmp/iwlwifi-8265-36.ucode.$$"
FIRMWARE_URL="https://github.com/wkennington/linux-firmware/raw/refs/heads/master/iwlwifi-8265-36.ucode"

echo "Downloading firmware from GitHub mirror..." | borderize -0080FF -FFFFFF
if wget -q --show-progress "$FIRMWARE_URL" -O "$TEMP_FILE"; then
    echo "✓ Download completed" | borderize -00FF00 -FFFFFF
else
    echo "✗ Download failed" | borderize -FF0000 -FFFFFF
    rm -f "$TEMP_FILE"
    exit 1
fi

# Verify download
DOWNLOADED_SIZE=$(stat -c%s "$TEMP_FILE" 2>/dev/null || echo "0")
if [[ $DOWNLOADED_SIZE -lt 1000000 ]]; then
    echo "✗ Downloaded file appears corrupted (${DOWNLOADED_SIZE} bytes)" | borderize -FF0000 -FFFFFF
    rm -f "$TEMP_FILE"
    exit 1
fi

echo "✓ Downloaded valid firmware file (${DOWNLOADED_SIZE} bytes)" | borderize -00FF00 -FFFFFF

# Install firmware
echo "Installing firmware to /lib/firmware/..." | borderize -0080FF -FFFFFF
cp "$TEMP_FILE" /lib/firmware/iwlwifi-8265-36.ucode
chown root:root /lib/firmware/iwlwifi-8265-36.ucode
chmod 644 /lib/firmware/iwlwifi-8265-36.ucode

echo "✓ Firmware installed successfully" | borderize -00FF00 -FFFFFF

# Clean up temp file
rm -f "$TEMP_FILE"

# Reload WiFi module
echo "Reloading WiFi module..." | borderize -0080FF -FFFFFF

# Unload module if loaded
if lsmod | grep -q iwlwifi; then
    modprobe -r iwlwifi
    echo "✓ Unloaded iwlwifi module" | borderize -00FF00 -FFFFFF
    sleep 2
fi

# Load module
modprobe iwlwifi
echo "✓ Loaded iwlwifi module" | borderize -00FF00 -FFFFFF

# Wait for initialization
echo "Waiting for firmware initialization..." | borderize -FFD700 -FFFFFF
sleep 3

# Check firmware loading status
echo "Verifying firmware load..." | borderize -0080FF -FFFFFF
if dmesg | tail -10 | grep -q "iwlwifi.*loaded firmware version"; then
    FIRMWARE_VERSION=$(dmesg | tail -10 | grep "iwlwifi.*loaded firmware version" | tail -1 | sed 's/.*version: //' | cut -d' ' -f1)
    echo "✓ SUCCESS: WiFi firmware loaded!" | borderize -00FF00 -FFFFFF
    echo "✓ Firmware version: $FIRMWARE_VERSION" | borderize -00FF00 -FFFFFF
else
    echo "⚠ Firmware status unclear - check dmesg output" | borderize -FFA500 -FFFF00
fi

# Check for WiFi interface
echo "Checking for WiFi interface..." | borderize -FFD700 -FFFFFF
sleep 2
if ip link show | grep -q wlan; then
    WIFI_INTERFACE=$(ip link show | grep wlan | head -1 | cut -d':' -f2 | tr -d ' ')
    echo "✓ WiFi interface detected: $WIFI_INTERFACE" | borderize -00FF00 -FFFFFF
else
    echo "⚠ WiFi interface not yet visible - may need NetworkManager restart" | borderize -FFA500 -FFFF00
fi

echo "Intel 8265 WiFi firmware fix completed!" | borderize -00FF00 -FFFFFF
echo "If WiFi still doesn't work, try: sudo systemctl restart NetworkManager" | borderize -FFD700 -FFFFFF