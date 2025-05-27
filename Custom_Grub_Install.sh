#!/bin/bash

# Enhanced GRUB Restore Script with Theme Support
# Automatically enables splash.png background and makes config portable

set -euo pipefail  # Strict error handling

# Configuration
FULL_BACKUP_URL="https://glitchlinux.wtf/grub_backup.tar.gz"
MINIMAL_BACKUP_URL="https://glitchlinux.wtf/grub_backup_no_live_97MB.tar.gz"
TEMP_DIR=$(mktemp -d)
LOG_FILE="/var/log/grub_restore.log"
SPLASH_PATH="/boot/grub/splash.png"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Logging function
log() {
    echo -e "$(date '+%Y-%m-%d %H:%M:%S') - $*" | tee -a "$LOG_FILE"
}

# Cleanup function
cleanup() {
    log "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}

# Error handler
error_handler() {
    log "${RED}ERROR:${NC} Script failed on line $1"
    cleanup
    exit 1
}

trap 'error_handler $LINENO' ERR

# Display restore options
show_options() {
    echo -e "${BLUE}GRUB Configuration Restore Options:${NC}"
    echo
    echo -e "1) ${GREEN}Full Restore${NC} - Includes live boot capabilities"
    echo -e "   (Larger download, complete configuration)"
    echo
    echo -e "2) ${YELLOW}Minimal Restore${NC} - Basic GRUB configuration"
    echo -e "   (Smaller 97MB download, no live boot)"
    echo
    echo -e "3) ${RED}Cancel${NC} - Exit without making changes"
    echo
}

# Verify requirements
check_requirements() {
    log "Checking system requirements..."
    local missing=()
    
    for cmd in curl tar sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done

    if [ ${#missing[@]} -gt 0 ]; then
        log "${RED}Error:${NC} Missing required commands: ${missing[*]}"
        exit 1
    fi
}

# Download backup
download_backup() {
    local url="$1"
    local backup_file="$2"
    
    log "Downloading GRUB backup from ${url}..."
    if ! curl -L -o "$backup_file" "$url"; then
        log "${RED}Error:${NC} Failed to download backup file"
        exit 1
    fi

    log "Download complete. Backup size: $(du -h "$backup_file" | cut -f1)"
}

# Verify backup
verify_backup() {
    local backup_file="$1"
    
    log "Verifying backup integrity..."
    if ! tar -tzf "$backup_file" >/dev/null 2>&1; then
        log "${RED}Error:${NC} Backup file is corrupt or invalid"
        exit 1
    fi
    log "${GREEN}Backup verification passed${NC}"
}

# Make GRUB configuration portable
make_portable() {
    log "Making GRUB configuration portable..."
    
    # Modify /etc/default/grub to use relative paths
    sudo sed -i 's/^GRUB_CMDLINE_LINUX=.*/GRUB_CMDLINE_LINUX="ro"/' /etc/default/grub
    sudo sed -i 's/^GRUB_DEVICE=.*/#GRUB_DEVICE=/' /etc/default/grub
    
    # Ensure splash screen is enabled
    if ! grep -q "GRUB_BACKGROUND=" /etc/default/grub; then
        echo "GRUB_BACKGROUND=\"$SPLASH_PATH\"" | sudo tee -a /etc/default/grub
    else
        sudo sed -i "s|^GRUB_BACKGROUND=.*|GRUB_BACKGROUND=\"$SPLASH_PATH\"|" /etc/default/grub
    fi
    
    # Enable graphical terminal
    if ! grep -q "GRUB_TERMINAL=console" /etc/default/grub; then
        echo "GRUB_TERMINAL_OUTPUT=\"gfxterm\"" | sudo tee -a /etc/default/grub
    fi
    
    # Update GRUB_TIMEOUT if needed
    sudo sed -i 's/^GRUB_TIMEOUT=.*/GRUB_TIMEOUT=5/' /etc/default/grub
    
    log "${GREEN}GRUB configuration now portable${NC}"
}

# Fix GRUB theme and splash
fix_theme() {
    log "Configuring GRUB theme and splash screen..."
    
    # Ensure required modules are loaded
    echo "GRUB_GFXMOD_LINUX=\"gfxterm gfxmenu png\"" | sudo tee -a /etc/default/grub
    
    # Copy splash.png if it doesn't exist
    if [ ! -f "$SPLASH_PATH" ]; then
        if [ -f "${TEMP_DIR}/boot/grub/splash.png" ]; then
            sudo cp "${TEMP_DIR}/boot/grub/splash.png" "$SPLASH_PATH"
        else
            log "${YELLOW}Warning:${NC} splash.png not found in backup"
        fi
    fi
    
    # Ensure proper permissions
    sudo chmod 644 "$SPLASH_PATH"
    
    log "${GREEN}Theme configuration complete${NC}"
}

# Restore files
restore_files() {
    local backup_file="$1"
    
    log "Extracting backup to temporary location..."
    tar -xzf "$backup_file" -C "$TEMP_DIR"

    # Verify essential files exist in backup
    declare -a required_files=(
        "etc/default/grub"
        "etc/grub.d/40_custom_bootmanagers"
        "etc/grub.d/40_custom"
        "etc/grub.d/10_linux"
        "boot"
    )

    for file in "${required_files[@]}"; do
        if [ ! -e "${TEMP_DIR}/${file}" ]; then
            log "${RED}Error:${NC} Backup missing required file: ${file}"
            exit 1
        fi
    done

    log "${YELLOW}WARNING:${NC} This will overwrite your current GRUB configuration!"
    log "The following will be replaced:"
    log "  /etc/default/grub"
    log "  /etc/grub.d/40_custom_bootmanagers"
    log "  /etc/grub.d/40_custom"
    log "  /etc/grub.d/10_linux"
    log "  Entire /boot directory contents"

    read -rp "Are you absolutely sure you want to continue? (y/N) " confirm
    if [[ "$confirm" != [yY] ]]; then
        log "Restore cancelled by user."
        exit 0
    fi

    # Create backups of existing files
    log "Creating backups of current files..."
    mkdir -p "${TEMP_DIR}/backups"
    sudo cp -a /etc/default/grub "${TEMP_DIR}/backups/grub.bak" 2>/dev/null || true
    sudo cp -a /etc/grub.d "${TEMP_DIR}/backups/grub.d.bak" 2>/dev/null || true
    sudo cp -a /boot "${TEMP_DIR}/backups/boot.bak" 2>/dev/null || true

    # Restore files
    log "Restoring GRUB configuration files..."
    sudo cp -af "${TEMP_DIR}/etc/default/grub" "/etc/default/"
    sudo rm -rf /etc/grub.d 2>/dev/null || true
    sudo cp -af "${TEMP_DIR}/etc/grub.d" "/etc/"

    log "Restoring /boot directory..."
    sudo rsync -a --delete "${TEMP_DIR}/boot/" "/boot/"

    # Make configuration portable
    make_portable
    
    # Fix theme and splash
    fix_theme

    log "${GREEN}File restoration complete${NC}"
}

# Post-restore steps
post_restore() {
    log "Running post-restore steps..."
    
    log "Updating GRUB configuration..."
    if ! sudo update-grub; then
        log "${YELLOW}Warning:${NC} GRUB configuration update failed"
    fi

    log "Reinstalling GRUB bootloader..."
    if [ -d "/boot/efi" ]; then
        log "Detected EFI system, installing GRUB for EFI..."
        if ! sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB; then
            log "${YELLOW}Warning:${NC} GRUB EFI installation failed"
        fi
    else
        log "Detected BIOS system, installing GRUB to default device..."
        if ! sudo grub-install; then
            log "${YELLOW}Warning:${NC} GRUB BIOS installation failed"
        fi
    fi

    log "Generating final GRUB config..."
    sudo grub-mkconfig -o /boot/grub/grub.cfg

    log "${GREEN}GRUB restoration complete!${NC}"
    log "You may need to reboot for changes to take effect."
}

# Main execution
main() {
    echo -e "${BLUE}=== GRUB Configuration Restore ===${NC}"
    echo
    
    while true; do
        show_options
        
        read -rp "Enter your choice (1-3): " choice
        case $choice in
            1)
                backup_url="$FULL_BACKUP_URL"
                backup_file="${TEMP_DIR}/grub_full_backup.tar.gz"
                log "=== Starting FULL GRUB Configuration Restore (with live boot) ==="
                break
                ;;
            2)
                backup_url="$MINIMAL_BACKUP_URL"
                backup_file="${TEMP_DIR}/grub_minimal_backup.tar.gz"
                log "=== Starting MINIMAL GRUB Configuration Restore (without live boot) ==="
                break
                ;;
            3)
                echo -e "${BLUE}Restore cancelled by user. No changes were made.${NC}"
                exit 0
                ;;
            *)
                echo -e "${RED}Invalid option. Please choose 1, 2, or 3.${NC}"
                ;;
        esac
    done

    check_requirements
    download_backup "$backup_url" "$backup_file"
    verify_backup "$backup_file"
    restore_files "$backup_file"
    post_restore
    cleanup
    log "=== Restore Process Complete ==="
}

# Run main function
main
