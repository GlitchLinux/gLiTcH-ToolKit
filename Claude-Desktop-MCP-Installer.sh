#!/bin/bash

#######################################################################
# Claude Desktop + MCP SSH Bootstrap (LUKS Container Edition)
# Downloads encrypted LUKS container, mounts it, and runs installer
#######################################################################

set -e

IMG_URL="https://glitchlinux.wtf/claude-cloud/MCP-container.img"
IMG_FILE="/tmp/MCP-container.img"
MAPPER_NAME="mcpcrypt"
MAPPER_DEV="/dev/mapper/$MAPPER_NAME"
WORKDIR="/tmp/MCP"

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

echo ""
echo "â•”â•â•â•â••â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•â•—"
echo "â•‘  Claude Desktop + MCP SSH Bootstrap (LUKS)   â•‘"
echo "â•‘  Version 1.0 - gLiTcH Server Edition         â•‘"
echo "â•šâ•â•â•â•â•â•â•â•â•â•â•â•â•â•ââ•â•â•â••â•â•â•â•â•"
echo ""

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

# Run installer
echo "[5/5] Running installer..."
echo ""
cd "$WORKDIR"
sudo bash ./MCP-autoinstaller.sh

echo ""
echo ""
echo "âœ“ Installer complete. Container will be unmounted and closed."
echo ""
echo ""
