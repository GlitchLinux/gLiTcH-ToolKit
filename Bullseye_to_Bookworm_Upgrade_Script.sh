#!/bin/bash

# Sparky Linux Bullseye to Bookworm Upgrade Script
# Handles usrmerge and other upgrade issues

set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log() {
    echo -e "${BLUE}[$(date '+%Y-%m-%d %H:%M:%S')]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    error "This script must be run as root (use sudo)"
    exit 1
fi

# Backup function
create_backup() {
    log "Creating backup of important files..."
    
    mkdir -p /root/upgrade-backup-$(date +%Y%m%d)
    BACKUP_DIR="/root/upgrade-backup-$(date +%Y%m%d)"
    
    # Backup sources.list
    cp /etc/apt/sources.list "$BACKUP_DIR/"
    cp -r /etc/apt/sources.list.d "$BACKUP_DIR/"
    
    # Backup important configs
    cp /etc/fstab "$BACKUP_DIR/"
    cp -r /etc/network "$BACKUP_DIR/" 2>/dev/null || true
    
    success "Backup created in $BACKUP_DIR"
}

# Check current system
check_system() {
    log "Checking current system..."
    
    # Check Debian version
    if [[ -f /etc/debian_version ]]; then
        DEBIAN_VERSION=$(cat /etc/debian_version)
        log "Current Debian version: $DEBIAN_VERSION"
    fi
    
    # Check Sparky version
    if [[ -f /etc/sparky-version ]]; then
        SPARKY_VERSION=$(cat /etc/sparky-version)
        log "Current Sparky version: $SPARKY_VERSION"
    fi
    
    # Check if bullseye
    if ! grep -q "bullseye" /etc/apt/sources.list*; then
        error "This doesn't appear to be a Bullseye system"
        exit 1
    fi
    
    # Check disk space
    AVAILABLE_SPACE=$(df / | awk 'NR==2 {print $4}')
    if [[ $AVAILABLE_SPACE -lt 2097152 ]]; then  # 2GB in KB
        error "Insufficient disk space. Need at least 2GB free"
        exit 1
    fi
    
    success "System check passed"
}

# Update current system
update_current_system() {
    log "Updating current Bullseye system..."
    
    apt update
    apt upgrade -y
    apt full-upgrade -y
    apt autoremove -y
    apt autoclean
    
    success "Current system updated"
}

# Handle usrmerge issue
fix_usrmerge() {
    log "Handling usrmerge transition..."
    
    # Check if usrmerge is needed
    if [[ -d /bin && ! -L /bin ]]; then
        warn "System needs usrmerge conversion"
        
        # Install usrmerge package
        apt update
        apt install -y usrmerge
        
        log "Running usrmerge conversion..."
        # This converts /bin, /sbin, /lib to symlinks pointing to /usr
        convert-usrmerge
        
        success "usrmerge conversion completed"
    else
        log "usrmerge already applied or not needed"
    fi
}

# Update sources.list for Bookworm
update_sources_list() {
    log "Updating sources.list for Bookworm..."
    
    # Backup current sources
    cp /etc/apt/sources.list /etc/apt/sources.list.bullseye-backup
    
    # Create new sources.list for Bookworm
    cat > /etc/apt/sources.list << 'EOF'
# Debian Bookworm repositories
deb http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm main contrib non-free non-free-firmware

deb http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian bookworm-updates main contrib non-free non-free-firmware

deb http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
deb-src http://deb.debian.org/debian-security bookworm-security main contrib non-free non-free-firmware
EOF

    # Handle Sparky-specific repositories
    if [[ -d /etc/apt/sources.list.d ]]; then
        log "Updating Sparky repositories..."
        
        # Remove or update Sparky repos to Bookworm versions
        for file in /etc/apt/sources.list.d/*.list; do
            if [[ -f "$file" ]]; then
                # Backup
                cp "$file" "${file}.bullseye-backup"
                
                # Update bullseye to bookworm in Sparky repos
                if grep -q "sparky" "$file"; then
                    sed -i 's/bullseye/bookworm/g' "$file"
                fi
                
                # Comment out problematic repos temporarily
                if grep -q "testing\|unstable\|sid" "$file"; then
                    warn "Commenting out testing/unstable repos in $file"
                    sed -i 's/^deb/#deb/g' "$file"
                fi
            fi
        done
    fi
    
    success "Sources updated for Bookworm"
}

# Minimal upgrade approach
minimal_upgrade() {
    log "Performing minimal upgrade to avoid conflicts..."
    
    # Update package lists
    apt update
    
    # First, upgrade essential packages
    log "Upgrading essential packages first..."
    apt install -y --only-upgrade apt dpkg libc6 locales
    
    # Handle potential conflicts
    log "Resolving package conflicts..."
    
    # Remove problematic packages that might conflict
    apt remove -y --purge \
        libpam-systemd:i386 \
        systemd:i386 \
        2>/dev/null || true
    
    # Fix broken packages
    apt --fix-broken install -y
    
    success "Minimal upgrade completed"
}

# Main upgrade
main_upgrade() {
    log "Performing main system upgrade..."
    
    # Set non-interactive mode
    export DEBIAN_FRONTEND=noninteractive
    
    # Upgrade in stages
    log "Stage 1: Upgrading core system..."
    apt upgrade -y
    
    log "Stage 2: Full distribution upgrade..."
    apt full-upgrade -y
    
    # Handle any remaining issues
    apt --fix-broken install -y
    apt autoremove -y
    
    success "Main upgrade completed"
}

# Post-upgrade cleanup
post_upgrade_cleanup() {
    log "Performing post-upgrade cleanup..."
    
    # Clean package cache
    apt autoclean
    apt autoremove -y
    
    # Update locate database
    updatedb 2>/dev/null || true
    
    # Regenerate initramfs
    log "Regenerating initramfs..."
    update-initramfs -u -k all
    
    # Update GRUB
    log "Updating GRUB..."
    update-grub
    
    success "Post-upgrade cleanup completed"
}

# Verify upgrade
verify_upgrade() {
    log "Verifying upgrade..."
    
    # Check new version
    NEW_VERSION=$(cat /etc/debian_version)
    log "New Debian version: $NEW_VERSION"
    
    # Check if bookworm
    if grep -q "bookworm" /etc/apt/sources.list; then
        success "Successfully upgraded to Bookworm"
    else
        warn "Upgrade verification inconclusive"
    fi
    
    # Check for broken packages
    BROKEN=$(dpkg -l | grep "^.[^i]" | wc -l)
    if [[ $BROKEN -gt 0 ]]; then
        warn "Found $BROKEN packages in non-installed state"
        log "Run 'dpkg -l | grep \"^.[^i]\"' to see them"
    fi
}

# Handle specific Sparky issues
fix_sparky_issues() {
    log "Fixing Sparky-specific issues..."
    
    # Update Sparky tools if available
    if command -v sparky-upgrade >/dev/null 2>&1; then
        log "Running sparky-upgrade..."
        sparky-upgrade || warn "sparky-upgrade had issues"
    fi
    
    # Fix desktop environment issues
    if [[ -n "$SUDO_USER" ]]; then
        USER_HOME=$(eval echo ~$SUDO_USER)
        
        # Reset some configs that might cause issues
        if [[ -d "$USER_HOME/.config" ]]; then
            log "Backing up user configs..."
            sudo -u $SUDO_USER cp -r "$USER_HOME/.config" "$USER_HOME/.config.pre-bookworm" 2>/dev/null || true
        fi
    fi
    
    success "Sparky-specific fixes applied"
}

# Emergency recovery info
create_recovery_info() {
    log "Creating recovery information..."
    
    cat > /root/UPGRADE_RECOVERY_INFO.txt << 'EOF'
SPARKY LINUX BOOKWORM UPGRADE RECOVERY INFO
==========================================

If the system fails to boot after upgrade:

1. Boot from a live USB/CD
2. Mount your root filesystem
3. Chroot into the system:
   mount /dev/sdX1 /mnt  # Replace X1 with your root partition
   chroot /mnt
   
4. Restore sources.list if needed:
   cp /etc/apt/sources.list.bullseye-backup /etc/apt/sources.list
   apt update && apt install -f
   
5. Fix bootloader:
   update-grub
   grub-install /dev/sdX  # Replace X with your disk
   
6. If X11/graphics issues persist:
   apt install --reinstall xserver-xorg-core
   
BACKUP LOCATION: Check /root/upgrade-backup-* directories

For Sparky-specific help: https://sparkylinux.org/forum/
EOF
    
    success "Recovery info created at /root/UPGRADE_RECOVERY_INFO.txt"
}

# Main execution
main() {
    log "=== Sparky Linux Bullseye to Bookworm Upgrade ==="
    warn "This will upgrade your system from Bullseye to Bookworm"
    warn "Make sure you have backups of important data!"
    
    read -p "Do you want to continue? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log "Upgrade cancelled by user"
        exit 0
    fi
    
    # Execute upgrade steps
    create_backup
    check_system
    update_current_system
    fix_usrmerge
    update_sources_list
    minimal_upgrade
    main_upgrade
    fix_sparky_issues
    post_upgrade_cleanup
    verify_upgrade
    create_recovery_info
    
    success "=== UPGRADE COMPLETED ==="
    echo
    log "System has been upgraded to Bookworm!"
    log "IMPORTANT: Reboot your system now"
    log "After reboot, you can install JWM and Xorg with the previous script"
    echo
    warn "Recovery information saved to /root/UPGRADE_RECOVERY_INFO.txt"
    warn "Backup created in $BACKUP_DIR"
    echo
    
    read -p "Reboot now? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        log "Rebooting..."
        reboot
    else
        log "Please reboot manually when ready"
    fi
}

# Run main function
main "$@"
