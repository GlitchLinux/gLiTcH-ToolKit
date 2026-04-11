#!/bin/bash
# ╔═════════════════════════════════════════════════════════════════╗
# ║  vDiskChain Setup - Boot raw disk images as bare metal OS       ║
# ║  https://github.com/ventoy/vdiskchain                           ║
# ║                                                                 ║
# ║  Installs vdiskchain bootloader files into an existing GRUB     ║
# ║  installation and generates boot entries for .vtoy disk images. ║
# ║                                                                 ║
# ║  Usage: sudo ./vdiskchain-setup.sh                              ║
# ║         (interactive — prompts for all paths)                   ║
# ╚═════════════════════════════════════════════════════════════════╝

set -e

# ── Colors ──────────────────────────────────────────────────────────
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

info()  { echo -e "${CYAN}[INFO]${NC}  $1"; }
ok()    { echo -e "${GREEN}[OK]${NC}    $1"; }
warn()  { echo -e "${YELLOW}[WARN]${NC}  $1"; }
err()   { echo -e "${RED}[ERROR]${NC} $1"; }
step()  { echo -e "\n${BOLD}${CYAN}── $1 ──${NC}"; }

prompt() {
    local msg="$1" default="$2" reply
    if [[ -n "$default" ]]; then
        echo -en "${BOLD}${msg}${NC} ${DIM}[${default}]${NC}: " >&2
    else
        echo -en "${BOLD}${msg}${NC}: " >&2
    fi
    read -r reply
    echo "${reply:-$default}"
}

# ── Root check ──────────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (sudo)"
    exit 1
fi

# ── Banner ──────────────────────────────────────────────────────────
echo ""
echo -e "${BOLD}${CYAN}╔══════════════════════════════════════════════════════╗${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${BOLD}vDiskChain Setup${NC}                                    ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}║${NC}  Boot raw disk images (.vtoy) as bare metal OS       ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}║${NC}  ${DIM}https://github.com/ventoy/vdiskchain${NC}                ${BOLD}${CYAN}║${NC}"
echo -e "${BOLD}${CYAN}╚══════════════════════════════════════════════════════╝${NC}"
echo ""

# ═══════════════════════════════════════════════════════════════════
# PROMPT 1: Target GRUB directory
# ═══════════════════════════════════════════════════════════════════
step "Step 1/5 — Select target GRUB directory"

echo ""
info "This is the path to the GRUB installation where vdiskchain"
info "will be installed. It must contain a grub.cfg file."
echo ""
echo -e "  ${DIM}Examples:${NC}"
echo -e "  ${DIM}  /mnt/usb/boot/grub      (USB drive)${NC}"
echo -e "  ${DIM}  /boot/grub              (local system)${NC}"
echo -e "  ${DIM}  /media/x/ROOT/boot/grub (mounted partition)${NC}"
echo ""

while true; do
    GRUB_DIR=$(prompt "Enter path to GRUB directory" "")

    # Strip trailing slash
    GRUB_DIR="${GRUB_DIR%/}"

    if [[ -z "$GRUB_DIR" ]]; then
        err "No path entered"
        continue
    fi

    if [[ ! -d "$GRUB_DIR" ]]; then
        err "Directory not found: $GRUB_DIR"
        continue
    fi

    if [[ ! -f "$GRUB_DIR/grub.cfg" ]]; then
        err "No grub.cfg found in $GRUB_DIR"
        err "This doesn't appear to be a valid GRUB directory"
        continue
    fi

    ok "Valid GRUB directory: $GRUB_DIR"
    break
done

# Resolve the boot partition root
# e.g., /mnt/usb/boot/grub -> /mnt/usb
BOOT_ROOT=""
if [[ "$(basename "$(dirname "$GRUB_DIR")")" == "boot" ]]; then
    BOOT_ROOT="$(dirname "$(dirname "$GRUB_DIR")")"
else
    BOOT_ROOT="$(dirname "$GRUB_DIR")"
fi

info "Boot partition root: $BOOT_ROOT"

# ═══════════════════════════════════════════════════════════════════
# PROMPT 2: Disk image (.vtoy) file(s)
# ═══════════════════════════════════════════════════════════════════
step "Step 2/5 — Select disk image(s)"

