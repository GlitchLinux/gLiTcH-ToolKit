#!/bin/bash
# gdisk-grub-patch.sh - Add/remove Gdisk from the host system's GRUB boot menu
#
# Usage:
#   sudo ./gdisk-grub-patch.sh install   - Clone Gdisk to /boot/gdisk, rewrite paths,
#                                           rebuild EFI with Gdisk modules, add GRUB entry
#   sudo ./gdisk-grub-patch.sh update    - Pull latest Gdisk and refresh everything
#   sudo ./gdisk-grub-patch.sh remove    - Remove Gdisk from GRUB and restore original EFI
#
# Requirements: git, python3, grub-mkimage, grub (update-grub or grub2-mkconfig)
# License: GPLv3

set -e

GDISK_DIR="/boot/gdisk"
GRUB_D_DIR=""
UPDATE_GRUB=""
EFI_DIR=""
EFI_DISTRO=""

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

# ── Detect EFI setup ──
detect_efi() {
    if [ ! -d /boot/efi/EFI ] && [ ! -d /efi/EFI ]; then
        echo "  No EFI partition found - skipping EFI rebuild (BIOS-only system)."
        return 1
    fi

    local efi_base="/boot/efi/EFI"
    [ -d "$efi_base" ] || efi_base="/efi/EFI"

    # Find the distro's EFI directory (debian, ubuntu, fedora, etc.)
    for d in "$efi_base"/*/; do
        local name
        name=$(basename "$d")
        [ "$name" = "BOOT" ] && continue
        if [ -f "$d/grubx64.efi" ]; then
            EFI_DIR="$d"
            EFI_DISTRO="$name"
            return 0
        fi
    done

    # Fallback to BOOT
    if [ -f "$efi_base/BOOT/grubx64.efi" ]; then
        EFI_DIR="$efi_base/BOOT"
        EFI_DISTRO="BOOT"
        return 0
    fi

    echo "  No grubx64.efi found in EFI partition - skipping EFI rebuild."
    return 1
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

# ── Rebuild EFI binary with Gdisk's a1ive GRUB modules ──
# This replaces grubx64.efi with one built from Gdisk's patched module set,
# so insmod map/ntboot/vhd/wimboot/grubfm all work in UEFI mode.
# The original is backed up and can be restored with 'remove'.
rebuild_efi() {
    if ! detect_efi; then
        return 0
    fi

    if ! command -v grub-mkimage >/dev/null 2>&1 && ! command -v grub2-mkimage >/dev/null 2>&1; then
        echo "  Warning: grub-mkimage not found - cannot rebuild EFI. Gdisk UEFI features may not work."
        return 0
    fi

    local mkimage="grub-mkimage"
    command -v grub-mkimage >/dev/null 2>&1 || mkimage="grub2-mkimage"

    local gdisk_moddir="$GDISK_DIR/boot/grub/x86_64-efi"
    if [ ! -d "$gdisk_moddir" ]; then
        echo "  Warning: Gdisk x86_64-efi module directory not found - skipping EFI rebuild."
        return 0
    fi

    local original_efi="$EFI_DIR/grubx64.efi"
    local backup_efi="$EFI_DIR/grubx64.efi.bak-pre-gdisk"

    # Backup original if not already backed up
    if [ ! -f "$backup_efi" ]; then
        echo "  Backing up original EFI: $original_efi -> $backup_efi"
        cp "$original_efi" "$backup_efi"
    fi

    # Detect root filesystem UUID for the embedded config
    local root_uuid
    root_uuid=$(grub-probe --target=fs_uuid / 2>/dev/null || findmnt -no UUID /)

    if [ -z "$root_uuid" ]; then
        echo "  Warning: Could not detect root UUID - skipping EFI rebuild."
        return 0
    fi

    # Write embedded config that finds root and sets prefix to Gdisk's module path
    local embed_cfg="/tmp/gdisk-embed.cfg"
    cat > "$embed_cfg" << EOF
search.fs_uuid $root_uuid root
set prefix=(\$root)/boot/gdisk/boot/grub
configfile \$prefix/grub.cfg
EOF

    # Also write a fallback that chains to the host's normal grub.cfg
    # in case Gdisk's config isn't found
    cat > /tmp/gdisk-embed-full.cfg << EOF
search.fs_uuid $root_uuid root

# Try Gdisk's module path first for insmod
set prefix=(\$root)/boot/gdisk/boot/grub

# But load the host's normal grub.cfg (which includes the 99-gdisk hook)
# so the user sees the normal boot menu with Gdisk as an option
if [ -f (\$root)/boot/grub/grub.cfg ]; then
    configfile (\$root)/boot/grub/grub.cfg
elif [ -f (\$root)/boot/grub2/grub.cfg ]; then
    configfile (\$root)/boot/grub2/grub.cfg
fi
EOF

    # Core modules to embed (must be in the image, not loaded from disk)
    local core_mods="normal configfile search search_fs_uuid part_gpt part_msdos fat ext2 echo"

    echo "  Building new grubx64.efi with Gdisk modules (root UUID: $root_uuid)..."

    "$mkimage" \
        -O x86_64-efi \
        -d "$gdisk_moddir" \
        -o /tmp/gdisk-grubx64.efi \
        -c /tmp/gdisk-embed-full.cfg \
        -p "/boot/gdisk/boot/grub" \
        $core_mods 2>&1

    if [ ! -f /tmp/gdisk-grubx64.efi ]; then
        echo "  Error: grub-mkimage failed. Original EFI preserved."
        return 1
    fi

    echo "  Installing new grubx64.efi to $EFI_DIR/"
    cp /tmp/gdisk-grubx64.efi "$original_efi"

    # Also update BOOT fallback if it exists and is separate
    if [ "$EFI_DISTRO" != "BOOT" ] && [ -f "$(dirname "$EFI_DIR")/BOOT/grubx64.efi" ]; then
        local boot_backup="$(dirname "$EFI_DIR")/BOOT/grubx64.efi.bak-pre-gdisk"
        if [ ! -f "$boot_backup" ]; then
            cp "$(dirname "$EFI_DIR")/BOOT/grubx64.efi" "$boot_backup"
        fi
        cp /tmp/gdisk-grubx64.efi "$(dirname "$EFI_DIR")/BOOT/grubx64.efi"
        echo "  Also updated BOOT/grubx64.efi"
    fi

    # Cleanup
    rm -f /tmp/gdisk-grubx64.efi /tmp/gdisk-embed.cfg /tmp/gdisk-embed-full.cfg

    echo "  EFI rebuilt. Original backed up as grubx64.efi.bak-pre-gdisk"
    echo "  All Gdisk UEFI modules (map, ntboot, vhd, wimboot, etc.) are now available."
}

# ── Restore original EFI binary ──
restore_efi() {
    if ! detect_efi; then
        return 0
    fi

    local backup_efi="$EFI_DIR/grubx64.efi.bak-pre-gdisk"

    if [ -f "$backup_efi" ]; then
        echo "  Restoring original EFI: $backup_efi -> $EFI_DIR/grubx64.efi"
        cp "$backup_efi" "$EFI_DIR/grubx64.efi"
        rm -f "$backup_efi"
    fi

    # Restore BOOT fallback too
    if [ "$EFI_DISTRO" != "BOOT" ]; then
        local boot_backup="$(dirname "$EFI_DIR")/BOOT/grubx64.efi.bak-pre-gdisk"
        if [ -f "$boot_backup" ]; then
            cp "$boot_backup" "$(dirname "$EFI_DIR")/BOOT/grubx64.efi"
            rm -f "$boot_backup"
            echo "  Restored BOOT/grubx64.efi"
        fi
    fi

    echo "  Original EFI binary restored."
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
    echo "=== Rebuilding EFI ==="
    rebuild_efi

    echo ""
    echo "=== Installing GRUB hook ==="
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

    echo ""
    echo "=== Rebuilding EFI ==="
    rebuild_efi

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

    echo ""
    echo "=== Restoring EFI ==="
    restore_efi

    if [ -d "$GDISK_DIR" ]; then
        rm -rf "$GDISK_DIR"
        echo "Removed $GDISK_DIR"
    fi

    echo ""
    echo "Updating GRUB configuration..."
    $UPDATE_GRUB

    echo ""
    echo "Done. Gdisk has been removed and original EFI restored."
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
        echo "  install  - Clone Gdisk, rewrite paths, rebuild EFI, add GRUB entry"
        echo "  update   - Pull latest Gdisk, re-apply patches, rebuild EFI"
        echo "  remove   - Remove Gdisk, restore original EFI, clean GRUB"
        exit 0
        ;;
esac
