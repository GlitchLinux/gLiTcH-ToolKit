#!/bin/bash

# ╭─────────────────────────────────╮
# │ ❖ Interactive QCOW2 Generator ❖ │
# │ https://github.com/GlitchLinux  │
# ╰─────────────────────────────────╯

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Clear screen
clear

echo -e "${BLUE}╭─────────────────────────────────╮${NC}"
echo -e "${BLUE}│ ❖ Interactive QCOW2 Generator ❖ │${NC}"
echo -e "${BLUE}│ https://github.com/GlitchLinux  │${NC}"
echo -e "${BLUE}╰─────────────────────────────────╯${NC}"
echo ""

# Check if qemu-img is installed
if ! command -v qemu-img &> /dev/null; then
    echo -e "${RED}✗ QEMU not found. Install: sudo apt install qemu-utils${NC}"
    exit 1
fi

while true; do
    # Get save path
    echo -ne "${YELLOW}> Enter save path:${NC} "
    read -r SAVE_PATH
    
    # Validate path
    SAVE_DIR=$(dirname "$SAVE_PATH")
    if [[ ! -d "$SAVE_DIR" ]]; then
        echo -e "${RED}✗ Directory does not exist: $SAVE_DIR${NC}"
        continue
    fi
    
    if [[ -f "$SAVE_PATH" ]]; then
        echo -ne "${YELLOW}⚠ File exists. Overwrite? (y/n):${NC} "
        read -r OVERWRITE
        if [[ ! "$OVERWRITE" =~ ^[Yy]$ ]]; then
            continue
        fi
    fi
    
    break
done

while true; do
    # Get image size
    echo -ne "${YELLOW}> Enter image size (e.g., 50G, 1T, 256M):${NC} "
    read -r IMAGE_SIZE
    
    # Basic validation
    if [[ ! "$IMAGE_SIZE" =~ ^[0-9]+[GMK]$ ]]; then
        echo -e "${RED}✗ Invalid format. Use: 50G, 1T, 256M${NC}"
        continue
    fi
    
    break
done

# Summary
echo ""
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}BUILDING: ${IMAGE_SIZE} QCOW2 IMAGE${NC}"
echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "Path: ${YELLOW}$SAVE_PATH${NC}"
echo -e "Size: ${YELLOW}$IMAGE_SIZE${NC}"
echo ""

# Confirmation
echo -ne "${YELLOW}> Confirm? (y/n):${NC} "
read -r CONFIRM
if [[ ! "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "${RED}✗ Cancelled${NC}"
    exit 0
fi

echo ""

# Create QCOW2 with progress
echo -e "${BLUE}[ Creating QCOW2 image... ]${NC}"
if qemu-img create -f qcow2 "$SAVE_PATH" "$IMAGE_SIZE" 2>&1; then
    echo ""
    echo -e "${GREEN}✓ QCOW2 SUCCESSFULLY GENERATED${NC}"
    echo -e "${GREEN}✓ Saved as: $SAVE_PATH${NC}"
    
    # Show file info
    FILE_SIZE=$(du -h "$SAVE_PATH" | cut -f1)
    VIRT_SIZE=$(qemu-img info "$SAVE_PATH" 2>/dev/null | grep "virtual disk size" | awk '{print $NF}')
    
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
    echo -e "Host disk usage: ${YELLOW}$FILE_SIZE${NC}"
    echo -e "Virtual size:    ${YELLOW}$VIRT_SIZE${NC}"
    echo -e "${BLUE}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
else
    echo -e "${RED}✗ Failed to create QCOW2 image${NC}"
    exit 1
fi

echo ""

# Generate again?
while true; do
    echo -ne "${YELLOW}> Generate another image? (y/n):${NC} "
    read -r AGAIN
    
    if [[ "$AGAIN" =~ ^[Yy]$ ]]; then
        echo ""
        exec "$0"
    elif [[ "$AGAIN" =~ ^[Nn]$ ]]; then
        echo -e "${GREEN}✓ Goodbye!${NC}"
        exit 0
    else
        echo -e "${RED}✗ Enter y or n${NC}"
    fi
done
