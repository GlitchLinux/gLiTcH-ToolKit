#!/bin/bash
#=========================================================
# gLiTcH-ToolKit :: Unarchiver Installer
# Author: x (GlitchLinux)
#=========================================================

set -e  # Exit on any error

# Ask for sudo at start
if [[ $EUID -ne 0 ]]; then
    echo "This installer requires sudo privileges."
    sudo -v || { echo "Sudo required. Exiting."; exit 1; }
fi

# Deoendencies
sudo apt update && sudo apt install unzip p7zip-full tar -y

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No color

# Download URL
URL="https://raw.githubusercontent.com/GlitchLinux/gLiTcH-ToolKit/refs/heads/main/unarchiver.sh"
DEST="/usr/local/bin/unarchiver"

echo -e "${YELLOW}[*] Installing Unarchiver...${NC}"

# Download script
sudo curl -fsSL "$URL" -o "$DEST" || {
    echo -e "${RED}[!] Failed to download from $URL${NC}"
    exit 1
}

# Set permissions
sudo chmod +x "$DEST"
sudo chmod 777 "$DEST"

echo -e "${GREEN}[+] Unarchiver installed successfully!${NC}"
echo -e "${YELLOW}[*] Location:${NC} $DEST"

# Run script (interactive if no arguments)
echo -e "${GREEN}[*] Running unarchiver now...${NC}\n"
bash "$DEST"
