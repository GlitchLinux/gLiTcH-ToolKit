#!/bin/bash

# Setup passwordless sudo for current user
# Creates /etc/sudoers.d entry with proper validation

set -e

if [[ $EUID -ne 0 ]]; then
    echo "[!] Error: This script must be run as root"
    exit 1
fi

SUDO_USER="${SUDO_USER:-${USER}}"
SUDOERS_FILE="/etc/sudoers.d/${SUDO_USER}-nopass"

echo "[*] Setting up passwordless sudo for: $SUDO_USER"

# Backup existing sudoers.d if it exists
if [[ -f "$SUDOERS_FILE" ]]; then
    echo "[*] Backing up existing sudoers entry..."
    cp "$SUDOERS_FILE" "${SUDOERS_FILE}.backup.$(date +%s)"
fi

# Write sudoers entry
echo "[*] Writing passwordless sudo entry..."
cat > "$SUDOERS_FILE" << EOF
# Passwordless sudo for $SUDO_USER
$SUDO_USER ALL=(ALL) NOPASSWD:ALL
EOF

# Set proper permissions (must be 0440)
chmod 0440 "$SUDOERS_FILE"

# Validate sudoers syntax
echo "[*] Validating sudoers syntax..."
if visudo -cf "$SUDOERS_FILE" > /dev/null 2>&1; then
    echo "[✓] Syntax valid"
else
    echo "[!] ERROR: Invalid sudoers syntax!"
    rm "$SUDOERS_FILE"
    exit 1
fi

echo "[✓] Passwordless sudo enabled for: $SUDO_USER"
echo ""
echo "Entry created: $SUDOERS_FILE"
echo "Permissions: 0440"
echo ""
echo "Verify with: sudo -l"
