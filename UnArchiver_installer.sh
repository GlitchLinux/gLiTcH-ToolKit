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
sudo apt update && sudo apt install unzip p7zip-full tar pv -y
cd /tmp && wget http://ftp.us.debian.org/debian/pool/non-free/r/rar/rar_7.01-1~deb12u1_amd64.deb
sudo dpkg -i rar_7.01-1~deb12u1_amd64.deb

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No color

# Download URL
URL1="https://raw.githubusercontent.com/GlitchLinux/gLiTcH-ToolKit/refs/heads/main/unarchiver.sh"
URL2="https://raw.githubusercontent.com/GlitchLinux/gLiTcH-ToolKit/refs/heads/main/archiver.sh"
DEST1="/usr/local/bin/unarchiver"
DEST2="/usr/local/bin/archiver"

echo -e "${YELLOW}[*] Installing Unarchiver...${NC}"

# Download script
sudo curl -fsSL "$URL1" -o "$DEST1" || {
    echo -e "${RED}[!] Failed to download from $URL1${NC}"
    exit 1
}

sudo curl -fsSL "$URL2" -o "$DEST2" || {
    echo -e "${RED}[!] Failed to download from $URL2${NC}"
    exit 1
}


# Set permissions
sudo chmod +x "$DEST1"
sudo chmod 777 "$DEST1"
sudo chmod +x "$DEST2"
sudo chmod 777 "$DEST2"


echo -e "${GREEN}[+] Archiver & Unarchiver installed successfully!${NC}"
echo -e "${YELLOW}[*] Location:${NC} /usr/local/bin"

echo "Run tools with unarchiver or archiver commands"
echo "Or execute dynamically with:"
echo "archiver [directory]"
echo "unarchiver archive.zip"
