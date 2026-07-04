#!/bin/bash
#=========================================================
# Universal Archiver Script
# Author: x (GlitchLinux)
# Description:
#   Archives a directory into .zip, .tar, .tar.gz, .7z, or .rar
#=========================================================

set -e  # Exit on any error

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m' # No color

# Get directory from argument or prompt
if [[ -z "$1" ]]; then
    echo -e "${YELLOW}Enter path to directory:${NC}"
    read -r DIR
else
    DIR="$1"
fi

# Check if directory exists
if [[ ! -d "$DIR" ]]; then
    echo -e "${RED}Error: Directory not found: $DIR${NC}"
    exit 1
fi

# Normalize path
DIR=$(realpath "$DIR")
BASENAME=$(basename "$DIR")
PARENTDIR=$(dirname "$DIR")

# Ask user for archive type
echo -e "${YELLOW}Select archive type: .zip .tar .tar.gz .7z .rar${NC}"
read -r ARCH_TYPE

# Normalize input
ARCH_TYPE=$(echo "$ARCH_TYPE" | tr '[:upper:]' '[:lower:]')
case "$ARCH_TYPE" in
    zip) ARCH_EXT=".zip" ;;
    ".zip") ARCH_EXT=".zip" ;;
    tar) ARCH_EXT=".tar" ;;
    ".tar") ARCH_EXT=".tar" ;;
    tar.gz|tgz|".tar.gz") ARCH_EXT=".tar.gz" ;;
    7z|".7z") ARCH_EXT=".7z" ;;
    rar|".rar") ARCH_EXT=".rar" ;;
    *)
        echo -e "${RED}Unsupported archive type: $ARCH_TYPE${NC}"
        exit 1
        ;;
esac

OUT_FILE="$PARENTDIR/$BASENAME$ARCH_EXT"

# Function to display progress for tar & zip
progress() {
    local CMD="$1"
    echo -e "${GREEN}Archiving: $DIR -> $OUT_FILE${NC}"
    "$CMD" | pv -p -t -e -b >/dev/null
    echo -e "${GREEN}Archive complete!${NC}"
}

# Ensure pv is installed for progress bar
if ! command -v pv &>/dev/null; then
    echo -e "${YELLOW}[!] 'pv' not found. Installing...${NC}"
    sudo apt install -y pv
fi

# Archive based on type
case "$ARCH_EXT" in
    .zip)
        echo -e "${GREEN}Archiving: $DIR -> $OUT_FILE${NC}"
        cd "$PARENTDIR"
        zip -r "$OUT_FILE" "$BASENAME"
        ;;
    .tar)
        echo -e "${GREEN}Archiving: $DIR -> $OUT_FILE${NC}"
        tar -cf "$OUT_FILE" -C "$PARENTDIR" "$BASENAME"
        ;;
    .tar.gz)
        echo -e "${GREEN}Archiving: $DIR -> $OUT_FILE${NC}"
        tar -czf "$OUT_FILE" -C "$PARENTDIR" "$BASENAME"
        ;;
    .7z)
        echo -e "${GREEN}Archiving: $DIR -> $OUT_FILE${NC}"
        7z a -y "$OUT_FILE" "$DIR"
        ;;
    .rar)
        echo -e "${GREEN}Archiving: $DIR -> $OUT_FILE${NC}"
        rar a -y "$OUT_FILE" "$DIR"
        ;;
esac

# Show resulting archive
echo -e "${YELLOW}Resulting archive:${NC} $OUT_FILE"
ls -lh "$OUT_FILE"
