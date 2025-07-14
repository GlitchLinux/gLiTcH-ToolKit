#!/bin/bash

# Complete GRUB Fallback Boot Setup Script
# This script provides a permanent solution for GRUB to always use /efi/boot/bootx64.efi
# Perfect for systems that will be used to create ISOs

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

print_header() {
    echo -e "${CYAN}========================================${NC}"
    echo -e "${CYAN} $1 ${NC}"
    echo -e "${CYAN}========================================${NC}"
}

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    print_error "This script must be run as root (use sudo)"
    exit 1
fi

print_header "GRUB Fallback Boot Complete Setup"

# Check if we're on a UEFI system
if [[ ! -d "/sys/firmware/efi" ]]; then
    print_error "This system is not booted in UEFI mode"
    exit 1
fi

# Find the EFI system partition mount point
EFI_MOUNT=$(findmnt -n -o TARGET -t vfat | head -1)
if [[ -z "$EFI_MOUNT" ]]; then
    print_error "Could not find EFI system partition"
    print_error "Make sure your EFI system partition is mounted (usually at /boot/efi)"
    exit 1
fi

print_status "Found EFI system partition mounted at: $EFI_MOUNT"

# ============================================================================
# STEP 1: Create GRUB Install Wrapper
# ============================================================================
print_step "1. Creating GRUB Install Wrapper"

# Backup original grub-install if not already done
if [[ ! -f "/usr/sbin/grub-install.original" ]]; then
    cp /usr/sbin/grub-install /usr/sbin/grub-install.original
    print_status "Original grub-install backed up to /usr/sbin/grub-install.original"
fi

# Create the wrapper script
cat > /usr/sbin/grub-install << 'EOF'
#!/bin/bash
# GRUB Install Wrapper - Forces --removable option for EFI installations
# This ensures BOOTX64.EFI is created instead of distribution-specific files
# Created by GRUB Fallback Setup Script

# Function to log wrapper activity
log_wrapper() {
    echo "GRUB Wrapper: $1" >&2
}

# Check if this is an EFI installation
if [[ "$*" == *"--target=x86_64-efi"* ]] || [[ "$*" == *"efi"* ]] && [[ "$*" != *"--help"* ]]; then
    log_wrapper "Detected EFI installation request"
    
    # Parse arguments and add our required flags
    ARGS="$*"
    
    # Add --removable if not present
    if [[ "$ARGS" != *"--removable"* ]]; then
        ARGS="$ARGS --removable"
        log_wrapper "Added --removable flag"
    fi
    
    # Add --no-nvram if not present (prevents EFI boot entry creation)
    if [[ "$ARGS" != *"--no-nvram"* ]]; then
        ARGS="$ARGS --no-nvram"
        log_wrapper "Added --no-nvram flag"
    fi
    
    log_wrapper "Installing with fallback boot support"
    log_wrapper "Command: /usr/sbin/grub-install.original $ARGS"
    
    # Execute the original grub-install with our modifications
    exec /usr/sbin/grub-install.original $ARGS
else
    # For non-EFI installations or help requests, use original behavior
    exec /usr/sbin/grub-install.original "$@"
fi
EOF

chmod +x /usr/sbin/grub-install
print_status "GRUB wrapper script created and made executable"

# ============================================================================
# STEP 2: Configure GRUB Defaults
# ============================================================================
print_step "2. Configuring GRUB Defaults"

# Backup original GRUB config
if [[ ! -f "/etc/default/grub.original" ]]; then
    cp /etc/default/grub /etc/default/grub.original
    print_status "Original GRUB config backed up"
fi

# Configure GRUB for fallback boot and prevent hanging
{
    echo ""
    echo "# GRUB Fallback Boot Configuration"
    echo "# Added by GRUB Fallback Setup Script"
    echo "GRUB_FORCE_REMOVABLE=true"
    echo "GRUB_DISABLE_OS_PROBER=true"
    echo "GRUB_DISABLE_SUBMENU=y"
    echo "GRUB_TIMEOUT=5"
    echo "GRUB_RECORDFAIL_TIMEOUT=5"
} >> /etc/default/grub

print_status "GRUB defaults configured for fallback boot"

# ============================================================================
# STEP 3: Create Maintenance Script
# ============================================================================
print_step "3. Creating Maintenance Script"

cat > /usr/local/bin/maintain-grub-fallback.sh << 'EOF'
#!/bin/bash
# GRUB Fallback Maintenance Script
# Ensures the wrapper persists after package updates

WRAPPER_SIGNATURE="GRUB Install Wrapper - Forces --removable option"

