#!/bin/bash
# quick-convert - Fast CLI image converter
# Usage: ./quick-convert [target_format] [source_file]
#        ./quick-convert  (interactive mode)

RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

die() { echo -e "${RED}✗ $1${NC}" >&2; exit 1; }

command -v convert &>/dev/null || die "ImageMagick not installed. Install: sudo apt install imagemagick"

convert_image() {
    local src="$1" fmt="$2"
    [[ -f "$src" ]] || die "File not found: $src"

    local dir base target
    dir="$(dirname "$src")"
    base="$(basename "$src" | sed 's/\.[^.]*$//')"
    target="${dir}/${base}.${fmt}"

    [[ "$src" == "$target" ]] && die "Source and target are the same file"

    echo -e "${CYAN}› converting ${src}${NC}"
    echo -e "${CYAN}› to ${target}${NC}"

    if convert "$src" "$target" 2>/dev/null; then
        echo -e "${GREEN}✓ converted ${base}.${fmt} ($(du -h "$target" | cut -f1))${NC}"
    else
        die "Conversion failed. Format '${fmt}' may not be supported for this input."
    fi
}

# --- Flag mode ---
if [[ $# -ge 2 ]]; then
    fmt="${1,,}"   # lowercase
    src="$2"
    convert_image "$src" "$fmt"
    exit 0
fi

# --- Interactive mode ---
echo -e "${YELLOW}quick-convert${NC} — image format converter"
echo ""

read -rep "$(echo -e "${CYAN}› enter path of source file: ${NC}")" src
[[ -z "$src" ]] && die "No source file provided"
src="${src/#\~/$HOME}"

read -rep "$(echo -e "${CYAN}› enter target file type: ${NC}")" fmt
[[ -z "$fmt" ]] && die "No target format provided"
fmt="${fmt,,}"
fmt="${fmt#.}"   # strip leading dot if user typed ".jpg"

echo ""
convert_image "$src" "$fmt"
