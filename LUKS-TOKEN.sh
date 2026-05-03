#!/bin/bash
# ╔══════════════════════════════════════════════════════╗
# ║           LUKS TOKEN KEY MANAGER                     ║
# ║  Downloads, auto-deletes, unlocks, and mounts a      ║
# ║  LUKS-encrypted .img token file                      ║
# ╚══════════════════════════════════════════════════════╝

set -euo pipefail

# ─── Config ───────────────────────────────────────────
TOKEN_URL="https://glitchlinux.wtf/FILES/LUKS-TOKEN/LUKS-TOKEN.img"
TOKEN_IMG="/tmp/LUKS-TOKEN.img"
RAW_IMG_MOUNT_POINT="/tmp/token-mount"
DECRYPTED_VOLUME_MOUNT="/mnt/LUKS-TOKEN.img"
LUKS_NAME="LUKS-TOKEN"
AUTO_DELETE_SCRIPT="/tmp/autodelete-token.sh"
AUTO_DELETE_DELAY=500

# ─── Colors ───────────────────────────────────────────
RED='\033[0;31m'
GRN='\033[0;32m'
YLW='\033[1;33m'
CYN='\033[0;36m'
BLD='\033[1m'
RST='\033[0m'

log()    { echo -e "${CYN}[*]${RST} $*"; }
ok()     { echo -e "${GRN}[✓]${RST} $*"; }
warn()   { echo -e "${YLW}[!]${RST} $*"; }
die()    { echo -e "${RED}[✗]${RST} $*" >&2; exit 1; }

# ─── 1. Download token image ──────────────────────────
echo ""
echo -e "${BLD}╔══════════════════════════════════╗${RST}"
echo -e "${BLD}║     LUKS Token Key Manager       ║${RST}"
echo -e "${BLD}╚══════════════════════════════════╝${RST}"
echo ""

log "Downloading LUKS token image..."

if [[ -f "$TOKEN_IMG" ]]; then
    warn "Existing token found — overwriting: $TOKEN_IMG"
    sudo rm -f "$TOKEN_IMG"
fi

if ! wget -q --show-progress -O "$TOKEN_IMG" "$TOKEN_URL"; then
    die "Download failed. Check URL or network connectivity."
fi
ok "Token downloaded to $TOKEN_IMG"

# ─── 2. Auto-delete launcher ──────────────────────────
log "Setting up auto-delete (${AUTO_DELETE_DELAY}s timer)..."

cat > "$AUTO_DELETE_SCRIPT" << EOF
#!/bin/bash
sleep ${AUTO_DELETE_DELAY}
sudo rm -f "${TOKEN_IMG}"
sudo rm -f "${AUTO_DELETE_SCRIPT}"
# Also attempt cleanup of mounts if still open
sudo umount "${DECRYPTED_VOLUME_MOUNT}" 2>/dev/null || true
sudo umount "${RAW_IMG_MOUNT_POINT}" 2>/dev/null || true
sudo cryptsetup luksClose "${LUKS_NAME}" 2>/dev/null || true
sudo rmdir "${DECRYPTED_VOLUME_MOUNT}" 2>/dev/null || true
sudo rmdir "${RAW_IMG_MOUNT_POINT}" 2>/dev/null || true
EOF

chmod +x "$AUTO_DELETE_SCRIPT"
sudo bash "$AUTO_DELETE_SCRIPT" &
AUTODEL_PID=$!
ok "Auto-delete running as PID ${AUTODEL_PID} (fires in ${AUTO_DELETE_DELAY}s)"
warn "Token and mounts will be wiped automatically in ${AUTO_DELETE_DELAY} seconds!"

# ─── 3. Passphrase prompt & LUKS unlock ───────────────
echo ""
log "Preparing mount points..."
sudo mkdir -p "$RAW_IMG_MOUNT_POINT"
sudo mkdir -p "$DECRYPTED_VOLUME_MOUNT"

# Set up loop device for the raw img
LOOP_DEV=$(sudo losetup --find --show "$TOKEN_IMG")
ok "Loop device: $LOOP_DEV"

# Close any leftover LUKS mapping with this name
if sudo cryptsetup status "$LUKS_NAME" &>/dev/null; then
    warn "Old LUKS mapping found — closing it..."
    sudo cryptsetup luksClose "$LUKS_NAME" || true
fi

echo ""
log "Enter LUKS passphrase to unlock token:"
ATTEMPTS=0
MAX_ATTEMPTS=3

while [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; do
    if sudo cryptsetup luksOpen "$LOOP_DEV" "$LUKS_NAME"; then
        ok "LUKS volume unlocked successfully."
        break
    else
        ATTEMPTS=$((ATTEMPTS + 1))
        REMAINING=$((MAX_ATTEMPTS - ATTEMPTS))
        if [[ $ATTEMPTS -lt $MAX_ATTEMPTS ]]; then
            warn "Wrong passphrase. ${REMAINING} attempt(s) remaining."
        else
            # Clean up loop device before exiting
            sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
            die "Too many failed attempts. Aborting."
        fi
    fi
done

# ─── 4. Mount decrypted volume ────────────────────────
log "Mounting decrypted volume at ${DECRYPTED_VOLUME_MOUNT}..."

if ! sudo mount "/dev/mapper/$LUKS_NAME" "$DECRYPTED_VOLUME_MOUNT"; then
    # Fallback: try mounting as read-only
    warn "Standard mount failed — trying read-only..."
    sudo mount -o ro "/dev/mapper/$LUKS_NAME" "$DECRYPTED_VOLUME_MOUNT" \
        || { sudo cryptsetup luksClose "$LUKS_NAME"; sudo losetup -d "$LOOP_DEV"; die "Mount failed."; }
fi

ok "Mounted at: ${DECRYPTED_VOLUME_MOUNT}"

# ─── 5. Open file manager ─────────────────────────────
echo ""
log "Opening file manager at mount point..."

# Try common file managers in order of preference
FM_OPENED=false
for FM in xdg-open thunar nautilus nemo pcmanfm dolphin; do
    if command -v "$FM" &>/dev/null; then
        "$FM" "$DECRYPTED_VOLUME_MOUNT" &>/dev/null &
        ok "Opened with: $FM"
        FM_OPENED=true
        break
    fi
done

if [[ "$FM_OPENED" == false ]]; then
    warn "No graphical file manager found."
    log "Browse manually: ls ${DECRYPTED_VOLUME_MOUNT}"
fi

# ─── Summary ──────────────────────────────────────────
echo ""
echo -e "${BLD}─────────────────────────────────────${RST}"
echo -e "${GRN}  Token mounted and ready${RST}"
echo -e "  Path:        ${CYN}${DECRYPTED_VOLUME_MOUNT}${RST}"
echo -e "  Loop device: ${CYN}${LOOP_DEV}${RST}"
echo -e "  LUKS map:    ${CYN}/dev/mapper/${LUKS_NAME}${RST}"
echo -e "  Auto-wipe:   ${YLW}${AUTO_DELETE_DELAY}s from now (PID ${AUTODEL_PID})${RST}"
echo -e "${BLD}─────────────────────────────────────${RST}"
echo ""
warn "To manually close early:"
echo -e "  ${CYN}sudo umount ${DECRYPTED_VOLUME_MOUNT} && sudo cryptsetup luksClose ${LUKS_NAME} && sudo losetup -d ${LOOP_DEV}${RST}"
echo ""
