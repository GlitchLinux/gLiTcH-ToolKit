#!/bin/bash

set -e

IMG_URL="https://glitchlinux.wtf/claude-cloud/MCP-container.img"
IMG_FILE="/tmp/MCP-container.img"
MAPPER_NAME="LUKS-VAULT"
MAPPER_DEV="/dev/mapper/$MAPPER_NAME"
WORKDIR="/tmp/MCP"

cd /tmp
sudo apt update -y
sudo apt install nodejs npm -y
wget https://glitchlinux.wtf/claude-cloud/claude-desktop_0.14.10_amd64.deb
sudo dpkg -i claude-desktop_0.14.10_amd64.deb
sudo apt install -f

# Cleanup function
cleanup() {
    echo ""
    echo "Cleaning up..."
    
    # Change out of mounted directory first
    cd /tmp 2>/dev/null || true
    
    # Give processes time to release files
    sleep 1
    
    # Unmount with retries
    if mountpoint -q "$WORKDIR" 2>/dev/null; then
        echo " - unmounting $WORKDIR"
        for i in {1..3}; do
            if sudo umount "$WORKDIR" 2>/dev/null; then
                echo "   unmounted successfully"
                break
            fi
            [ $i -lt 3 ] && sleep 1
        done
    fi
    
    # Close LUKS mapper with retries
    if [ -b "$MAPPER_DEV" ]; then
        echo " - closing LUKS mapper $MAPPER_NAME"
        for i in {1..3}; do
            if sudo cryptsetup luksClose "$MAPPER_NAME" 2>/dev/null; then
                echo "   closed successfully"
                break
            fi
            [ $i -lt 3 ] && sleep 1
        done
    fi
    
    # Detach loop device
    if [ -n "$LOOP_DEV" ] && losetup "$LOOP_DEV" >/dev/null 2>&1; then
        echo " - detaching loop device $LOOP_DEV"
        sudo losetup -d "$LOOP_DEV" 2>/dev/null || true
    fi
    
    # Remove workdir
    [ -d "$WORKDIR" ] && sudo rmdir "$WORKDIR" 2>/dev/null || true
    
    echo "Cleanup complete."
}

trap cleanup EXIT

# Download LUKS container
echo "[1/5] Downloading encrypted container..."
if ! wget -q "$IMG_URL" -O "$IMG_FILE"; then
    echo "âœ— Failed to download container"
    exit 1
fi
echo "âœ“ Container downloaded"
echo ""

# Attach loop device
echo "[2/5] Setting up loop device..."
LOOP_DEV=$(sudo losetup -f)
sudo losetup "$LOOP_DEV" "$IMG_FILE"
echo "âœ“ Loop device: $LOOP_DEV"
echo ""

# Open LUKS container
echo "[3/5] Opening LUKS container..."
echo "Enter LUKS passphrase:"
if ! sudo cryptsetup luksOpen "$LOOP_DEV" "$MAPPER_NAME"; then
    echo "âœ— Failed to open LUKS container (wrong passphrase?)"
    exit 1
fi
echo "âœ“ Container opened"
echo ""

# Mount to workdir
sleep 0.5
mkdir -p "$WORKDIR"
echo "[4/5] Mounting container..."
if ! sudo mount "$MAPPER_DEV" "$WORKDIR"; then
    echo "âœ— Failed to mount container"
    exit 1
fi
echo "âœ“ Mounted to $WORKDIR"
echo ""
echo ""
cd "$WORKDIR" && sudo cp MCP-Setup-Files.tar.gz /home/x/Desktop && cd /home/x/Desktop
tar -xvzf MCP-Setup-Files.tar.gz

echo -n "Starting Installation in "
for i in {5..1}; do
    echo -n "$i "
    sleep 1
done

echo    # newline after countdown
./Install-NOT-as-ROOT.sh

read -p "Hit enter to finish!"

sudo rm -f claude_desktop_config.json
sudo rm -f id_rsa
sudo rm -f id_rsa.pub
sudo rm -f Install-NOT-as-ROOT.sh
sudo rm -f /tmp/MCP-container.img
sudo rm -f MCP-Setup-Files.tar.gz
sudo rm -f README.md
sudo rm -f /tmp/claude-desktop_0.14.10_amd64.deb

exit
exit
