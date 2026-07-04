#!/bin/bash

# Setup xterm .Xresources configuration
# Creates ~/.Xresources with vibrant neon xterm settings
# Merges resources into X database with xrdb

set -e

XRESOURCES_FILE="$HOME/.Xresources"
BACKUP_FILE="$HOME/.Xresources.backup.$(date +%s)"

# Backup existing .Xresources if it exists
if [[ -f "$XRESOURCES_FILE" ]]; then
    echo "[*] Backing up existing .Xresources to $BACKUP_FILE"
    cp "$XRESOURCES_FILE" "$BACKUP_FILE"
fi

# Write xterm configuration to .Xresources
echo "[*] Writing xterm configuration to $XRESOURCES_FILE"
cat > "$XRESOURCES_FILE" << 'EOF'
! Font settings
xterm*faceName: Monospace Bold
xterm*faceSize: 15
! Cursor settings
xterm*cursorBlink: true
xterm*cursorUnderLine: true
xterm*cursorColor: #FF00D8
xterm*pointerColor: #FF00D8
xterm*cursorColorForeground: #FF00D8
! Geometry
xterm*geometry: 70x20
! Disable audible bell
xterm*bellIsUrgent: false
xterm*visualBell: false
xterm*bellSuppressTime: 0
! Scrollbar
xterm*scrollBar: false
! Selection colors
xterm*highlightSelection: true
xterm*selectToClipboard: true
xterm*highlightColor: #ffffff
xterm*foreground: #ffffff
xterm*background: #000000
! Copy/Paste with Ctrl+Shift+C/V
xterm*VT100.translations: #override \
  Ctrl Shift <Key>C: copy-selection(CLIPBOARD) \n\
  Ctrl Shift <Key>V: insert-selection(CLIPBOARD) \n\
  Ctrl <Key>plus: larger-vt-font() \n\
  Ctrl <Key>minus: smaller-vt-font() \n\
  Ctrl <Key>equal: set-vt-font(d)
! Vibrant Neon Color Palette
! Black - xterm*color0:
xterm*color0:  #000000
! Bright Red - xterm*color1:
xterm*color1:  #FF0000
! Neon Green - xterm*color2:
xterm*color2:  #00FF00
! Neon Green (Alt) - xterm*color3:
xterm*color3:  #00FF00
! Electric Blue - xterm*color4:
xterm*color4:  #0000FF
! Hot Magenta - xterm*color5:
xterm*color5:   #FF00D8
! Electric Cyan - xterm*color6:
xterm*color6:  #00FFFF
! Light Gray - xterm*color7:
xterm*color7:  #C0C0C0
! Dark Gray - xterm*color8:
xterm*color8:  #808080
! Coral Red - xterm*color9:
xterm*color9:  #FF6B6B
! Neon Green (Bright) - xterm*color10:
xterm*color10: #00FF0B
! Bright Yellow - xterm*color11:
xterm*color11: #FF00D8
! Hot Pink - xterm*color12:
xterm*color12: #FF00D8
! Bright Magenta - xterm*color13:
xterm*color13: #FF00D8
! Bright Cyan - xterm*color14:
xterm*color14: #FF00D8
! White - xterm*color15:
xterm*color15: #FFFFFF
EOF

# Merge resources into X database
if command -v xrdb &>/dev/null; then
    echo "[*] Loading resources with xrdb..."
    xrdb -merge "$XRESOURCES_FILE"
    echo "[✓] xterm resources loaded successfully"
else
    echo "[!] Warning: xrdb not found. Install x11-utils or xorg package"
    echo "[!] You can manually load with: xrdb -merge ~/.Xresources"
fi

# Verify .Xresources was written
if [[ -f "$XRESOURCES_FILE" ]]; then
    echo "[✓] Configuration written to $XRESOURCES_FILE"
    echo ""
    echo "Setup complete! Your xterm will now use these settings:"
    echo "  - 70x20 geometry"
    echo "  - Monospace Bold, 15pt font"
    echo "  - Neon magenta cursor (#FF00D8)"
    echo "  - Vibrant color palette"
    echo "  - Ctrl+Shift+C/V for copy/paste"
    echo ""
    echo "New xterm windows will use these settings immediately."
    echo "Restart existing xterm windows for changes to take effect."
    [[ -f "$BACKUP_FILE" ]] && echo "Previous config backed up to: $BACKUP_FILE"
else
    echo "[!] Error: Failed to write $XRESOURCES_FILE"
    exit 1
fi
