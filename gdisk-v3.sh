#!/bin/bash
# ====================================================================
#  gdisk-v2.sh  -  Gdisk v2.0 Download ~ Install ~ Repair
# --------------------------------------------------------------------
#  Deploys the Gdisk v2 multiboot GRUB utility to a disk or partition
#  of the user's choice, with selectable FAT32 size, while preserving
#  the custom a1ive-patched GRUB core.img (map/wimboot) boot chain.
#
#  Three operations:
#    1. Create  - wipe a whole disk, new MBR table + sized FAT32,
#                 extract Gdisk files, install patched BIOS+UEFI boot.
#    2. Update  - install/refresh Gdisk onto an EXISTING partition
#                 (keeps the partition, refreshes files + boot chain).
#    3. Repair  - reinstall MBR core.img and/or UEFI BOOTX64.EFI on an
#                 existing Gdisk device without touching user data.
#
#  Boot chain is installed from the PREBUILT patched core
#  (core-patched.img) via grub-bios-setup - never regenerated, so the
#  custom modules survive. Mirrors Grub2-Patch.sh patch_bios() logic.
#
#  Source: https://github.com/GlitchLinux  (GPLv3)
# ====================================================================

clear

set -uo pipefail

# Ensure system sbin dirs are on PATH (parted, mkfs.vfat, wipefs etc. live there)
export PATH="/usr/local/sbin:/usr/sbin:/sbin:$PATH"

# -------------------- config --------------------
BASE_URL="https://glitchlinux.wtf/FILES/G-Drive/Gdisk-v2"
ZIP_NAME="Gdisk-v2-Patched.zip"
TAR_NAME="grub-patch.tar.gz"
FAT_LABEL="Gdisk-v3"
WORK_DIR="/tmp/gdisk-v2-$$"
DL_DIR="/tmp/gdisk-v2-dl"
MNT="/tmp/gdisk-v2-mnt-$$"

# -------------------- styling --------------------
RED=$'\e[0;31m'; GRN=$'\e[0;32m'; YLW=$'\e[1;33m'
CYN=$'\e[0;36m'; BOLD=$'\e[1m'; DIM=$'\e[2m'; NC=$'\e[0m'
MAGENTA=$'\033[38;5;198m'; BRIGHT_GREEN=$'\033[0;96m'

# semantic shortcuts
HL="$MAGENTA"          # highlight: names, devices, partitions
ACCENT="$CYN"          # section accent
RULE_COLOR="$DIM$CYN"

# thin rule sized to the terminal (falls back to 60 cols)
rule() {
    local w; w="$(tput cols 2>/dev/null || echo 60)"
    [ "$w" -gt 70 ] && w=70
    printf "${RULE_COLOR}%*s${NC}\n" "$w" '' | tr ' ' '-'
}

msg()  { echo -e "${GRN}[+]${NC} $*"; }
warn() { echo -e "${YLW}[!]${NC} $*"; }
err()  { echo -e "${RED}[x]${NC} $*"; }
info() { echo -e "${CYN}[i]${NC} $*"; }
die()  { err "$*"; cleanup; exit 1; }

# section header used at the top of every operation/picker screen
header() {
    clear
    echo
    echo "${CYN} ${BOLD}Gdisk v2.0${NC} ❖${NC}${CYN} ${BOLD}$*${NC}" | borderize
    echo
}

banner() {
    clear
    echo
    echo "${CYN} ${BOLD}Gdisk v2.0${NC} ❖${NC}${CYN} ${BOLD}Download ~ Install ~ Repair ${NC}" | borderize
    echo
}

# -------------------- cleanup --------------------
cleanup() {
    mountpoint -q "$MNT" 2>/dev/null && umount "$MNT" 2>/dev/null
    rm -rf "$WORK_DIR" 2>/dev/null
    rmdir "$MNT" 2>/dev/null
}
trap cleanup EXIT

# -------------------- root --------------------
[ "$(id -u)" -eq 0 ] || die "Run as root:  sudo $0"

