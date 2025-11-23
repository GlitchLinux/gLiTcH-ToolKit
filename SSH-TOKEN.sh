#!/bin/bash

set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

TOKEN_URL="https://glitchlinux.wtf/FILES/SSH-TOKEN/SSH-TOKEN-2MB.img"
TOKEN_FILE="/tmp/SSH-TOKEN-2MB.img"
TOKEN_MOUNT="/media/token-mount"
SSH_DIR_X="/home/x/.ssh"
SSH_DIR_ROOT="/root/.ssh"

# Check if running with sudo privileges
if [ "$EUID" -ne 0 ]; then 
    echo -e "${YELLOW}This script requires sudo privileges${NC}"
    exec sudo bash "$0" "$@"
fi

# Function to cleanup on exit
cleanup() {
    echo -e "${YELLOW}[*] Cleaning up...${NC}"
    
    # Unmount if mounted
    if mountpoint -q "$TOKEN_MOUNT" 2>/dev/null; then
        echo -e "${YELLOW}[*] Unmounting $TOKEN_MOUNT${NC}"
        umount "$TOKEN_MOUNT" || true
    fi
    
    # Close LUKS device if open
    if [ -e "/dev/mapper/luks-token" ]; then
        echo -e "${YELLOW}[*] Closing LUKS device${NC}"
        cryptsetup close luks-token || true
    fi
    
    # Remove temporary mount points
    [ -d "$TOKEN_MOUNT" ] && rmdir "$TOKEN_MOUNT" 2>/dev/null || true
    
    echo -e "${GREEN}[✓] Cleanup complete${NC}"
}

trap cleanup EXIT

# Step 1: Download token image
echo -e "${YELLOW}[1/7] Downloading SSH token image...${NC}"
if [ -f "$TOKEN_FILE" ]; then
    echo -e "${YELLOW}[!] $TOKEN_FILE already exists, skipping download${NC}"
else
    if ! wget -q --show-progress "$TOKEN_URL" -O "$TOKEN_FILE"; then
        echo -e "${RED}[✗] Failed to download token image${NC}"
        exit 1
    fi
    echo -e "${GREEN}[✓] Downloaded to $TOKEN_FILE${NC}"
fi

# Step 2: Create mount point
echo -e "${YELLOW}[2/7] Creating mount point...${NC}"
mkdir -p "$TOKEN_MOUNT" || true
echo -e "${GREEN}[✓] Mount point ready${NC}"

# Step 3: Open LUKS device with passphrase prompt
echo -e "${YELLOW}[3/7] Opening LUKS encrypted device...${NC}"
if ! cryptsetup open "$TOKEN_FILE" luks-token; then
    echo -e "${RED}[✗] Failed to open LUKS device (incorrect passphrase?)${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] LUKS device opened${NC}"

# Step 4: Mount ext2 partition
echo -e "${YELLOW}[4/7] Mounting ext2 partition...${NC}"
if ! mount /dev/mapper/luks-token "$TOKEN_MOUNT"; then
    echo -e "${RED}[✗] Failed to mount partition${NC}"
    exit 1
fi
echo -e "${GREEN}[✓] Mounted at $TOKEN_MOUNT${NC}"

# Step 5: List and verify contents
echo -e "${YELLOW}[5/7] Contents in token image:${NC}"
ls -lah "$TOKEN_MOUNT/" || echo -e "${YELLOW}[!] Could not list contents${NC}"

# Step 6: Import SSH files for user x
echo -e "${YELLOW}[6/7] Importing SSH files for user x...${NC}"

mkdir -p "$SSH_DIR_X"
chown x:x "$SSH_DIR_X"
chmod 700 "$SSH_DIR_X"

# Copy all files from token to x/.ssh and set permissions
for file in "$TOKEN_MOUNT"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        dest_file="$SSH_DIR_X/$filename"
        
        echo -e "${YELLOW}[*] Copying $filename to $SSH_DIR_X${NC}"
        cp "$file" "$dest_file"
        chown x:x "$dest_file"
        
        # Set appropriate permissions based on filename
        case "$filename" in
            id_rsa|id_ed25519)
                chmod 600 "$dest_file"
                echo -e "${GREEN}[✓] $filename (600)${NC}"
                ;;
            *.pub|known_hosts*|authorized_keys)
                chmod 644 "$dest_file"
                echo -e "${GREEN}[✓] $filename (644)${NC}"
                ;;
            ssh.sh)
                chmod 755 "$dest_file"
                echo -e "${GREEN}[✓] $filename (755)${NC}"
                ;;
            *)
                chmod 644 "$dest_file"
                echo -e "${GREEN}[✓] $filename (644)${NC}"
                ;;
        esac
    fi
done

echo -e "${GREEN}[✓] User x SSH files imported${NC}"

# Step 7: Import SSH files for root
echo -e "${YELLOW}[7/7] Importing SSH files for root...${NC}"

mkdir -p "$SSH_DIR_ROOT"
chmod 700 "$SSH_DIR_ROOT"

# Copy all files from token to root/.ssh and set permissions
for file in "$TOKEN_MOUNT"/*; do
    if [ -f "$file" ]; then
        filename=$(basename "$file")
        
        # Skip ssh.sh for root
        if [ "$filename" = "ssh.sh" ]; then
            continue
        fi
        
        dest_file="$SSH_DIR_ROOT/$filename"
        
        echo -e "${YELLOW}[*] Copying $filename to $SSH_DIR_ROOT${NC}"
        cp "$file" "$dest_file"
        
        # Set appropriate permissions based on filename
        case "$filename" in
            id_rsa|id_ed25519)
                chmod 600 "$dest_file"
                echo -e "${GREEN}[✓] $filename (600)${NC}"
                ;;
            *.pub|known_hosts*|authorized_keys)
                chmod 644 "$dest_file"
                echo -e "${GREEN}[✓] $filename (644)${NC}"
                ;;
            *)
                chmod 644 "$dest_file"
                echo -e "${GREEN}[✓] $filename (644)${NC}"
                ;;
        esac
    fi
done

echo -e "${GREEN}[✓] Root SSH files imported${NC}"

echo ""
echo -e "${GREEN}[✓] All SSH files imported successfully${NC}"
echo -e "${YELLOW}[*] User x .ssh contents:${NC}"
ls -lah "$SSH_DIR_X/" || true
echo ""
echo -e "${YELLOW}[*] Root .ssh contents:${NC}"
ls -lah "$SSH_DIR_ROOT/" || true

sleep 3
clear
bash /home/x/ssh.sh