if [[ -f /usr/sbin/grub-install.original ]] && [[ -f /usr/sbin/grub-install ]]; then
    # Check if our wrapper is still in place
    if ! grep -q "$WRAPPER_SIGNATURE" /usr/sbin/grub-install 2>/dev/null; then
        logger "GRUB Fallback: Restoring wrapper after package update"
        
        # Backup the new package version
        cp /usr/sbin/grub-install /usr/sbin/grub-install.pkg
        
        # Restore our wrapper
        cat > /usr/sbin/grub-install << 'WRAPPER_EOF'
#!/bin/bash
# GRUB Install Wrapper - Forces --removable option for EFI installations
# This ensures BOOTX64.EFI is created instead of distribution-specific files
# Restored by maintenance script

log_wrapper() {
    echo "GRUB Wrapper: $1" >&2
}

if [[ "$*" == *"--target=x86_64-efi"* ]] || [[ "$*" == *"efi"* ]] && [[ "$*" != *"--help"* ]]; then
    log_wrapper "Detected EFI installation request"
    ARGS="$*"
    
    if [[ "$ARGS" != *"--removable"* ]]; then
        ARGS="$ARGS --removable"
        log_wrapper "Added --removable flag"
    fi
    
    if [[ "$ARGS" != *"--no-nvram"* ]]; then
        ARGS="$ARGS --no-nvram"
        log_wrapper "Added --no-nvram flag"
    fi
    
    log_wrapper "Installing with fallback boot support"
    exec /usr/sbin/grub-install.pkg $ARGS
else
    exec /usr/sbin/grub-install.pkg "$@"
fi
WRAPPER_EOF
        
        chmod +x /usr/sbin/grub-install
        logger "GRUB Fallback: Wrapper restored successfully"
    fi
fi
EOF

chmod +x /usr/local/bin/maintain-grub-fallback.sh
print_status "Maintenance script created"

# ============================================================================
# STEP 4: Configure APT Hook
# ============================================================================
print_step "4. Configuring APT Package Update Protection"

# Remove any existing malformed hooks
rm -f /etc/apt/apt.conf.d/99-grub-fallback

# Create a simple, working APT hook
cat > /etc/apt/apt.conf.d/99-grub-fallback << 'EOF'
DPkg::Post-Invoke {
    "/usr/local/bin/maintain-grub-fallback.sh || true";
};
EOF

print_status "APT hook configured to maintain wrapper after updates"

# ============================================================================
# STEP 5: Configure Kernel Update Hooks
# ============================================================================
print_step "5. Configuring Kernel Update Hooks"

mkdir -p /etc/kernel/postinst.d
cat > /etc/kernel/postinst.d/grub-fallback << 'EOF'
#!/bin/bash
# Ensure GRUB fallback boot after kernel updates

# Only run for EFI systems
if [[ -d "/sys/firmware/efi" ]]; then
    EFI_MOUNT=$(findmnt -n -o TARGET -t vfat | head -1)
    if [[ -n "$EFI_MOUNT" ]]; then
        logger "GRUB Fallback: Ensuring fallback boot after kernel update"
        
        # Reinstall GRUB to fallback path (wrapper will handle flags)
        /usr/sbin/grub-install --target=x86_64-efi --efi-directory="$EFI_MOUNT" 2>/dev/null || true
        
        # Generate new GRUB config safely
        timeout 60 grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || {
            logger "GRUB Fallback: Standard config generation failed, using safe method"
            GRUB_DISABLE_OS_PROBER=true timeout 30 grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null || true
        }
    fi
fi
EOF

chmod +x /etc/kernel/postinst.d/grub-fallback
print_status "Kernel update hook configured"

# ============================================================================
# STEP 6: Create Boot Verification Service
# ============================================================================
print_step "6. Creating Boot Verification Service"

cat > /etc/systemd/system/grub-fallback-verify.service << 'EOF'
[Unit]
Description=Verify GRUB Fallback Boot Configuration
After=multi-user.target

[Service]
Type=oneshot
ExecStart=/usr/local/bin/verify-grub-fallback.sh
RemainAfterExit=yes
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
EOF

cat > /usr/local/bin/verify-grub-fallback.sh << 'EOF'
#!/bin/bash
# Verify GRUB fallback boot configuration on startup

EFI_MOUNT=$(findmnt -n -o TARGET -t vfat | head -1)

