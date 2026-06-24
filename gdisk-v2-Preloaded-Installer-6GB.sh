#!/bin/bash
# ====================================================================
#  gdisk-v2.sh  -  Gdisk v2.0 Preloaded Install (6GB+)
# --------------------------------------------------------------------
#  Deploys the Gdisk v2 multiboot GRUB utility to a disk or partition
#  of the user's choice, with selectable FAT32 size, while preserving
#  the custom a1ive-patched GRUB core.img (map/wimboot) boot chain.
#
#  This is the PRELOADED installer - downloads and installs the full
#  6GB+ Gdisk image with all included ISOs/WIMs/VTOYs.
#
#  Three operations:
#    1. Create  - wipe a whole disk, new MBR table + sized FAT32,
#                 extract Gdisk files, install patched BIOS+UEFI boot.
#    2. Update  - install/refresh Gdisk onto an EXISTING partition
#                 (keeps the partition, refreshes files + boot chain).
#    3. Repair  - reinstall MBR core.img and/or UEFI BOOTX64.EFI on an
#                 existing Gdisk device without touching user data.
#
#  Download path selection (for the 6GB+ zip):
#    - 8GB+ RAM available  -> /tmp (tmpfs / fast)
#    - Otherwise           -> /home/.gdisk-install/
#    - No space at /home   -> format target first, download to target
#    - No space anywhere   -> offer core (100MB) installer fallback
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
ZIP_NAME="Gdisk-v2-Patched-6.1GB.zip"
TAR_NAME="grub-patch.tar.gz"
FAT_LABEL="GDISK-V2"
WORK_DIR="/tmp/gdisk-v2-$$"
MNT="/tmp/gdisk-v2-mnt-$$"

# Size thresholds (bytes)
ZIP_SIZE_NEEDED=$((7 * 1024 * 1024 * 1024))   # ~7GB headroom for zip + extraction
RAM_THRESHOLD=$((8 * 1024 * 1024))             # 8GB in KB (for /proc/meminfo)
CORE_INSTALLER_URL="https://raw.githubusercontent.com/GlitchLinux/gLiTcH-ToolKit/refs/heads/main/gdisk-v2.sh"

# These get set dynamically by resolve_download_path()
DL_DIR=""
DL_MODE=""   # "tmp", "home", "target", or "fallback"

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
    echo "${CYN} ${BOLD}Gdisk v2.0${NC} ~${NC}${CYN}${BOLD} Preloaded Install ~ 6GB ${NC}" | borderize
    echo
    info "$*"
    echo
}

