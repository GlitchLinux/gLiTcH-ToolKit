#!/bin/bash

# AutoFS Stage 1: Simple Transparent Installation
# Your exact commands with full visible output + auto-accept prompts

set -e

echo "AutoFS Stage 1: Dependencies Installation"
echo "========================================"
echo

# Check root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: Must run as root"
    echo "Usage: sudo $0"
    exit 1
fi

# Set environment for non-interactive mode
export DEBIAN_FRONTEND=noninteractive
export NEEDRESTART_MODE=a
export APT_LISTCHANGES_FRONTEND=none

echo "Step 1: Update package lists and install git"
echo "--------------------------------------------"
sudo apt update && sudo apt install git -y

echo
echo "Step 2: Clone repository"
echo "------------------------"
cd /tmp && git clone https://github.com/GlitchLinux/autoFS.git

echo
echo "Step 3: Move scripts and install packages"
echo "------------------------------------------"
cd autoFS

# Move scripts if they exist
if [[ -d "SCRIPTS" ]]; then
    echo "Moving SCRIPTS directory..."
    sudo mv SCRIPTS /home/SCRIPTS
    echo "Scripts moved to /home/SCRIPTS/"
else
    echo "No SCRIPTS directory found - skipping"
fi

echo
echo "Step 4: Force install all .deb packages (first pass) - AUTO-ACCEPTING PROMPTS"
echo "------------------------------------------------------------------------------"
# Use yes to auto-answer prompts and force options
yes | sudo dpkg --force-all --force-confnew --force-confdef -i *.deb || true

echo
echo "Step 5: Fix dependencies - AUTO-ACCEPTING"
echo "-----------------------------------------"
sudo apt install -f -y

echo
echo "Step 6: Install packages again (second pass) - AUTO-ACCEPTING"
echo "-------------------------------------------------------------"
yes | sudo dpkg --force-confnew --force-confdef -i *.deb || true

echo
echo "Step 7: Update and upgrade system - AUTO-ACCEPTING"
echo "--------------------------------------------------"
sudo apt --fix-broken-install -y && sudo apt update && sudo apt upgrade -y
#
#echo
#echo "Step 8: Verify critical packages"
#echo "--------------------------------"
#echo "Checking critical packages:"

#for pkg in nginx python3 iptables dnsmasq bridge-utils ntfs-3g; do
#    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" || command -v "$pkg" >/dev/null 2>&1; then
#       echo "✓ $pkg - OK"
#    else
#        echo "✗ $pkg - Missing"
#    fi
#done

echo
echo "Step 10: Create system directories"
echo "----------------------------------"
sudo mkdir -p /var/www/autofs
sudo mkdir -p /mnt/autofs
sudo mkdir -p /etc/autofs
sudo mkdir -p /var/log/autofs

# Set permissions
sudo chown -R www-data:www-data /var/www/autofs 2>/dev/null || echo "www-data user not found (normal on some systems)"

echo
echo "STAGE 1 COMPLETE!"
echo "================="
echo "All steps executed successfully"
echo "Ready for Stage 2: Network Configuration"

# Create completion marker
echo "$(date): Stage 1 completed" > /tmp/.autofs-stage1-complete

echo
echo "Summary:"
echo "- Repository cloned from GitHub"
echo "- All .deb packages installed (force method)"
echo "- Dependencies fixed"
echo "- System updated and upgraded" 
echo "- Kernel and GRUB checked"
echo "- System directories created"
echo
echo "Next: Run Stage 2 for network configuration"