# -------------------- tool checks --------------------
need() {
    local t p found
    for t in "$@"; do
        found=0
        for p in "$t" "/sbin/$t" "/usr/sbin/$t" "/usr/local/sbin/$t"; do
            if command -v "$p" >/dev/null 2>&1; then found=1; break; fi
        done
        [ "$found" -eq 1 ] || die "missing required tool: $t"
    done
}
need parted mkfs.vfat unzip tar dd lsblk blkid partprobe wipefs sync losetup
# grub-bios-setup resolved on demand (may be grub2-bios-setup)
BIOS_SETUP=""
for t in grub-bios-setup grub2-bios-setup; do
    for p in "$t" "/sbin/$t" "/usr/sbin/$t"; do
        command -v "$p" >/dev/null 2>&1 && { BIOS_SETUP="$p"; break 2; }
    done
done

# ====================================================================
#  SOURCE ACQUISITION
# ====================================================================
# Locate the zip + tarball. Priority:
#   1. Same directory as this script
#   2. Already-downloaded copy in $DL_DIR
#   3. Download from $BASE_URL
acquire_sources() {
    local sdir; sdir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"
    mkdir -p "$DL_DIR"

    for f in "$ZIP_NAME" "$TAR_NAME"; do
        if   [ -f "$sdir/$f" ];   then cp -f "$sdir/$f" "$DL_DIR/$f"; info "Using local: ${HL}$f${NC}"
        elif [ -f "$DL_DIR/$f" ]; then info "Cached: ${HL}$f${NC}"
        else
            need wget
            info "Downloading ${HL}$f${NC} ..."
            wget -q --show-progress -O "$DL_DIR/$f.part" "$BASE_URL/$f" \
                || die "download failed: $BASE_URL/$f"
            mv -f "$DL_DIR/$f.part" "$DL_DIR/$f"
            msg "Downloaded: ${HL}$f${NC}"
        fi
    don
    ZIP="$DL_DIR/$ZIP_NAME"
    TAR="$DL_DIR/$TAR_NAME"
    [ -s "$ZIP" ] || die "zip missing/empty: $ZIP"
    [ -s "$TAR" ] || die "tarball missing/empty: $TAR"
}

# extract the grub-patch tarball (has core-patched.img + boot images + modules)
extract_patch() {
    mkdir -p "$WORK_DIR/patch"
    tar xzf "$TAR" -C "$WORK_DIR/patch"
    PATCH_CORE="$WORK_DIR/patch/boot/grub/i386-pc/core-patched.img"
    PATCH_BOOTIMG="$WORK_DIR/patch/boot/grub/i386-pc/boot.img"
    PATCH_I386="$WORK_DIR/patch/boot/grub/i386-pc"
    PATCH_EFIBIN="$WORK_DIR/patch/EFI/BOOT/BOOTX64.EFI"
    PATCH_EFIMODS="$WORK_DIR/patch/boot/grub/x86_64-efi"
    [ -f "$PATCH_CORE" ]   || die "tarball missing core-patched.img"
    [ -f "$PATCH_BOOTIMG" ] || die "tarball missing boot.img"
}

# ====================================================================
#  DEVICE / PARTITION PICKERS
# ====================================================================
pick_disk() {
    header "Select Target Disk"
    echo "  ${BOLD}Available disks:${NC}" >&2
    echo >&2
    # highlight device names in magenta
    lsblk -dpno NAME,SIZE,MODEL,TRAN | grep -vE '/dev/ram' \
        | sed -E "s#^(/dev/[a-zA-Z0-9]+)#  ${HL}\1${NC}#" >&2
    # also surface backing-file loop devices (e.g. mounted .img for testing)
    local lhdr=0 ln
    while read -r ln; do
        [ -z "$ln" ] && continue
        [ "$lhdr" -eq 0 ] && { echo >&2; echo "  ${DIM}loop devices:${NC}" >&2; lhdr=1; }
        echo "  ${HL}$ln${NC}" >&2
    done < <(losetup -ln -O NAME,SIZE,BACK-FILE 2>/dev/null)
    echo >&2
    local d
    read -rp "  Enter target ${HL}DISK${NC} (e.g. /dev/sdf or /dev/loop5): " d
    [ -b "$d" ] || die "not a block device: $d"
    case "$d" in *[0-9]) [[ "$d" =~ loop[0-9]+$ ]] || warn "That looks like a partition, not a whole disk.";; esac
    REPLY_DISK="$d"
}