banner() {
    clear
    echo
    echo "${CYN} ${BOLD}Gdisk v2.0${NC} ~${NC}${CYN}${BOLD} Preloaded Install ~ 6GB ${NC}" | borderize
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
need parted mkfs.vfat unzip tar dd lsblk blkid partprobe wipefs sync losetup wget

# grub-bios-setup resolved on demand (may be grub2-bios-setup)
BIOS_SETUP=""
for t in grub-bios-setup grub2-bios-setup; do
    for p in "$t" "/sbin/$t" "/usr/sbin/$t"; do
        command -v "$p" >/dev/null 2>&1 && { BIOS_SETUP="$p"; break 2; }
    done
done

# ====================================================================
#  HELPERS - space / RAM checks
# ====================================================================
get_avail_ram_kb() {
    # MemAvailable from /proc/meminfo (in KB)
    awk '/^MemAvailable:/ {print $2}' /proc/meminfo 2>/dev/null || echo 0
}

get_avail_space_bytes() {
    # available bytes on the filesystem containing $1
    local path="$1"
    [ -d "$path" ] || mkdir -p "$path" 2>/dev/null
    if [ -d "$path" ]; then
        df --output=avail -B1 "$path" 2>/dev/null | tail -n1 | tr -d ' '
    else
        echo 0
    fi
}

get_disk_size_bytes() {
    # total size of a block device in bytes
    blockdev --getsize64 "$1" 2>/dev/null || echo 0
}

# ====================================================================
#  DYNAMIC DOWNLOAD PATH RESOLUTION
# ====================================================================
resolve_download_path() {
    local ram_kb avail_tmp avail_home

    ram_kb="$(get_avail_ram_kb)"
    info "Available RAM: ${HL}$(( ram_kb / 1024 ))MB${NC}"

    # Option 1: /tmp if 8GB+ RAM available
    if [ "$ram_kb" -ge "$RAM_THRESHOLD" ]; then
        avail_tmp="$(get_avail_space_bytes /tmp)"
        if [ "$avail_tmp" -ge "$ZIP_SIZE_NEEDED" ]; then
            DL_DIR="/tmp/gdisk-v2-dl"
            DL_MODE="tmp"
            msg "Download path: ${HL}/tmp${NC} ($(( avail_tmp / 1024 / 1024 / 1024 ))GB available)"
            return
        else
            warn "/tmp has only $(( avail_tmp / 1024 / 1024 / 1024 ))GB - not enough"
        fi
    else
        info "Less than 8GB RAM - skipping /tmp"
    fi

    # Option 2: /home/.gdisk-install/
    avail_home="$(get_avail_space_bytes /home)"
    if [ "$avail_home" -ge "$ZIP_SIZE_NEEDED" ]; then
        DL_DIR="/home/.gdisk-install"
        DL_MODE="home"
        msg "Download path: ${HL}/home/.gdisk-install/${NC} ($(( avail_home / 1024 / 1024 / 1024 ))GB available)"
        return
    else
        warn "/home has only $(( avail_home / 1024 / 1024 / 1024 ))GB - not enough"
    fi

    # Option 3: download direct to target (set later after target selection)
    # Check if target disk has enough space - this is resolved in acquire_sources()
    DL_DIR=""
    DL_MODE="target"
    warn "Not enough space in /tmp or /home - will download to install target"
}

# Called when DL_MODE="target" and we know the target device
# Formats the target, mounts it, and sets DL_DIR on it
resolve_target_download() {
    local disk="$1" part="$2"
    local disk_size
    disk_size="$(get_disk_size_bytes "$disk")"

    if [ "$disk_size" -lt "$ZIP_SIZE_NEEDED" ]; then
        DL_MODE="fallback"
        return 1
    fi

    msg "Formatting target ${HL}$part${NC} to use as download staging area"
    format_fat "$part"
    mkdir -p "$MNT"
    mount "$part" "$MNT" || die "mount $part failed for staging"
    DL_DIR="$MNT/.gdisk-install"
    mkdir -p "$DL_DIR"
    msg "Download path: ${HL}$part${NC} (install target)"
    return 0
}

# ====================================================================
#  FALLBACK - offer core installer
# ====================================================================
offer_core_installer() {
    echo
    rule
    err "${BOLD}Not enough space to install Gdisk Preloaded 6GB+${NC}"
    rule
    echo
    echo "  Do you want to run the ${HL}base Gdisk installer${NC} instead?  ${BOLD}Y/n${NC}"
    echo
    echo "  ${DIM}Size needed for Gdisk Core Build ~ 100MB${NC}"
    echo "  ${DIM}Add your own .wim .iso .img .vtoy images manually after install.${NC}"
    echo
    local a
    read -rp "  > " a
    if [[ "$a" =~ ^[Yy]?$ ]]; then
        msg "Downloading core installer..."
        wget --progress=bar:force:noscroll -O /tmp/gdisk-v2.sh "$CORE_INSTALLER_URL" \
            || die "Failed to download core installer"
        msg "Launching core installer..."
        exec sudo bash /tmp/gdisk-v2.sh
    else
        die "Aborted - no installer launched"
    fi
}

# ====================================================================
#  SOURCE ACQUISITION
# ====================================================================
# Locate the zip + tarball. Priority:
#   1. Same directory as this script
#   2. Already-downloaded copy in $DL_DIR
#   3. Download from $BASE_URL (with progress)
acquire_sources() {
    local sdir; sdir="$(cd "$(dirname "$(readlink -f "$0")")" && pwd)"

    # Resolve download path if not yet done
    [ -n "$DL_DIR" ] || resolve_download_path
    [ "$DL_MODE" = "fallback" ] && { offer_core_installer; return; }

    mkdir -p "$DL_DIR"

    # -- grub-patch tarball (small, always fits) --
    if [ -f "$sdir/$TAR_NAME" ]; then
        cp -f "$sdir/$TAR_NAME" "$DL_DIR/$TAR_NAME"
        info "Using local: ${HL}$TAR_NAME${NC}"
    elif [ -f "$DL_DIR/$TAR_NAME" ]; then
        info "Cached: ${HL}$TAR_NAME${NC}"
    else
        info "Downloading ${HL}$TAR_NAME${NC} ..."
        wget --progress=bar:force:noscroll -O "$DL_DIR/$TAR_NAME.part" "$BASE_URL/$TAR_NAME" \
            || die "download failed: $BASE_URL/$TAR_NAME"
        mv -f "$DL_DIR/$TAR_NAME.part" "$DL_DIR/$TAR_NAME"
        msg "Downloaded: ${HL}$TAR_NAME${NC}"
    fi

    # -- main preloaded zip (6GB+) --
    if [ -f "$sdir/$ZIP_NAME" ]; then
        cp -f "$sdir/$ZIP_NAME" "$DL_DIR/$ZIP_NAME"
        info "Using local: ${HL}$ZIP_NAME${NC}"
    elif [ -f "$DL_DIR/$ZIP_NAME" ]; then
        info "Cached: ${HL}$ZIP_NAME${NC}"
    else
        echo
        rule
        info "Downloading ${HL}$ZIP_NAME${NC} (~6.1GB)"
        info "Download path: ${HL}$DL_DIR${NC}"
        rule
        echo
        wget --progress=bar:force:noscroll -O "$DL_DIR/$ZIP_NAME.part" "$BASE_URL/$ZIP_NAME" \
            || die "download failed: $BASE_URL/$ZIP_NAME"
        mv -f "$DL_DIR/$ZIP_NAME.part" "$DL_DIR/$ZIP_NAME"
        msg "Downloaded: ${HL}$ZIP_NAME${NC}"
    fi

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
    mountpoint -q "$MNT" || mount "$part" "$MNT" || die "mount $part failed"

    echo
    rule
    msg "Extracting Gdisk files to ${HL}$part${NC} - this may take a while..."
    rule
    echo

    # The zip wraps everything in a top-level folder.
    # Extract to a staging dir, then move the INNER contents to the FS root.
    local stage="$WORK_DIR/zip-stage"
    rm -rf "$stage"; mkdir -p "$stage"

    # Unzip with progress - show file count progress
    local total_files
    total_files="$(unzip -l "$ZIP" 2>/dev/null | tail -n1 | awk '{print $2}')"
    if [ -n "$total_files" ] && [ "$total_files" -gt 0 ] 2>/dev/null; then
        info "Extracting ${HL}$total_files${NC} files from archive..."
        # Use unzip with verbose output piped through a progress counter
        local count=0
        unzip -o "$ZIP" -d "$stage" 2>&1 | while IFS= read -r line; do
            if [[ "$line" == *"inflating:"* ]] || [[ "$line" == *"extracting:"* ]]; then
                count=$((count + 1))
                printf "\r  ${CYN}[i]${NC} Extracted: ${HL}%d${NC} / ${HL}%s${NC} files" "$count" "$total_files"
            fi
        done
        echo
    else
        # Fallback: basic unzip with some output
        unzip -o "$ZIP" -d "$stage" | tail -n1
    fi

    [ $? -eq 0 ] || die "unzip failed"

    # find the single wrapper dir (fallback: stage itself if already flat)
    local src="$stage"
    local entries; entries=$(ls -A "$stage")
    if [ "$(echo "$entries" | wc -l)" -eq 1 ] && [ -d "$stage/$entries" ]; then
        src="$stage/$entries"
    fi

    msg "Copying files to partition..."
    cp -a "$src"/. "$MNT"/ || die "copy to partition failed"
    sync
    msg "Extraction complete"

    # Clean up staging zip data from download dir if it was on the target
    if [ "$DL_MODE" = "target" ] && [ -d "$MNT/.gdisk-install" ]; then
        info "Cleaning staging data from target..."
        rm -rf "$MNT/.gdisk-install"
        sync
    fi
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

    # Resolve download path early
    resolve_download_path

    pick_disk
    local disk="$REPLY_DISK"
    confirm_destroy "$disk"

    # If DL_MODE is "target", we need to set up the disk first
    if [ "$DL_MODE" = "target" ]; then
        # size selection first (needed to create partition)
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

        header "Preparing Target for Download"
        unmount_all "$disk"
        make_partition "$disk" "$SIZESPEC"
        format_fat "$PART"

        # Try to use the target as download destination
        if ! resolve_target_download "$disk" "$PART"; then
            offer_core_installer
            return
        fi
    fi

    # Now acquire sources (downloads if needed)
    acquire_sources
    extract_patch

    # If not target mode, do size selection + partitioning now
    if [ "$DL_MODE" != "target" ]; then
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
    else
        # Target mode: partition is already formatted and mounted
        # Unmount briefly to re-extract cleanly
        header "Building Gdisk Device"
        mountpoint -q "$MNT" && umount "$MNT"
    fi

    extract_files "$PART"
    install_uefi_boot
    install_bios_boot "$disk" "$PART"
    finalize "$disk" "$PART"
}

op_update() {
    header "Update Gdisk"
    info "UPDATE - install/refresh Gdisk onto an EXISTING partition"

    resolve_download_path
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

    resolve_download_path
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

    # Clean up download cache if it was in /home
    if [ "$DL_MODE" = "home" ] && [ -d "/home/.gdisk-install" ]; then
        info "Cleaning download cache from /home/.gdisk-install/"
        rm -rf /home/.gdisk-install
    fi

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
