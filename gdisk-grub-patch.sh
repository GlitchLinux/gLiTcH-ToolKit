#!/bin/bash
# gdisk-grub-patch.sh - Add/remove Gdisk from the host system's GRUB boot menu
#
# Usage:
#   sudo ./gdisk-grub-patch.sh install   - Clone Gdisk to /boot/gdisk and add GRUB menu entry
#   sudo ./gdisk-grub-patch.sh update    - Pull latest Gdisk and refresh GRUB
#   sudo ./gdisk-grub-patch.sh remove    - Remove Gdisk from GRUB and delete /boot/gdisk
#
# Requirements: git, grub (update-grub or grub2-mkconfig)
# License: GPLv3

set -e

GDISK_DIR="/boot/gdisk"
GRUB_D_DIR=""
UPDATE_GRUB=""

# Detect grub.d location and update command
detect_grub() {
    if [ -d /etc/grub.d ]; then
        GRUB_D_DIR="/etc/grub.d"
    else
        echo "Error: /etc/grub.d not found. Is GRUB installed?"
        exit 1
    fi

    if command -v update-grub >/dev/null 2>&1; then
        UPDATE_GRUB="update-grub"
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        UPDATE_GRUB="grub2-mkconfig -o /boot/grub2/grub.cfg"
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        UPDATE_GRUB="grub-mkconfig -o /boot/grub/grub.cfg"
    else
        echo "Error: No grub config generator found (update-grub / grub-mkconfig / grub2-mkconfig)"
        exit 1
    fi
}

# Check root
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

do_install() {
    if [ -d "$GDISK_DIR/boot/grub" ]; then
        echo "Gdisk is already installed at $GDISK_DIR"
        echo "Use 'update' to pull the latest version, or 'remove' first."
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git is required. Install it with your package manager."
        exit 1
    fi

    echo "Cloning Gdisk to $GDISK_DIR..."
    git clone --depth 1 https://github.com/GlitchLinux/Gdisk.git "$GDISK_DIR"

    echo "Installing GRUB hook at $GRUB_D_DIR/99-gdisk..."
    cat > "$GRUB_D_DIR/99-gdisk" << 'GRUBEOF'
#!/bin/sh
exec tail -n +3 "$0"

menuentry "Gdisk - Multiboot Manager" --class gdisk --class boot {
    configfile /boot/gdisk/boot/grub/gdisk.cfg
}
GRUBEOF
    chmod +x "$GRUB_D_DIR/99-gdisk"

    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "Done. Gdisk has been added to your GRUB boot menu."
    echo "Reboot and select 'Gdisk - Multiboot Manager' to use it."
}

do_update() {
    if [ ! -d "$GDISK_DIR/.git" ]; then
        echo "Error: Gdisk is not installed at $GDISK_DIR (no git repo found)."
        echo "Run 'install' first."
        exit 1
    fi

    echo "Pulling latest Gdisk..."
    cd "$GDISK_DIR" && git pull

    # Ensure hook is still in place
    if [ ! -x "$GRUB_D_DIR/99-gdisk" ]; then
        echo "GRUB hook missing, reinstalling..."
        cat > "$GRUB_D_DIR/99-gdisk" << 'GRUBEOF'
#!/bin/sh
exec tail -n +3 "$0"

menuentry "Gdisk - Multiboot Manager" --class gdisk --class boot {
    configfile /boot/gdisk/boot/grub/gdisk.cfg
}
GRUBEOF
        chmod +x "$GRUB_D_DIR/99-gdisk"
    fi

    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "Done. Gdisk has been updated."
}

do_remove() {
    echo "Removing Gdisk from GRUB..."

    if [ -f "$GRUB_D_DIR/99-gdisk" ]; then
        rm -f "$GRUB_D_DIR/99-gdisk"
        echo "Removed GRUB hook."
    fi

    if [ -d "$GDISK_DIR" ]; then
        rm -rf "$GDISK_DIR"
        echo "Removed $GDISK_DIR"
    fi

    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "Done. Gdisk has been removed from your GRUB boot menu."
}

# Main
check_root
detect_grub

case "${1:-}" in
    install)
        do_install
        ;;
    update)
        do_update
        ;;
    remove)
        do_remove
        ;;
    *)
        echo "Gdisk GRUB Patcher"
        echo ""
        echo "Usage: sudo $0 {install|update|remove}"
        echo ""
        echo "  install  - Clone Gdisk to /boot/gdisk and add it to GRUB"
        echo "  update   - Pull latest Gdisk and refresh GRUB"
        echo "  remove   - Remove Gdisk from GRUB and delete /boot/gdisk"
        exit 0
        ;;
esac