if [[ -n "$EFI_MOUNT" ]] && [[ -d "/sys/firmware/efi" ]]; then
    if [[ ! -f "$EFI_MOUNT/EFI/BOOT/BOOTX64.EFI" ]]; then
        logger "GRUB Fallback: BOOTX64.EFI missing, reinstalling..."
        /usr/sbin/grub-install --target=x86_64-efi --efi-directory="$EFI_MOUNT" 2>/dev/null || true
    else
        logger "GRUB Fallback: Boot configuration verified"
    fi
fi
EOF

chmod +x /usr/local/bin/verify-grub-fallback.sh
systemctl enable grub-fallback-verify.service >/dev/null 2>&1
print_status "Boot verification service created and enabled"

# ============================================================================
# STEP 7: Create Safe GRUB Update Script
# ============================================================================
print_step "7. Creating Safe GRUB Update Script"

cat > /usr/local/bin/update-grub-safe << 'EOF'
#!/bin/bash
# Safe GRUB configuration update script
# Prevents hanging and ensures fallback boot compatibility

echo "Running safe GRUB configuration update..."

# Kill any hanging processes first
pkill -f grub-mkconfig >/dev/null 2>&1 || true
pkill -f update-grub >/dev/null 2>&1 || true
pkill -f os-prober >/dev/null 2>&1 || true

# Export environment to disable problematic features
export GRUB_DISABLE_OS_PROBER=true

# Try standard generation with timeout
echo "Attempting standard GRUB config generation..."
if timeout 60 grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null; then
    echo "GRUB configuration updated successfully"
else
    echo "Standard generation failed, trying safe method..."
    
    # Temporarily disable problematic scripts
    [[ -f /etc/grub.d/30_os-prober ]] && mv /etc/grub.d/30_os-prober /etc/grub.d/30_os-prober.disabled
    [[ -f /etc/grub.d/30_uefi-firmware ]] && mv /etc/grub.d/30_uefi-firmware /etc/grub.d/30_uefi-firmware.disabled
    
    # Try again with disabled scripts
    if timeout 30 grub-mkconfig -o /boot/grub/grub.cfg 2>/dev/null; then
        echo "GRUB configuration updated with safe method"
    else
        echo "Safe generation failed, creating minimal configuration..."
        
        # Create minimal working configuration
        ROOT_UUID=$(blkid -s UUID -o value $(findmnt -n -o SOURCE /) 2>/dev/null || echo "")
        cat > /boot/grub/grub.cfg << MINIMAL_EOF
# Minimal GRUB Configuration for Fallback Boot
set timeout=5
set default=0

insmod part_gpt
insmod part_msdos
insmod fat
insmod ext2

search --no-floppy --fs-uuid --set=root $ROOT_UUID

menuentry 'Linux' {
    linux /vmlinuz root=UUID=$ROOT_UUID ro quiet splash
    initrd /initrd.img
}

menuentry 'Linux (recovery mode)' {
    linux /vmlinuz root=UUID=$ROOT_UUID ro recovery nomodeset
    initrd /initrd.img
}
MINIMAL_EOF
        echo "Minimal GRUB configuration created"
    fi
    
    # Re-enable scripts
    [[ -f /etc/grub.d/30_os-prober.disabled ]] && mv /etc/grub.d/30_os-prober.disabled /etc/grub.d/30_os-prober
    [[ -f /etc/grub.d/30_uefi-firmware.disabled ]] && mv /etc/grub.d/30_uefi-firmware.disabled /etc/grub.d/30_uefi-firmware
fi

echo "GRUB update completed"
EOF

chmod +x /usr/local/bin/update-grub-safe
print_status "Safe GRUB update script created"

# ============================================================================
# STEP 8: Install GRUB with Fallback Configuration
# ============================================================================
print_step "8. Installing GRUB with Fallback Configuration"

# Ensure EFI directory structure exists
mkdir -p "$EFI_MOUNT/EFI/BOOT"

# Kill any hanging processes
pkill -f grub-mkconfig >/dev/null 2>&1 || true
pkill -f update-grub >/dev/null 2>&1 || true

# Install GRUB using our wrapper
print_status "Running GRUB installation (wrapper will add --removable automatically)..."
/usr/sbin/grub-install --target=x86_64-efi --efi-directory="$EFI_MOUNT"

# Generate GRUB configuration safely
print_status "Generating GRUB configuration..."
/usr/local/bin/update-grub-safe

# ============================================================================
# STEP 9: Clean Up and Verify
# ============================================================================
print_step "9. Cleanup and Verification"

# Remove distribution-specific directories
for distro_dir in "$EFI_MOUNT/EFI/debian" "$EFI_MOUNT/EFI/ubuntu" "$EFI_MOUNT/EFI/BOOT/grub"; do
    if [[ -d "$distro_dir" ]]; then
        print_warning "Removing distribution-specific directory: $distro_dir"
        rm -rf "$distro_dir"
    fi
