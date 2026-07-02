#!/bin/bash
# Snapshot EVERYTHING from user x to /etc/skel (except .cache, .ssh, .bash_history)

set -e

SOURCE_USER="x"
SOURCE_HOME="/home/$SOURCE_USER"
SKEL_DIR="/etc/skel"

echo "════════════════════════════════════════════════════════"
echo "SNAPSHOTTING GLITCH LINUX USER CONFIGURATION"
echo "════════════════════════════════════════════════════════"
echo ""

if [ ! -d "$SOURCE_HOME" ]; then
    echo "[ERROR] User home not found: $SOURCE_HOME"
    exit 1
fi

if [ $EUID -ne 0 ]; then
    echo "[ERROR] Must run as root (sudo)"
    exit 1
fi

echo "[1/3] Backing up current /etc/skel..."
if [ -d "$SKEL_DIR" ]; then
    cp -r "$SKEL_DIR" "/etc/skel.backup.$(date +%s)"
    rm -rf "$SKEL_DIR"
fi
mkdir -p "$SKEL_DIR"

echo "[2/3] Copying ALL user configs from /home/$SOURCE_USER..."

# Copy everything from source home
cp -r "$SOURCE_HOME"/* "$SKEL_DIR/" 2>/dev/null || true
cp -r "$SOURCE_HOME"/.* "$SKEL_DIR/" 2>/dev/null || true

# Remove only the per-user stuff
echo "  Removing per-user runtime data..."
rm -rf "$SKEL_DIR/.cache"              # Temporary cache
rm -rf "$SKEL_DIR/.ssh"                # SSH keys (security!)
rm -f "$SKEL_DIR/.bash_history"        # Per-user shell history
rm -f "$SKEL_DIR/.Xauthority"          # X11 session auth (regenerated per login)
rm -f "$SKEL_DIR/.viminfo"             # Vim runtime data
rm -f "$SKEL_DIR/.lesshst"             # Less history
rm -f "$SKEL_DIR/.recently-used.xbel"  # Recent files

# Keep everything else:
# ✓ .config/ (all application settings including KDE/Plasma)
# ✓ .local/ (themes, icons, fonts, application data)
# ✓ .bashrc, .profile (shell config)
# ✓ .gtkrc, .Xresources (theming)
# ✓ .themes, .icons, .fonts (system appearance)
# ✓ Desktop, Downloads (user folders - with Glitch structure)
# ✓ etc.

echo "[3/3] Setting correct permissions..."
chown -R root:root "$SKEL_DIR"
chmod 755 "$SKEL_DIR"

# Fix permissions on all files/dirs
find "$SKEL_DIR" -type f -exec chmod 644 {} \;
find "$SKEL_DIR" -type d -exec chmod 755 {} \;

# Make shell scripts executable
find "$SKEL_DIR" -name "*.sh" -type f -exec chmod 755 {} \; 2>/dev/null || true
[ -d "$SKEL_DIR/.local/bin" ] && find "$SKEL_DIR/.local/bin" -type f -exec chmod 755 {} \; 2>/dev/null || true

echo ""
echo "════════════════════════════════════════════════════════"
echo "[✓] SNAPSHOT COMPLETE"
echo "════════════════════════════════════════════════════════"
echo ""
echo "Summary:"
echo "  Source: $SOURCE_HOME"
echo "  Destination: $SKEL_DIR"
echo ""
echo "Total size copied:"
du -sh "$SKEL_DIR" | awk '{print "  " $1 " of user x configuration"}'
echo ""
echo "Included (Glitch Linux defaults):"
echo "  ✓ .config/ (all KDE/Plasma settings, app configs)"
echo "  ✓ .local/ (themes, icons, fonts, app data)"
echo "  ✓ .bashrc, .profile (shell configuration)"
echo "  ✓ .gtkrc-2.0, .Xresources (theming)"
echo "  ✓ .themes, .icons, .fonts (visual assets)"
echo "  ✓ Desktop, Downloads (user structure)"
echo "  ✓ All dotfiles and configurations"
echo ""
echo "EXCLUDED (per-user only):"
echo "  ✗ .bash_history (shell history)"
echo "  ✗ .cache (temporary runtime cache)"
echo "  ✗ .ssh (private SSH keys)"
echo "  ✗ .Xauthority (X11 session auth)"
echo ""
echo "Test with:"
echo "  sudo useradd -m testuser"
echo "  su - testuser"
echo "  # New user should have EXACT Glitch Linux appearance and config"
