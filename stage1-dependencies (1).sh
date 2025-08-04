#!/bin/bash

# AutoFS Stage 1: Simple Transparent Installation
# Your exact commands with full visible output - no hiding anything

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
echo "Step 4: Force install all .deb packages (first pass)"
echo "----------------------------------------------------"
sudo dpkg --force-all -i *.deb

echo
echo "Step 5: Fix dependencies"
echo "------------------------"
sudo apt install -f -y

echo
echo "Step 6: Install packages again (second pass)"
echo "---------------------------------------------"
sudo dpkg -i *.deb

echo
echo "Step 7: Update and upgrade system"
echo "---------------------------------"
sudo apt update && sudo apt upgrade -y

echo
echo "Step 8: Check kernel and boot files"
echo "-----------------------------------"
echo "Boot directory contents:"
sudo ls -l /boot/ | grep -E "(vmlinuz|initrd)" || echo "No vmlinuz/initrd files found"

# Check for kernel files
VMLINUZ_COUNT=$(ls /boot/vmlinuz* 2>/dev/null | wc -l)
INITRD_COUNT=$(ls /boot/initrd* 2>/dev/null | wc -l)

echo "Found $VMLINUZ_COUNT vmlinuz files"
echo "Found $INITRD_COUNT initrd files"

if [[ $VMLINUZ_COUNT -eq 0 ]] || [[ $INITRD_COUNT -eq 0 ]]; then
    echo "WARNING: Missing kernel files - attempting reinstall"
    echo "Installing kernel packages..."
    sudo apt install -y linux-image-amd64 linux-headers-amd64
    echo "Updating GRUB..."
    sudo update-grub
else
    echo "Kernel files OK - configuring packages and updating GRUB"
    sudo dpkg --configure -a
    sudo update-grub
fi

echo
echo "Step 9: Verify critical packages"
echo "--------------------------------"
echo "Checking critical packages:"

for pkg in nginx python3 iptables dnsmasq bridge-utils ntfs-3g; do
    if dpkg -l "$pkg" 2>/dev/null | grep -q "^ii" || command -v "$pkg" >/dev/null 2>&1; then
        echo "✓ $pkg - OK"
    else
        echo "✗ $pkg - Missing"
    fi
done

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