pick_partition() {
    header "Select Target Partition"
    echo "  ${BOLD}Available partitions:${NC}" >&2
    echo >&2
    lsblk -pno NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT | grep -vE '/dev/ram' \
        | sed -E "s#(/dev/[a-zA-Z0-9]+)#${HL}\1${NC}#" >&2
    echo >&2
    local p
    read -rp "  Enter target ${HL}PARTITION${NC} (e.g. /dev/sdf1): " p
    [ -b "$p" ] || die "not a block device: $p"
    REPLY_PART="$p"
}

# parent disk + partition number from a partition node
resolve_parent() {
    local part="$1"
    local pk; pk="$(lsblk -no PKNAME "$part" | head -n1)"
    [ -n "$pk" ] || die "cannot resolve parent disk of $part"
    PARENT="/dev/$pk"
    PARTNUM="$(grep -oE '[0-9]+$' <<<"$(basename "$part")")"
    [ -n "$PARTNUM" ] || die "cannot parse partition number from $part"
}

confirm_destroy() {
    local tgt="$1"
    echo
    rule
    warn "ALL DATA on ${HL}${BOLD}$tgt${NC}${YLW} will be DESTROYED.${NC}"
    rule
    echo
    local a
    read -rp "  Type ${BOLD}${GRN}YES${NC} to continue: " a
    [ "$a" = "YES" ] || die "aborted by user"
}

unmount_all() {
    local dev="$1" m
    for m in $(lsblk -lnpo NAME "$dev" 2>/dev/null); do
        while mountpoint -q "$(lsblk -no MOUNTPOINT "$m" | head -n1)" 2>/dev/null; do
            umount "$m" 2>/dev/null || break
        done
        umount "$m" 2>/dev/null || true
    done
}

# ====================================================================
#  CORE STEPS
# ====================================================================

# write fresh msdos table + one FAT32 partition of chosen size
make_partition() {
    local disk="$1" size_spec="$2"   # size_spec like "8G" or "MAX"
    msg "Wiping ${HL}$disk${NC}"
    wipefs -a "$disk" >/dev/null 2>&1 || true
    dd if=/dev/zero of="$disk" bs=1M count=8 conv=fsync status=none

    msg "Creating MBR table + FAT32 partition (${HL}${size_spec}${NC})"
    parted -s "$disk" mklabel msdos
    if [ "$size_spec" = "MAX" ]; then
        parted -s "$disk" mkpart primary fat32 1MiB 100%
    else
        parted -s "$disk" mkpart primary fat32 1MiB "$size_spec"
    fi
    parted -s "$disk" set 1 boot on
    parted -s "$disk" set 1 lba on
    partprobe "$disk"; sleep 1

    # partition node (handle /dev/sdX1 vs /dev/nvme0n1p1 vs /dev/loopXp1)
    if [[ "$disk" =~ [0-9]$ ]]; then PART="${disk}p1"; else PART="${disk}1"; fi
    [ -b "$PART" ] || { partprobe "$disk"; sleep 1; }
    [ -b "$PART" ] || die "partition node $PART did not appear"
}

format_fat() {
    local part="$1"
    msg "Formatting ${HL}$part${NC} as FAT32 (label ${HL}$FAT_LABEL${NC})"
    mkfs.vfat -F 32 -n "$FAT_LABEL" "$part" >/dev/null
}