echo ""
info "Provide the full path to each .img.vtoy disk image file."
info "The file MUST have the .vtoy extension (required by vdiskchain)."
info ""
info "The path stored in the boot config will be relative to the"
info "partition root, so vdiskchain can find it at boot time."
echo ""
echo -e "  ${DIM}Examples:${NC}"
echo -e "  ${DIM}  /mnt/data/GLITCH-KDE-25GB.img.vtoy${NC}"
echo -e "  ${DIM}  /media/x/VDISK-SHELF/debian-12.img.vtoy${NC}"
echo ""

declare -a VTOY_PATHS=()        # relative paths (for grub config)
declare -a VTOY_DISPLAY=()      # display names (for menu entries)
declare -a VTOY_FULLPATHS=()    # full paths (for verification)

while true; do
    if [[ ${#VTOY_PATHS[@]} -gt 0 ]]; then
        echo ""
        info "${#VTOY_PATHS[@]} image(s) added so far"
    fi

    VTOY_INPUT=$(prompt "Enter full path to .vtoy disk image (or 'done')" "")

    # Check for done/exit
    if [[ "${VTOY_INPUT,,}" == "done" || "${VTOY_INPUT,,}" == "d" ]]; then
        if [[ ${#VTOY_PATHS[@]} -eq 0 ]]; then
            warn "No images added yet"
            echo -en "  Continue without images? (y/n): "
            read -r yn
            [[ "${yn,,}" == "y" ]] && break
            continue
        fi
        break
    fi

    # Validate the file
    if [[ -z "$VTOY_INPUT" ]]; then
        continue
    fi

    if [[ ! -f "$VTOY_INPUT" ]]; then
        err "File not found: $VTOY_INPUT"
        continue
    fi

    if [[ "$VTOY_INPUT" != *.vtoy ]]; then
        err "File must have .vtoy extension"
        warn "Rename it:  mv \"$(basename "$VTOY_INPUT")\" \"$(basename "$VTOY_INPUT").vtoy\""
        continue
    fi

    # Get file size
    file_size=$(stat -c%s "$VTOY_INPUT" 2>/dev/null || echo 0)
    file_size_human=$(numfmt --to=iec "$file_size" 2>/dev/null || echo "${file_size}B")

    # Determine the mount point of the partition containing this file
    vtoy_mount=$(df "$VTOY_INPUT" --output=target 2>/dev/null | tail -1)
    vtoy_dev=$(df "$VTOY_INPUT" --output=source 2>/dev/null | tail -1)

    # Calculate the relative path from partition root
    rel_path="${VTOY_INPUT#$vtoy_mount}"

    # Generate a display name from the filename
    vtoy_basename=$(basename "$VTOY_INPUT")
    display_name=$(echo "$vtoy_basename" | sed 's/\.vtoy$//; s/\.img$//; s/[-_]/ /g')

    echo ""
    info "File:       $VTOY_INPUT ($file_size_human)"
    info "Partition:  $vtoy_dev mounted at $vtoy_mount"
    info "Boot path:  vdisk=${rel_path}"
    info "Menu name:  ${display_name}"
    echo ""

    # Let user customize the display name
    custom_name=$(prompt "  Menu entry name" "$display_name")
    display_name="$custom_name"

    VTOY_PATHS+=("$rel_path")
    VTOY_DISPLAY+=("$display_name")
    VTOY_FULLPATHS+=("$VTOY_INPUT")

    ok "Added: ${display_name} → vdisk=${rel_path}"
done

echo ""
info "${#VTOY_PATHS[@]} disk image(s) selected"

# ═══════════════════════════════════════════════════════════════════
# STEP 3: Download vdiskchain release
# ═══════════════════════════════════════════════════════════════════
step "Step 3/5 — Downloading vdiskchain"

TMPDIR=$(mktemp -d /tmp/vdiskchain-setup.XXXXXX)
trap "rm -rf $TMPDIR" EXIT

SKIP_DOWNLOAD=""

# Check if binaries already exist on the target
if [[ -f "$BOOT_ROOT/vdiskchain" ]]; then
    info "vdiskchain binary already exists at $BOOT_ROOT/vdiskchain"
    echo -en "  ${BOLD}Re-download and overwrite? (y/n)${NC} [n]: "
    read -r overwrite
    if [[ "${overwrite,,}" != "y" ]]; then
        ok "Keeping existing vdiskchain binaries"
        SKIP_DOWNLOAD=true
    fi
fi

if [[ "${SKIP_DOWNLOAD}" != "true" ]]; then
    RELEASE_URL="https://github.com/ventoy/vdiskchain/releases/download/v1.3/vdiskchain-1.3.tar.gz"

    info "Downloading vdiskchain v1.3 release..."
    if command -v wget &>/dev/null; then
        wget -q --show-progress -O "$TMPDIR/vdiskchain-1.3.tar.gz" "$RELEASE_URL"
    elif command -v curl &>/dev/null; then
        curl -sL -o "$TMPDIR/vdiskchain-1.3.tar.gz" "$RELEASE_URL"
    else
        err "Neither wget nor curl found — cannot download"
        exit 1
    fi

    tar xzf "$TMPDIR/vdiskchain-1.3.tar.gz" -C "$TMPDIR"
    ok "Release v1.3 downloaded and extracted"

    # Locate and verify binaries
    EFI_BIN="$TMPDIR/vdiskchain-1.3/vdiskchain"
    BIOS_KRN="$TMPDIR/vdiskchain-1.3/ipxe.krn"

    if [[ ! -f "$EFI_BIN" ]]; then
        err "Could not find vdiskchain EFI binary in release"
        err "Download manually from: https://github.com/ventoy/vdiskchain/releases"
        exit 1
    fi

    if ! file "$EFI_BIN" | grep -q "PE32+.*EFI"; then
        err "vdiskchain binary is not a valid EFI application"
        exit 1
    fi
    ok "Found vdiskchain EFI binary: $(file -b "$EFI_BIN")"

    if [[ -f "$BIOS_KRN" ]]; then
        ok "Found iPXE BIOS kernel:     $(file -b "$BIOS_KRN")"
    else
        warn "iPXE BIOS kernel not found — BIOS boot entries will be skipped"
        BIOS_KRN=""
    fi

    # Install binaries
    info "Installing boot files..."
    cp "$EFI_BIN" "$BOOT_ROOT/vdiskchain"
    chmod 644 "$BOOT_ROOT/vdiskchain"
    ok "Installed: $BOOT_ROOT/vdiskchain (EFI chainloader)"

    if [[ -n "$BIOS_KRN" ]]; then
        cp "$BIOS_KRN" "$BOOT_ROOT/ipxe.krn"
        chmod 644 "$BOOT_ROOT/ipxe.krn"
        ok "Installed: $BOOT_ROOT/ipxe.krn (BIOS boot kernel)"
    fi
else
    # Check if ipxe.krn exists for BIOS entries
    [[ -f "$BOOT_ROOT/ipxe.krn" ]] && BIOS_KRN="exists" || BIOS_KRN=""
fi

# ═══════════════════════════════════════════════════════════════════
# STEP 4: Generate vdiskchain.cfg
# ═══════════════════════════════════════════════════════════════════
step "Step 4/5 — Generating vdiskchain.cfg"

VDISK_CFG="$GRUB_DIR/vdiskchain.cfg"

{
    cat <<'HEADER'
# ╔══════════════════════════════════════════════════════════════════╗
# ║  vDiskChain Boot Menu                                           ║
# ║  Auto-generated - edit manually or re-run vdiskchain-setup.sh   ║
# ║                                                                 ║
# ║  Boot raw disk images (.vtoy) as bare metal operating systems   ║
# ║  https://github.com/ventoy/vdiskchain                          ║
# ╚══════════════════════════════════════════════════════════════════╝

if loadfont /boot/grub/font.pf2 ; then
    set gfxmode=auto
    insmod gfxterm
    terminal_output gfxterm
fi
set timeout=10
set default=0

HEADER

    if [[ ${#VTOY_PATHS[@]} -eq 0 ]]; then
        cat <<'EMPTY'
### No .vtoy images configured — add entries manually below ###
# Example UEFI entry:
#   if [ "${grub_platform}" = "efi" ]; then
#       menuentry "My Linux vDisk" {
#           insmod chain
#           chainloader /vdiskchain vdisk=/path/to/image.img.vtoy
#           boot
#       }
#   fi
#
# Example BIOS entry:
#   if [ "${grub_platform}" = "pc" ]; then
#       menuentry "My Linux vDisk" {
#           linux16 /ipxe.krn vdisk=/path/to/image.img.vtoy
#           initrd16 /vdiskchain
#           boot
#       }
#   fi

EMPTY
    else
        for i in "${!VTOY_PATHS[@]}"; do
            vtoy_path="${VTOY_PATHS[$i]}"
            display_name="${VTOY_DISPLAY[$i]}"

            echo "### ${display_name} ###"

            # UEFI entry
            cat <<EOF
if [ "\${grub_platform}" = "efi" ]; then
    menuentry "${display_name} - vDiskChain" {
        insmod part_msdos
        insmod part_gpt
        insmod chain
        insmod fat
        insmod ntfs
        insmod ext2
        insmod exfat
        chainloader /vdiskchain vdisk=${vtoy_path}
        boot
    }
fi
EOF

            # BIOS entry
            if [[ -n "$BIOS_KRN" ]]; then
                cat <<EOF
if [ "\${grub_platform}" = "pc" ]; then
    menuentry "${display_name} - vDiskChain" {
        insmod part_msdos
        insmod part_gpt
        insmod fat
        insmod ntfs
        insmod ext2
        insmod exfat
        linux16 /ipxe.krn vdisk=${vtoy_path}
        initrd16 /vdiskchain
        boot
    }
fi
EOF
            fi
            echo ""
        done
    fi

    # Return to main menu
    cat <<'FOOTER'
menuentry "← Back to Main Menu" {
    configfile /boot/grub/grub.cfg
}
FOOTER

} > "$VDISK_CFG"

ok "Generated: $VDISK_CFG"
if [[ ${#VTOY_PATHS[@]} -gt 0 ]]; then
    info "  → ${#VTOY_PATHS[@]} disk image(s) configured"
fi

# ═══════════════════════════════════════════════════════════════════
# STEP 5: Hook into main grub.cfg
# ═══════════════════════════════════════════════════════════════════
step "Step 5/5 — Adding submenu to grub.cfg"

GRUB_CFG="$GRUB_DIR/grub.cfg"

if grep -q "vdiskchain.cfg" "$GRUB_CFG" 2>/dev/null; then
    warn "vDiskChain submenu entry already exists in grub.cfg — skipping"
    info "vdiskchain.cfg has been regenerated with updated images"
else
    if grep -q 'menuentry "Shutdown"' "$GRUB_CFG" 2>/dev/null; then
        sed -i '/menuentry "Shutdown"/i \
### vDiskChain - Boot disk images as bare metal OS ###\
menuentry "vDiskChain - Disk Image Booting" {\
    configfile /boot/grub/vdiskchain.cfg\
}\
' "$GRUB_CFG"
        ok "Inserted vDiskChain submenu before Shutdown entry"
    else
        {
            echo ''
            echo '### vDiskChain - Boot disk images as bare metal OS ###'
            echo 'menuentry "vDiskChain - Disk Image Booting" {'
            echo '    configfile /boot/grub/vdiskchain.cfg'
            echo '}'
        } >> "$GRUB_CFG"
        ok "Appended vDiskChain submenu to grub.cfg"
    fi
fi

# ═══════════════════════════════════════════════════════════════════
# Summary
# ═══════════════════════════════════════════════════════════════════
echo ""
step "Setup Complete"
echo ""
echo -e "${BOLD}Installed files:${NC}"
info "  $BOOT_ROOT/vdiskchain          (EFI chainloader)"
[[ -n "$BIOS_KRN" ]] && \
info "  $BOOT_ROOT/ipxe.krn            (BIOS boot kernel)"
info "  $VDISK_CFG"
info "  $GRUB_CFG"
echo ""
if [[ ${#VTOY_PATHS[@]} -gt 0 ]]; then
    echo -e "${BOLD}Configured disk images:${NC}"
    for i in "${!VTOY_PATHS[@]}"; do
        info "  ${VTOY_DISPLAY[$i]}"
        info "    → vdisk=${VTOY_PATHS[$i]}"
    done
else
    warn "No images configured."
    info "Edit $VDISK_CFG manually to add boot entries."
fi
echo ""
echo -e "${BOLD}${YELLOW}IMPORTANT:${NC} Disk image files MUST have the ${BOLD}.vtoy${NC} extension!"
echo -e "  ${DIM}Example: mylinux.img.vtoy  or  debian-12.vhd.vtoy${NC}"
echo ""
info "To add more images later, re-run:"
info "  sudo $0"
echo ""
ok "Ready to boot! Select 'vDiskChain - Disk Image Booting' from the GRUB menu."
