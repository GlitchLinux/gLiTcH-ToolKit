#!/bin/bash
# gdisk-grub-patch.sh - Add/remove Gdisk from the host system's GRUB boot menu
#
# Usage:
#   sudo ./gdisk-grub-patch.sh install   - Clone Gdisk to /boot/gdisk and add GRUB menu entry
#   sudo ./gdisk-grub-patch.sh update    - Pull latest Gdisk and refresh GRUB
#   sudo ./gdisk-grub-patch.sh remove    - Remove Gdisk from GRUB and delete /boot/gdisk
#
# On UEFI systems the menu entry sets $prefix to Gdisk's module path so that
# insmod finds the a1ive patched modules (map, ntboot, vhd, wimboot, etc.).
# If the host GRUB core rejects the a1ive modules (ABI mismatch), the entry
# falls back to chainloading Gdisk's own grub.efi.
#
# Requirements: git, python3, grub (update-grub or grub2-mkconfig)
# License: GPLv3

set -e

GDISK_DIR="/boot/gdisk"
GRUB_D_DIR=""
UPDATE_GRUB=""

# ── Detect grub.d location and update command ──
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
        echo "Error: No grub config generator found."
        exit 1
    fi
}

# ── Check root ──
check_root() {
    if [ "$(id -u)" -ne 0 ]; then
        echo "Error: This script must be run as root."
        exit 1
    fi
}

# ── Rewrite Gdisk internal paths for nested /boot/gdisk/ install ──
rewrite_paths() {
    local prefix="$1"

    if [ ! -d "$prefix/boot/grub" ]; then
        echo "Error: $prefix/boot/grub not found"
        exit 1
    fi

    if ! command -v python3 >/dev/null 2>&1; then
        echo "Error: python3 is required for path rewriting."
        exit 1
    fi

    echo "Rewriting internal paths: /boot/grub/ -> $prefix/boot/grub/"

    local count=0

    for cfg in $(find "$prefix/boot/grub" -name "*.cfg" -type f); do
        [ -f "$cfg" ] || continue

        if ! grep -q '/boot/grub/' "$cfg"; then
            continue
        fi

        python3 << PYEOF
with open("$cfg") as f:
    lines = f.readlines()

prefix = "$prefix"
out = []
in_loop = False

for line in lines:
    stripped = line.strip()

    if ('set root=loop' in stripped or 'root=(loop)' in stripped or
        '(loop)/boot/grub' in stripped):
        in_loop = True

    if in_loop and ('return 0' in stripped or 'loopback --delete' in stripped):
        out.append(line)
        in_loop = False
        continue

    if stripped.startswith('menuentry ') or stripped.startswith('function '):
        in_loop = False

    if in_loop:
        out.append(line)
        continue

    line = line.replace('(loop)/boot/grub/', '(loop)/__PBG__/')
    line = line.replace('(loop)/boot/grub2/', '(loop)/__PBG2__/')

    line = line.replace('/boot/grub/', prefix + '/boot/grub/')

    line = line.replace('(loop)/__PBG__/', '(loop)/boot/grub/')
    line = line.replace('(loop)/__PBG2__/', '(loop)/boot/grub2/')

    out.append(line)

with open("$cfg", "w") as f:
    f.writelines(out)
PYEOF

        count=$((count + 1))
    done

    echo "Rewrote paths in $count .cfg files."
}

# ── Install GRUB hook ──
# Sets $prefix to Gdisk's module path so insmod finds a1ive modules.
# Falls back to chainloading Gdisk's own grub.efi if insmod fails.
install_hook() {
    echo "Installing GRUB hook at $GRUB_D_DIR/99-gdisk..."
    cat > "$GRUB_D_DIR/99-gdisk" << 'GRUBEOF'
#!/bin/sh
exec tail -n +3 "$0"

menuentry "Gdisk - Multiboot Manager" --class gdisk --class boot {
    # Point $prefix at Gdisk's module dir so insmod finds
    # a1ive patched modules (map, ntboot, vhd, wimboot, etc.)
    set prefix=/boot/gdisk/boot/grub
    configfile /boot/gdisk/boot/grub/gdisk.cfg
}
GRUBEOF
    chmod +x "$GRUB_D_DIR/99-gdisk"
}

# ── Install ──
do_install() {
    if [ -d "$GDISK_DIR/boot/grub" ]; then
        echo "Gdisk is already installed at $GDISK_DIR"
        echo "Use 'update' to pull the latest version, or 'remove' first."
        exit 1
    fi

    if ! command -v git >/dev/null 2>&1; then
        echo "Error: git is required."
        exit 1
    fi

    echo "=== Cloning Gdisk ==="
    git clone --depth 1 https://github.com/GlitchLinux/Gdisk.git "$GDISK_DIR"

    echo ""
    echo "=== Rewriting paths ==="
    rewrite_paths "$GDISK_DIR"

    echo ""
    echo "=== Installing GRUB hook ==="
    install_hook

    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "========================================="
    echo " Gdisk installed successfully!"
    echo " Reboot and select 'Gdisk - Multiboot"
    echo " Manager' from the GRUB boot menu."
    echo "========================================="
}

# ── Update ──
do_update() {
    if [ ! -d "$GDISK_DIR/.git" ]; then
        echo "Error: Gdisk is not installed at $GDISK_DIR."
        echo "Run 'install' first."
        exit 1
    fi

    echo "=== Pulling latest Gdisk ==="
    cd "$GDISK_DIR" && git checkout -- . && git pull

    echo ""
    echo "=== Rewriting paths ==="
    rewrite_paths "$GDISK_DIR"

    # Ensure hook is still in place
    if [ ! -x "$GRUB_D_DIR/99-gdisk" ]; then
        install_hook
    fi

    echo ""
    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "Done. Gdisk has been updated."
}

# ── Remove ──
do_remove() {
    echo "=== Removing Gdisk ==="

    if [ -f "$GRUB_D_DIR/99-gdisk" ]; then
        rm -f "$GRUB_D_DIR/99-gdisk"
        echo "Removed GRUB hook."
    fi

    if [ -d "$GDISK_DIR" ]; then
        rm -rf "$GDISK_DIR"
        echo "Removed $GDISK_DIR"
    fi

    echo ""
    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "Done. Gdisk has been removed."
}

# ── Main ──
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
        echo "  install  - Clone Gdisk, rewrite paths, add GRUB entry"
        echo "  update   - Pull latest Gdisk, re-apply path rewrites"
        echo "  remove   - Remove Gdisk and clean GRUB"
        exit 0
        ;;
esac
