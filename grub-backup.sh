#!/bin/bash

# Comprehensive GRUB Backup and Restore Script

set -euo pipefail  # Strict error handling

BACKUP_DIR="${HOME}/grub_boot_backups"
TIMESTAMP=$(date +%Y%m%d_%H%M%S)
BACKUP_FILE="${BACKUP_DIR}/grub_boot_backup_${TIMESTAMP}.tar.gz"

# Verify required commands exist
check_requirements() {
    for cmd in tar sha256sum; do
        if ! command -v "${cmd}" >/dev/null 2>&1; then
            echo "Error: Required command '${cmd}' not found!" >&2
            exit 1
        fi
    done
}

# Create backup function
backup_grub_boot() {
    echo "=== Creating Comprehensive GRUB and Boot Backup ==="
    
    # Create backup directory
    mkdir -p "${BACKUP_DIR}" || {
        echo "Error: Failed to create backup directory ${BACKUP_DIR}" >&2
        exit 1
    }

    # Files and directories to backup
    declare -a BACKUP_PATHS=(
        "/etc/default/grub"
        "/etc/grub.d/40_custom_bootmanagers"
        "/etc/grub.d/40_custom"
        "/etc/grub.d/10_linux"
        "/boot"
    )

    echo "Backing up:"
    printf "  %s\n" "${BACKUP_PATHS[@]}"

    # Create backup with verification
    if ! sudo tar -czvpf "${BACKUP_FILE}" \
        --exclude='/boot/lost+found' \
        "${BACKUP_PATHS[@]}" 2>/dev/null; then
        echo "Error: Backup creation failed!" >&2
        [ -f "${BACKUP_FILE}" ] && rm -f "${BACKUP_FILE}"
        exit 1
    fi

    echo -e "\nBackup successful: ${BACKUP_FILE}"
    echo "Size: $(du -h "${BACKUP_FILE}" | cut -f1)"
    echo "SHA256: $(sha256sum "${BACKUP_FILE}" | cut -d' ' -f1)"
}

# Restore function
restore_grub_boot() {
    local restore_file="$1"

    echo "=== GRUB and Boot Configuration Restore ==="
    
    if [ ! -f "${restore_file}" ]; then
        echo "Error: Backup file not found: ${restore_file}" >&2
        exit 1
    fi

    echo "WARNING: This will overwrite critical system files!"
    echo "The following will be replaced:"
    echo "  /etc/default/grub"
    echo "  /etc/grub.d/40_custom_bootmanagers"
    echo "  /etc/grub.d/40_custom"
    echo "  /etc/grub.d/10_linux"
    echo "  Entire /boot directory contents"
    
    read -rp "Are you absolutely sure you want to continue? (y/N) " confirm
    if [[ "${confirm}" != [yY] ]]; then
        echo "Restore cancelled."
        exit 0
    fi

    # Create temporary directory
    TEMP_DIR=$(mktemp -d)
    trap 'rm -rf "${TEMP_DIR}"' EXIT

    echo "Extracting backup..."
    if ! sudo tar -xzvf "${restore_file}" -C "${TEMP_DIR}"; then
        echo "Error: Failed to extract backup file" >&2
        exit 1
    fi

    # Verify extracted files
    declare -a REQUIRED_PATHS=(
        "${TEMP_DIR}/etc/default/grub"
        "${TEMP_DIR}/etc/grub.d/40_custom_bootmanagers"
        "${TEMP_DIR}/etc/grub.d/40_custom"
        "${TEMP_DIR}/etc/grub.d/10_linux"
        "${TEMP_DIR}/boot"
    )

    for path in "${REQUIRED_PATHS[@]}"; do
        if [ ! -e "${path}" ]; then
            echo "Error: Backup appears incomplete (missing ${path})" >&2
            exit 1
        fi
    done

    echo -e "\nRestoring files with backups of existing files..."
    
    # Restore /etc files with backups
    declare -a ETC_FILES=(
        "default/grub"
        "grub.d/40_custom_bootmanagers"
        "grub.d/40_custom"
        "grub.d/10_linux"
    )

    for file in "${ETC_FILES[@]}"; do
        src="${TEMP_DIR}/etc/${file}"
        dest="/etc/${file}"
        
        if [ -f "${src}" ]; then
            echo "Backing up current ${dest} to ${dest}.bak"
            sudo cp -af "${dest}" "${dest}.bak" 2>/dev/null || true
            echo "Restoring ${dest}"
            sudo cp -af "${src}" "${dest}"
        fi
    done

    # Restore /boot directory
    echo "Restoring /boot directory contents..."
    sudo rsync -a --delete "${TEMP_DIR}/boot/" "/boot/"

    echo -e "\nRestore completed successfully!"
    echo -e "\nIMPORTANT: You must now complete these steps:"
    echo "1. Update GRUB configuration:"
    echo "   sudo update-grub"
    echo "2. Reinstall GRUB bootloader:"
    echo "   For EFI systems:"
    echo "     sudo grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB"
    echo "   For BIOS systems:"
    echo "     sudo grub-install /dev/sdX (replace sdX with your actual boot device)"
    echo "3. Verify bootloader:"
    echo "   sudo grub-mkconfig -o /boot/grub/grub.cfg"
}

# Main script execution
main() {
    check_requirements

    case "${1:-}" in
        backup)
            backup_grub_boot
            ;;
        restore)
            if [ -z "${2:-}" ]; then
                echo "Usage: $0 restore <backup_file.tar.gz>" >&2
                exit 1
            fi
            restore_grub_boot "$2"
            ;;
        list)
            echo "Available backups in ${BACKUP_DIR}:"
            ls -lh "${BACKUP_DIR}"/*.tar.gz 2>/dev/null || echo "No backups found"
            ;;
        *)
            echo "Usage:"
            echo "  $0 backup        - Create backup of GRUB and boot files"
            echo "  $0 restore <file> - Restore from backup"
            echo "  $0 list          - List available backups"
            exit 1
            ;;
    esac
}

# Run main function with arguments
main "$@"