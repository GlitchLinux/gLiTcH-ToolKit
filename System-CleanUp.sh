#!/bin/bash

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

echo "1. Remove Unnecessary Packages:"
sudo apt autoremove -y

echo "2. Clean Package Cache:"
sudo apt clean -y
sudo apt autoclean -y

echo "3. Remove Old Kernels:"
echo "List installed kernels:"
dpkg --list | grep linux-image
echo "Removing older kernels (specify OLD-KERNEL version):"
# Uncomment the next line and replace OLD-KERNEL with the version number of the kernel you want to remove
# sudo apt remove linux-image-OLD-KERNEL -y
sudo update-grub

echo "4. Clean Log Files:"
sudo logrotate -f /etc/logrotate.conf

echo "5. Delete Temporary Files:"
rm -rf ~/.cache

echo "6. Empty Trash:"
rm -rf ~/.local/share/Trash/*

echo "7. Remove Old Configuration Files:"
sudo apt install deborphan -y
sudo deborphan --guess-all | xargs sudo apt-get -y remove --purge

echo "8. Remove Orphaned Packages:"
# Uncomment the next line to remove orphaned packages
# sudo apt-get remove --purge $(deborphan)

echo "Cleanup completed."
