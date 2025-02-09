#!/bin/bash

# Define the locale you want to set
TARGET_LANG="en_US.UTF-8"

echo "========================================="
echo "       Debian Locale Fixer Script       "
echo "========================================="

# Check current locale settings
echo -e "\n[INFO] Current locale settings:"
locale

# Ensure the necessary locale is available
echo -e "\n[INFO] Checking installed locales..."
if ! locale -a | grep -q "$TARGET_LANG"; then
    echo "[WARNING] $TARGET_LANG not found! Generating it now..."
    sudo locale-gen "$TARGET_LANG"
    echo "[INFO] Locale $TARGET_LANG generated."
else
    echo "[OK] $TARGET_LANG is already available."
fi

# Update system-wide locale settings
echo -e "\n[INFO] Updating system-wide locale settings..."
sudo update-locale LANG=$TARGET_LANG LC_ALL=$TARGET_LANG

# Apply changes immediately for the current session
export LANG=$TARGET_LANG
export LC_ALL=$TARGET_LANG

# Verify new locale settings
echo -e "\n[INFO] New locale settings:"
locale

sudo apt reinstall locales

# Suggest reboot if necessary
echo -e "\n[INFO] Locale configuration complete."
echo "A system reboot is recommended to apply changes globally."
read -p "Do you want to reboot now? (y/N): " REBOOT_CHOICE

if [[ "$REBOOT_CHOICE" =~ ^[Yy]$ ]]; then
    echo "[INFO] Rebooting now..."
    sudo reboot
else
    echo "[INFO] Please reboot manually when convenient."
fi
