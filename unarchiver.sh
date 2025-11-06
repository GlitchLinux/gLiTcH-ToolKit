#!/bin/bash
#=========================================================
# Universal Unarchiver Script
# Author: x (GlitchLinux)
# Description:
#   Extracts .zip, .tar, .tar.gz, .7z, .rar, .iso, .img files
#   into a folder with the same base name as the archive.
#=========================================================

# Exit on errors
set -e

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No color

# Check if a file argument was passed, otherwise prompt
if [[ -z "$1" ]]; then
    echo -e "${YELLOW}Enter path to file:${NC}"
    read -r FILE
else
    FILE="$1"
fi

# Check file existence
if [[ ! -f "$FILE" ]]; then
    echo -e "${RED}Error: File not found: $FILE${NC}"
    exit 1
fi

# Extract directory and base name
DIR="$(dirname "$FILE")"
BASENAME="$(basename "$FILE")"
NAME="${BASENAME%.*}"
OUT_DIR="$DIR/$NAME"

# Create output directory
mkdir -p "$OUT_DIR"

# Determine file type and extract
echo -e "${GREEN}Extracting $BASENAME to $OUT_DIR...${NC}"

case "$FILE" in
    *.zip)
        unzip -q "$FILE" -d "$OUT_DIR"
        ;;
    *.tar)
        tar -xf "$FILE" -C "$OUT_DIR"
        ;;
    *.tar.gz|*.tgz)
        tar -xzf "$FILE" -C "$OUT_DIR"
        ;;
    *.7z)
        7z x -y "$FILE" -o"$OUT_DIR" >/dev/null
        ;;
    *.rar)
        unrar x -y "$FILE" "$OUT_DIR" >/dev/null
        ;;
    *.iso)
        # Mount ISO temporarily and copy contents
        MNT_DIR=$(mktemp -d)
        sudo mount -o loop "$FILE" "$MNT_DIR" >/dev/null 2>&1
        cp -r "$MNT_DIR"/* "$OUT_DIR"/
        sudo umount "$MNT_DIR"
        rmdir "$MNT_DIR"
        ;;
    *.img)
        # Try auto-mounting IMG file (loopback)
        MNT_DIR=$(mktemp -d)
        sudo mount -o loop "$FILE" "$MNT_DIR" >/dev/null 2>&1
        cp -r "$MNT_DIR"/* "$OUT_DIR"/
        sudo umount "$MNT_DIR"
        rmdir "$MNT_DIR"
        ;;
    *)
        echo -e "${RED}Unsupported file type: $FILE${NC}"
        exit 1
        ;;
esac

echo -e "${GREEN}Extraction complete!${NC}"
echo -e "${YELLOW}Contents of $OUT_DIR:${NC}"
ls "$OUT_DIR"
