#!/bin/bash

# Debian Bullseye to Bookworm Upgrade Recovery Script
# Specifically handles usrmerge issues during major version upgrades

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_color() {
    local color=$1
    local message=$2
    echo -e "${color}${message}${NC}"
}

print_color $BLUE "=== DEBIAN BULLSEYE → BOOKWORM UPGRADE RECOVERY ==="
print_color $YELLOW "This addresses known usrmerge issues during Debian major upgrades"

# Step 1: Emergency filesystem remount
print_color $YELLOW "Step 1: Attempting emergency filesystem remount..."

if sudo mount -o remount,rw / 2>/dev/null; then
    print_color $GREEN "✓ Filesystem remounted as read-write"
    
    # Test write capability
    if touch /tmp/upgrade_recovery_test 2>/dev/null; then
        rm -f /tmp/upgrade_recovery_test
        print_color $GREEN "✓ Write access confirmed"
        WRITABLE=true
    else
        print_color $RED "✗ Still read-only despite remount"
        WRITABLE=false
    fi
else
    print_color $RED "✗ Cannot remount filesystem"
    WRITABLE=false
fi

# Step 2: Handle the broken upgrade state
if [[ "$WRITABLE" == "true" ]]; then
    print_color $YELLOW "Step 2: Fixing broken Debian upgrade state..."
    
    # Remove the problematic usrmerge package
    print_color $BLUE "Removing broken usrmerge package..."
    sudo dpkg --remove --force-remove-reinstreq usrmerge 2>/dev/null || true
    sudo dpkg --purge --force-all usrmerge 2>/dev/null || true
    
    # Clean dpkg lock files if they exist
    sudo rm -f /var/lib/dpkg/lock*
    sudo rm -f /var/cache/apt/archives/lock
    
    # Restore essential binaries from backups
    print_color $BLUE "Restoring essential system binaries..."
    for backup in /bin/*.usrmerge.backup /sbin/*.usrmerge.backup; do
        if [[ -f "$backup" ]]; then
            original="${backup%.usrmerge.backup}"
            target="/usr${original}"
            
            # Ensure target directory exists
            sudo mkdir -p "$(dirname "$target")"
            
            # Copy backup to /usr location
            sudo cp "$backup" "$target" 2>/dev/null || true
            sudo chmod +x "$target" 2>/dev/null || true
            
            print_color $GREEN "Restored $(basename "$original")"
        fi
    done
    
    # Create proper symlinks for merged directories
    print_color $BLUE "Creating proper directory structure..."
    
    # Handle /bin → /usr/bin
    if [[ -d "/bin" && ! -L "/bin" ]]; then
        # Move any remaining files to /usr/bin
        sudo find /bin -maxdepth 1 -type f -exec mv {} /usr/bin/ \; 2>/dev/null || true
        # Remove the directory and create symlink
        sudo rmdir /bin 2>/dev/null || sudo rm -rf /bin
        sudo ln -sf usr/bin /bin
        print_color $GREEN "✓ Fixed /bin → /usr/bin"
    fi
    
    # Handle /sbin → /usr/sbin
    if [[ -d "/sbin" && ! -L "/sbin" ]]; then
        # Move any remaining files to /usr/sbin
        sudo find /sbin -maxdepth 1 -type f -exec mv {} /usr/sbin/ \; 2>/dev/null || true
        # Remove the directory and create symlink
        sudo rmdir /sbin 2>/dev/null || sudo rm -rf /sbin
        sudo ln -sf usr/sbin /sbin
        print_color $GREEN "✓ Fixed /sbin → /usr/sbin"
    fi
    
    # Step 3: Fix broken package state
    print_color $YELLOW "Step 3: Fixing broken package states..."
    
    # Configure pending packages
    sudo dpkg --configure -a 2>/dev/null || true
    
    # Fix broken dependencies
    sudo apt --fix-broken install -y 2>/dev/null || true
    
    # Step 4: Complete the Debian upgrade properly
    print_color $YELLOW "Step 4: Completing Debian Bookworm upgrade..."
    
    # Update sources.list for Bookworm if still pointing to Bullseye
    if grep -q "bullseye" /etc/apt/sources.list 2>/dev/null; then
        print_color $BLUE "Updating sources.list to Bookworm..."
        sudo sed -i 's/bullseye/bookworm/g' /etc/apt/sources.list
        
        # Also update sources.list.d files
        sudo find /etc/apt/sources.list.d/ -name "*.list" -exec sed -i 's/bullseye/bookworm/g' {} \; 2>/dev/null || true
    fi
    
    # Update package lists
    sudo apt update 2>/dev/null || print_color $YELLOW "APT update had warnings (this is normal during recovery)"
    
    # Complete the upgrade
    print_color $BLUE "Completing distribution upgrade..."
    sudo apt full-upgrade -y 2>/dev/null || print_color $YELLOW "Some packages may need manual attention"
    
    # Clean up
    sudo apt autoremove -y 2>/dev/null || true
    sudo apt autoclean 2>/dev/null || true
    
    # Step 5: Verify system state
    print_color $YELLOW "Step 5: Verifying system state..."
    
    # Check if essential commands work
    essential_commands=("cp" "mv" "rm" "ls" "cat" "grep")
    all_working=true
    
    for cmd in "${essential_commands[@]}"; do
        if command -v "$cmd" >/dev/null 2>&1; then
            print_color $GREEN "✓ $cmd is available"
        else
            print_color $RED "✗ $cmd is missing"
            all_working=false
        fi
    done
    
    # Check directory structure
    if [[ -L "/bin" && -L "/sbin" ]]; then
        print_color $GREEN "✓ Directory structure properly merged"
    else
        print_color $YELLOW "! Directory structure may need attention"
    fi
    
    # Check Debian version
    if [[ -f "/etc/debian_version" ]]; then
        version=$(cat /etc/debian_version)
        print_color $BLUE "Current Debian version: $version"
    fi
    
    # Remove backup files if system is working
    if [[ "$all_working" == "true" ]]; then
        print_color $BLUE "Cleaning up backup files..."
        sudo rm -f /bin/*.usrmerge.backup /sbin/*.usrmerge.backup 2>/dev/null || true
    fi
    
    print_color $GREEN "=== UPGRADE RECOVERY COMPLETE ==="
    print_color $BLUE "Your Debian Bullseye → Bookworm upgrade should now be fixed"
    
else
    # Filesystem is still read-only - provide recovery instructions
    print_color $RED "=== FILESYSTEM REPAIR REQUIRED ==="
    print_color $YELLOW "The filesystem is corrupted and requires offline repair"
    
    echo
    print_color $BLUE "RECOVERY INSTRUCTIONS:"
    echo "1. Reboot the system:"
    echo "   sudo reboot"
    echo
    echo "2. Boot from Sparky Bonsai live USB/CD or Debian rescue mode"
    echo
    echo "3. Mount your system and repair filesystem:"
    echo "   sudo mkdir /mnt/system"
    echo "   sudo mount /dev/sdaX /mnt/system  # Replace X with your disk"
    echo "   sudo fsck -f -y /dev/sdaX"
    echo
    echo "4. Chroot into your system:"
    echo "   sudo mount --bind /proc /mnt/system/proc"
    echo "   sudo mount --bind /sys /mnt/system/sys"
    echo "   sudo mount --bind /dev /mnt/system/dev"
    echo "   sudo chroot /mnt/system"
    echo
    echo "5. Run this recovery script again from chroot environment"
    echo
    echo "6. Complete the upgrade:"
    echo "   dpkg --remove --force-remove-reinstreq usrmerge"
    echo "   apt update && apt full-upgrade -y"
    echo
    echo "7. Exit chroot and reboot:"
    echo "   exit"
    echo "   sudo umount /mnt/system/proc /mnt/system/sys /mnt/system/dev"
    echo "   sudo umount /mnt/system"
    echo "   sudo reboot"
fi

print_color $BLUE "=== ADDITIONAL INFORMATION ==="
echo "This issue is common when upgrading from:"
echo "• Debian 11 (Bullseye) → Debian 12 (Bookworm)"
echo "• Any Debian-based distro during this transition"
echo "• The usrmerge requirement is mandatory in Bookworm"
echo
echo "Prevention for future upgrades:"
echo "• Always backup before major version upgrades"
echo "• Use 'apt full-upgrade' instead of 'apt upgrade' for major versions"
echo "• Consider fresh installation for major version jumps"
echo
print_color $YELLOW "If problems persist after recovery:"
echo "• Consider backing up data and fresh installing Sparky Bonsai"
echo "• The Bookworm-based version will be more stable"
echo "• This avoids upgrade-related issues entirely"