extract_files() {
    local part="$1"
    mkdir -p "$MNT"
    mount "$part" "$MNT" || die "mount $part failed"
    msg "Extracting Gdisk files to ${HL}$part${NC}"

    # The zip wraps everything in a top-level "Gdisk-v2-Patched/" folder.
    # Extract to a staging dir, then move the INNER contents to the FS root.
    local stage="$WORK_DIR/zip-stage"
    rm -rf "$stage"; mkdir -p "$stage"
    unzip -oq "$ZIP" -d "$stage" || die "unzip failed"

    # find the single wrapper dir (fallback: stage itself if already flat)
    local src="$stage"
    local entries; entries=$(ls -A "$stage")
    if [ "$(echo "$entries" | wc -l)" -eq 1 ] && [ -d "$stage/$entries" ]; then
        src="$stage/$entries"
    fi

    cp -a "$src"/. "$MNT"/ || die "copy to partition failed"
    sync
}

# install patched BIOS core.img into post-MBR gap (reuses patch_bios logic)
install_bios_boot() {
    local disk="$1" part="$2"
    [ -n "$BIOS_SETUP" ] || { warn "grub-bios-setup not found (apt install grub-pc-bin) - BIOS boot NOT installed"; return 1; }

    # ensure i386-pc modules + boot images present on the partition
    local moddir="$MNT/boot/grub/i386-pc"
    mkdir -p "$moddir"
    cp -f "$PATCH_I386"/*.mod  "$moddir/" 2>/dev/null || true
    cp -f "$PATCH_I386"/*.lst  "$moddir/" 2>/dev/null || true
    for img in boot.img diskboot.img kernel.img lnxboot.img; do
        [ -f "$PATCH_I386/$img" ] && cp -f "$PATCH_I386/$img" "$moddir/"
    done
    # grub-bios-setup reads boot.img + core.img FROM --directory. Install the
    # PATCHED core under that name so the custom modules are what gets embedded.
    cp -f "$PATCH_CORE" "$moddir/core.img"
    sync

    msg "Installing patched core.img to post-MBR gap via ${HL}$(basename "$BIOS_SETUP")${NC}"
    # Standard grub-bios-setup syntax: --directory holds boot.img + core.img,
    # last positional arg is the target disk. The --core-image flag is NOT
    # portable (absent in mainline grub) - it caused the path-concat error.
    "$BIOS_SETUP" --directory="$moddir" "$disk" \
        || die "grub-bios-setup failed"
    msg "BIOS boot chain installed"
}

# refresh/ensure UEFI binary + modules (just files on the FAT partition)
install_uefi_boot() {
    msg "Installing UEFI ${HL}BOOTX64.EFI${NC} + x86_64-efi modules"
    mkdir -p "$MNT/EFI/BOOT" "$MNT/boot/grub/x86_64-efi"
    [ -f "$PATCH_EFIBIN" ] && cp -f "$PATCH_EFIBIN" "$MNT/EFI/BOOT/BOOTX64.EFI"
    cp -f "$PATCH_EFIMODS"/*.mod "$MNT/boot/grub/x86_64-efi/" 2>/dev/null || true
    cp -f "$PATCH_EFIMODS"/*.lst "$MNT/boot/grub/x86_64-efi/" 2>/dev/null || true
    sync
}

# ====================================================================
#  OPERATIONS
# ====================================================================

op_create() {
    header "Create Gdisk Device"
    info "CREATE - new Gdisk device on a whole disk"
    acquire_sources
    extract_patch
    pick_disk
    local disk="$REPLY_DISK"
    confirm_destroy "$disk"

    # size selection
    header "FAT32 Partition Size"
    echo "  ${BOLD}1.${NC} ${HL}Fill entire disk${NC} ~ recommended"
    echo "  ${BOLD}2.${NC} ${HL}Custom size${NC} ~ e.g. 8G, 16G, 4096M"
    echo
    local s sz
    read -rp "  > " s
    if [ "$s" = "2" ]; then
        echo
        read -rp "  Enter size (e.g. ${HL}8G${NC}): " sz
        [[ "$sz" =~ ^[0-9]+[MGmg]$ ]] || die "invalid size: $sz"
        SIZESPEC="$sz"
    else
        SIZESPEC="MAX"
    fi

    header "Building Gdisk Device"
    unmount_all "$disk"
    make_partition "$disk" "$SIZESPEC"
    format_fat "$PART"
    extract_files "$PART"
    install_uefi_boot
    install_bios_boot "$disk" "$PART"
    finalize "$disk" "$PART"
}

op_update() {
    header "Update Gdisk"
    info "UPDATE - install/refresh Gdisk onto an EXISTING partition"
    acquire_sources
    extract_patch
    pick_partition
    local part="$REPLY_PART"
    resolve_parent "$part"

    local fstype; fstype="$(blkid -o value -s TYPE "$part" 2>/dev/null)"
    case "$fstype" in
        vfat|fat|fat32|msdos) : ;;
        "") warn "no filesystem detected on ${HL}$part${NC}" ;;
        *)  warn "filesystem is '${HL}$fstype${NC}${YLW}', not FAT32 - Gdisk expects FAT32" ;;
    esac

    echo
    warn "Existing files on ${HL}${BOLD}$part${NC}${YLW} are kept; Gdisk files will be added/overwritten.${NC}"
    echo
    read -rp "  Proceed? [${GRN}y${NC}/${RED}N${NC}]: " a
    [[ "$a" =~ ^[Yy]$ ]] || die "aborted"

    header "Updating Gdisk"
    unmount_all "$PARENT"
    [ "$fstype" = "" ] && format_fat "$part"
    extract_files "$part"
    install_uefi_boot
    install_bios_boot "$PARENT" "$part"
    finalize "$PARENT" "$part"
}

op_repair() {
    header "Repair Gdisk"
    info "REPAIR - fix MBR / UEFI boot on an existing Gdisk device"
    acquire_sources
    extract_patch
    pick_partition
    local part="$REPLY_PART"
    resolve_parent "$part"

    header "Repair Target"
    echo "  ${BOLD}1.${NC} ${HL}BIOS${NC} ~ MBR + core.img"
    echo "  ${BOLD}2.${NC} ${HL}UEFI${NC} ~ BOOTX64.EFI + modules"
    echo "  ${BOLD}3.${NC} ${HL}Both${NC} ~ BIOS + UEFI"
    echo
    local r; read -rp "  > " r

    header "Repairing Gdisk"
    unmount_all "$PARENT"
    mkdir -p "$MNT"; mount "$part" "$MNT" || die "mount $part failed"

    case "$r" in
        1) install_bios_boot "$PARENT" "$part" ;;
        2) install_uefi_boot ;;
        3) install_uefi_boot; install_bios_boot "$PARENT" "$part" ;;
        *) die "invalid choice" ;;
    esac
    finalize "$PARENT" "$part"
}

finalize() {
    local disk="$1" part="$2"
    sync
    mountpoint -q "$MNT" && umount "$MNT" 2>/dev/null
    partprobe "$disk" 2>/dev/null || true
    echo
    rule
    msg "${BOLD}Done.${NC}"
    rule
    info "Device : ${HL}$disk${NC}"
    info "Part   : ${HL}$part${NC}  ($(lsblk -no SIZE "$part" 2>/dev/null | tr -d ' '))"
    info "Label  : ${HL}$FAT_LABEL${NC}"
    echo
    echo "  ${BRIGHT_GREEN}${BOLD}Gdisk v2 is ready.${NC} ${GRN}Boot the target in BIOS or UEFI mode.${NC}"
    echo
}

# ====================================================================
#  MENU
# ====================================================================
banner
echo "  ${BOLD}Select Gdisk Operation [1-3]:${NC}"
echo
echo "  ${BOLD}1.${NC} ${MAGENTA}Create Gdisk${NC} ~ Make a new Gdisk Device"
echo "  ${BOLD}2.${NC} ${MAGENTA}Update Gdisk${NC} ~ Update or Install on existing partition."
echo "  ${BOLD}3.${NC} ${MAGENTA}Repair Gdisk${NC} ~ Fix MBR & UEFI Boot on existing Gdisk device."
echo
read -rp "  > " CHOICE
echo

case "$CHOICE" in
    1) op_create ;;
    2) op_update ;;
    3) op_repair ;;
    *) die "invalid choice: $CHOICE" ;;
esac
