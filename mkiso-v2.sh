#!/bin/bash
# ╔═══════════════════════════════════════════════╗
# ║  mkiso.sh - Create ISO from directory         ║
# ║  Uses xorriso - Saves to parent of source dir ║
# ║  Auto-detects BIOS/EFI boot from boot/grub/   ║
# ║  Auto-detects isolinux BIOS boot              ║
# ╚═══════════════════════════════════════════════╝

set -euo pipefail

# -- Colors --
RED='\033[0;31m'; GREEN='\033[0;32m'; CYAN='\033[0;36m'; YELLOW='\033[1;33m'; NC='\033[0m'

err()  { echo -e "${RED}[ERROR]${NC} $1" >&2; exit 1; }
info() { echo -e "${CYAN}[INFO]${NC} $1"; }
ok()   { echo -e "${GREEN}[OK]${NC} $1"; }
warn() { echo -e "${YELLOW}[WARN]${NC} $1"; }

# -- Dependency check --
command -v xorriso &>/dev/null || err "xorriso not found. Install with: sudo apt install xorriso"

# -- Prompt for source directory --
if [[ -n "${1:-}" ]]; then
    SRC_DIR="$1"
else
    read -rp "$(echo -e "${CYAN}Source directory: ${NC}")" SRC_DIR
fi

# -- Validate --
SRC_DIR="$(realpath -e "$SRC_DIR" 2>/dev/null)" || err "Directory does not exist: ${SRC_DIR:-<empty>}"
[[ -d "$SRC_DIR" ]] || err "Not a directory: $SRC_DIR"
[[ "$(ls -A "$SRC_DIR")" ]] || err "Directory is empty: $SRC_DIR"

# -- Paths --
DIR_NAME="$(basename "$SRC_DIR")"
PARENT_DIR="$(dirname "$SRC_DIR")"
ISO_NAME="${DIR_NAME}.iso"
ISO_PATH="${PARENT_DIR}/${ISO_NAME}"

# -- Conflict check --
if [[ -f "$ISO_PATH" ]]; then
    warn "File already exists: $ISO_PATH"
    read -rp "$(echo -e "${YELLOW}Overwrite? [y/N]: ${NC}")" confirm
    [[ "${confirm,,}" == "y" ]] || { info "Aborted."; exit 0; }
    rm -f "$ISO_PATH"
fi

# -- Volume label --
read -rp "$(echo -e "${CYAN}Volume label [${DIR_NAME}]: ${NC}")" VOL_LABEL
VOL_LABEL="${VOL_LABEL:-$DIR_NAME}"

# -- Auto-detect boot images --
BOOT_OPTS=()
BIOS_FOUND=false

# Check for isolinux BIOS boot (takes priority over GRUB eltorito for BIOS)
ISOLINUX_BIN="isolinux/isolinux.bin"
ISOLINUX_CAT="isolinux/boot.cat"

if [[ -f "${SRC_DIR}/${ISOLINUX_BIN}" ]]; then
    ok "isolinux BIOS boot found: ${ISOLINUX_BIN}"
    BIOS_FOUND=true
    BOOT_OPTS+=(
        -b "$ISOLINUX_BIN"
        -c "$ISOLINUX_CAT"
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
    )
    # Add isohybrid MBR if isohdpfx.bin exists
    if [[ -f "${SRC_DIR}/isolinux/isohdpfx.bin" ]]; then
        ok "isohybrid MBR found: isolinux/isohdpfx.bin"
        BOOT_OPTS+=(
            -isohybrid-mbr "${SRC_DIR}/isolinux/isohdpfx.bin"
        )
    fi
fi

# Check for GRUB eltorito BIOS boot (only if isolinux not found)
BIOS_IMG="boot/grub/eltorito.img"

if [[ "$BIOS_FOUND" == false ]] && [[ -f "${SRC_DIR}/${BIOS_IMG}" ]]; then
    ok "BIOS boot image found: ${BIOS_IMG}"
    BIOS_FOUND=true
    BOOT_OPTS+=(
        -b "$BIOS_IMG"
        -no-emul-boot
        -boot-load-size 4
        -boot-info-table
    )
fi

if [[ "$BIOS_FOUND" == false ]]; then
    warn "No BIOS boot image found (checked isolinux/ and boot/grub/eltorito.img)"
fi

# Check for EFI boot
EFI_IMG="boot/grub/efi.img"

if [[ -f "${SRC_DIR}/${EFI_IMG}" ]]; then
    ok "EFI boot image found: ${EFI_IMG}"
    BOOT_OPTS+=(
        -eltorito-alt-boot
        -e "$EFI_IMG"
        -no-emul-boot
    )
else
    warn "No EFI boot image (${EFI_IMG}) - skipping"
fi

# -- Build ISO --
echo ""
info "Building ISO..."
info "  Source:  $SRC_DIR"
info "  Output:  $ISO_PATH"
info "  Label:   $VOL_LABEL"
echo ""

xorriso -as mkisofs \
    -R -J \
    -joliet-long \
    -V "$VOL_LABEL" \
    ${BOOT_OPTS[@]+"${BOOT_OPTS[@]}"} \
    -o "$ISO_PATH" \
    "$SRC_DIR"

# -- Result --
echo ""
if [[ -f "$ISO_PATH" ]]; then
    ISO_SIZE="$(du -h "$ISO_PATH" | cut -f1)"
    ok "ISO created successfully!"
    info "  Path: $ISO_PATH"
    info "  Size: $ISO_SIZE"
else
    err "ISO creation failed - output file not found"
fi
