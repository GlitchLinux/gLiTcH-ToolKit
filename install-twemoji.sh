#!/usr/bin/env bash
# install-twemoji.sh - install Twemoji as the system-wide default emoji font
set -euo pipefail

FONT_URL="https://github.com/Sav22999/emoji/raw/refs/heads/master/font/twemoji.ttf"
TMP_FILE="/tmp/twemoji.ttf"
FONT_DIR="/usr/local/share/fonts/twemoji"
CONF_FILE="/etc/fonts/conf.d/60-twemoji-default.conf"

if [[ $EUID -eq 0 ]]; then SUDO=""; else SUDO="sudo"; fi

for cmd in curl fc-scan fc-cache fc-match; do
  command -v "$cmd" >/dev/null || { echo "Missing: $cmd (install curl and fontconfig)"; exit 1; }
done

echo "[1/5] Downloading to $TMP_FILE"
curl -fL --retry 3 -o "$TMP_FILE" "$FONT_URL"

echo "[2/5] Verifying font"
[[ -s "$TMP_FILE" ]] || { echo "Downloaded file is empty"; exit 1; }
FAMILY="$(fc-scan --format '%{family[0]}' "$TMP_FILE" 2>/dev/null || true)"
[[ -n "$FAMILY" ]] || { echo "Not a valid font file: $TMP_FILE"; exit 1; }
echo "    Font family: $FAMILY"

echo "[3/5] Installing to $FONT_DIR"
$SUDO mkdir -p "$FONT_DIR"
$SUDO mv -f "$TMP_FILE" "$FONT_DIR/twemoji.ttf"
$SUDO chmod 644 "$FONT_DIR/twemoji.ttf"

echo "[4/5] Writing fontconfig default: $CONF_FILE"
$SUDO tee "$CONF_FILE" >/dev/null <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "fonts.dtd">
<fontconfig>
  <!-- Use Twemoji for the generic emoji family -->
  <alias binding="strong">
    <family>emoji</family>
    <prefer><family>${FAMILY}</family></prefer>
  </alias>
  <!-- Skip Noto Color Emoji so Twemoji is picked during fallback -->
  <selectfont>
    <rejectfont>
      <glob>*NotoColorEmoji*</glob>
    </rejectfont>
  </selectfont>
</fontconfig>
EOF

echo "[5/5] Rebuilding font cache"
$SUDO fc-cache -f "$FONT_DIR"
$SUDO fc-cache -f >/dev/null

echo
echo "Result:"
echo "  fc-match emoji -> $(fc-match emoji)"
echo "Restart your browser and GUI apps to pick up the change."