done

# Verify installation
print_status "Verifying installation..."

if [[ -f "$EFI_MOUNT/EFI/BOOT/BOOTX64.EFI" ]]; then
    print_status "✓ BOOTX64.EFI exists at $EFI_MOUNT/EFI/BOOT/"
    ls -la "$EFI_MOUNT/EFI/BOOT/BOOTX64.EFI"
else
    print_error "✗ BOOTX64.EFI missing!"
    exit 1
fi

if [[ -f /boot/grub/grub.cfg ]] && [[ -s /boot/grub/grub.cfg ]]; then
    GRUB_SIZE=$(stat -c%s /boot/grub/grub.cfg)
    print_status "✓ grub.cfg exists (${GRUB_SIZE} bytes)"
else
    print_error "✗ grub.cfg missing or empty!"
    exit 1
fi

# Test wrapper functionality
print_status "Testing wrapper functionality..."
if grep -q "GRUB Install Wrapper" /usr/sbin/grub-install; then
    print_status "✓ GRUB wrapper is active"
else
    print_error "✗ GRUB wrapper not found!"
    exit 1
fi

# Show final EFI structure
print_status "Final EFI directory structure:"
tree "$EFI_MOUNT/EFI" 2>/dev/null || find "$EFI_MOUNT/EFI" -type f

# ============================================================================
# STEP 10: Create Uninstall Script
# ============================================================================
print_step "10. Creating Uninstall Script"

cat > /usr/local/bin/uninstall-grub-fallback << 'EOF'
#!/bin/bash
# Uninstall GRUB Fallback Configuration

echo "Uninstalling GRUB Fallback configuration..."

# Restore original grub-install
if [[ -f /usr/sbin/grub-install.original ]]; then
    mv /usr/sbin/grub-install.original /usr/sbin/grub-install
    echo "Original grub-install restored"
fi

# Restore original GRUB config
if [[ -f /etc/default/grub.original ]]; then
    mv /etc/default/grub.original /etc/default/grub
    echo "Original GRUB config restored"
fi

# Remove hooks and services
rm -f /etc/apt/apt.conf.d/99-grub-fallback
rm -f /etc/kernel/postinst.d/grub-fallback
systemctl disable grub-fallback-verify.service >/dev/null 2>&1
rm -f /etc/systemd/system/grub-fallback-verify.service

# Remove scripts
rm -f /usr/local/bin/maintain-grub-fallback.sh
rm -f /usr/local/bin/verify-grub-fallback.sh
rm -f /usr/local/bin/update-grub-safe

echo "GRUB Fallback configuration removed"
echo "Run 'grub-install' and 'update-grub' to restore standard behavior"
EOF

chmod +x /usr/local/bin/uninstall-grub-fallback
print_status "Uninstall script created at /usr/local/bin/uninstall-grub-fallback"

# ============================================================================
# FINAL REPORT
# ============================================================================
print_header "INSTALLATION COMPLETE"

echo -e "${GREEN}✓ GRUB Fallback Boot Successfully Configured${NC}"
echo ""
echo -e "${YELLOW}System Changes:${NC}"
echo "  • GRUB wrapper installed (forces --removable for EFI)"
echo "  • APT hook prevents package updates from breaking wrapper"
echo "  • Kernel update hook maintains fallback boot"
echo "  • Boot verification service ensures configuration"
echo "  • Safe GRUB update script created"
echo ""
echo -e "${YELLOW}Key Files:${NC}"
echo "  • EFI Boot: $EFI_MOUNT/EFI/BOOT/BOOTX64.EFI"
echo "  • GRUB Config: /boot/grub/grub.cfg"
echo "  • Wrapper: /usr/sbin/grub-install"
echo "  • Safe Update: /usr/local/bin/update-grub-safe"
echo "  • Uninstall: /usr/local/bin/uninstall-grub-fallback"
echo ""
echo -e "${YELLOW}For ISO Creation:${NC}"
echo "  • This system is now ready for ISO creation"
echo "  • All configurations will be preserved in the ISO"
echo "  • Systems installed from your ISO will use fallback boot"
echo ""
echo -e "${YELLOW}Testing:${NC}"
echo "  • Reboot to test the configuration"
echo "  • Use 'sudo /usr/local/bin/update-grub-safe' for future GRUB updates"
echo ""
echo -e "${GREEN}Your system will now always boot from /efi/boot/bootx64.efi${NC}"
print_warning "Remember to test boot functionality before creating your ISO!"
