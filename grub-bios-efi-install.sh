#!/bin/bash
#═══════════════════════════════════════════════════════════════════════
#  grub-bios-efi-install.sh
#
#  Sets up a GPT disk with dual BIOS + EFI GRUB boot support:
#    Partition 1: BIOS Boot (ef02)  — 1 MiB    — GRUB core.img
#    Partition 2: FAT32 ESP (ef00)  — user-set  — Everything else:
#                 /EFI/BOOT/BOOTX64.EFI   (EFI bootloader)
#                 /boot/grub/grub.cfg     (shared config)
#                 /boot/grub/i386-pc/*    (BIOS modules)
#                 /boot/grub/x86_64-efi/* (EFI modules)
#                 /boot/iso/*             (multiboot ISOs)
#
#  Both BIOS and EFI GRUB load the same /boot/grub/grub.cfg
#  from the single FAT32 partition.
#
#  Usage:
#    sudo ./grub-bios-efi-install.sh /dev/sdX [grub.cfg]
#
#  Author: Marcus / gLiTcH Linux
#  Date:   2026-04-13
#═══════════════════════════════════════════════════════════════════════

set -euo pipefail

# ─── Colors ──────────────────────────────────────────────────────────
RED='\033[1;31m'
GRN='\033[1;32m'
YLW='\033[1;33m'
CYN='\033[1;36m'
MAG='\033[1;35m'
WHT='\033[1;37m'
DIM='\033[2m'
RST='\033[0m'

# ─── Borderize (auto-install if missing) ────────────────────────────
[ ! -f /usr/local/bin/borderize ] && \
  sudo curl -sL https://git.io/borderize -o /usr/local/bin/borderize && \
  sudo chmod +x /usr/local/bin/borderize

box() { echo -e "$1" | borderize; }

# ─── Sanity checks ──────────────────────────────────────────────────
if [[ $EUID -ne 0 ]]; then
    echo -e "${RED}ERROR: Must run as root (sudo)${RST}"
    exit 1
fi

if [[ $# -lt 1 ]]; then
    box "${WHT}  grub-bios-efi-install.sh  ${RST}"
    echo ""
    echo -e "  ${WHT}Usage:${RST} sudo $0 /dev/sdX [path/to/grub.cfg]"
    echo ""
    echo "  /dev/sdX       Target disk (WILL BE WIPED)"
    echo "  grub.cfg       Optional: custom grub.cfg to install"
    echo "                 If omitted, a default template is created"
    echo ""
    echo -e "  ${WHT}Partition layout:${RST}"
    echo "    Part 1: BIOS Boot (ef02)   — 1 MiB   (core.img)"
    echo "    Part 2: FAT32 ESP (ef00)   — selectable (EFI + GRUB + ISOs)"
    echo ""
    echo -e "  ${DIM}Both BIOS and EFI GRUB load the same grub.cfg from Part 2.${RST}"
    exit 1
fi

DISK="$1"
CUSTOM_GRUBCFG="${2:-}"

# ─── Dependency check ───────────────────────────────────────────────
MISSING=()
for cmd in sgdisk mkfs.vfat grub-install grub-mkimage partprobe blkid; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done

if [[ ${#MISSING[@]} -gt 0 ]]; then
    echo -e "${RED}Missing dependencies: ${MISSING[*]}${RST}"
    echo "Install with: apt install gdisk dosfstools grub-pc-bin grub-efi-amd64-bin grub-common parted"
    exit 1
fi

# ─── Verify GRUB platform modules exist ─────────────────────────────
GRUB_BIOS_DIR="/usr/lib/grub/i386-pc"
GRUB_EFI_DIR="/usr/lib/grub/x86_64-efi"

HAS_BIOS=true
HAS_EFI=true

if [[ ! -d "$GRUB_BIOS_DIR" ]]; then
    echo -e "${YLW}WARNING: $GRUB_BIOS_DIR not found — BIOS boot will be skipped${RST}"
    echo -e "${DIM}Install with: apt install grub-pc-bin${RST}"
    HAS_BIOS=false
fi

if [[ ! -d "$GRUB_EFI_DIR" ]]; then
    echo -e "${YLW}WARNING: $GRUB_EFI_DIR not found — EFI boot will be skipped${RST}"
    echo -e "${DIM}Install with: apt install grub-efi-amd64-bin${RST}"
    HAS_EFI=false
fi

if [[ "$HAS_BIOS" == false && "$HAS_EFI" == false ]]; then
    echo -e "${RED}ERROR: Neither BIOS nor EFI GRUB modules found. Nothing to install.${RST}"
    exit 1
fi

# Verify critical modules
if [[ "$HAS_BIOS" == true ]]; then
    for mod in fat part_gpt biosdisk search_fs_uuid normal configfile boot; do
        if [[ ! -f "$GRUB_BIOS_DIR/${mod}.mod" ]]; then
            echo -e "${RED}ERROR: Missing BIOS module: ${mod}.mod${RST}"
            exit 1
        fi
    done
fi

if [[ "$HAS_EFI" == true ]]; then
    for mod in fat part_gpt search_fs_uuid normal configfile boot efi_gop; do
        if [[ ! -f "$GRUB_EFI_DIR/${mod}.mod" ]]; then
            echo -e "${RED}ERROR: Missing EFI module: ${mod}.mod${RST}"
            exit 1
        fi
    done
fi

# ─── Validate target disk ───────────────────────────────────────────
if [[ ! -b "$DISK" ]]; then
    echo -e "${RED}ERROR: '$DISK' is not a block device${RST}"
    exit 1
fi

# Refuse to target mounted disks
if mount | grep -q "^${DISK}"; then
    echo -e "${RED}ERROR: '$DISK' or its partitions are currently mounted!${RST}"
    echo "Unmount first, then retry."
    exit 1
fi

# Get disk info
DISK_SIZE_BYTES=$(lsblk -bno SIZE "$DISK" | head -1)
DISK_SIZE_HUMAN=$(lsblk -no SIZE "$DISK" | head -1 | xargs)
DISK_MODEL=$(lsblk -no MODEL "$DISK" | head -1 | xargs)
DISK_SIZE_MB=$((DISK_SIZE_BYTES / 1024 / 1024))

# Overhead: 1 MiB (BIOS Boot) + ~2 MiB (GPT tables/alignment)
OVERHEAD_MB=3
AVAILABLE_MB=$((DISK_SIZE_MB - OVERHEAD_MB))

if [[ $AVAILABLE_MB -le 32 ]]; then
    echo -e "${RED}ERROR: Disk too small. Need at least ~64 MiB.${RST}"
    exit 1
fi

# ─── Ask for FAT32 partition size ────────────────────────────────────
echo ""
box "${CYN}  gLiTcH GRUB Dual-Boot Installer (BIOS + EFI)  ${RST}"
echo ""
echo -e "  ${WHT}Target disk:${RST}  $DISK"
echo -e "  ${WHT}Model:${RST}        ${DISK_MODEL:-unknown}"
echo -e "  ${WHT}Total size:${RST}   $DISK_SIZE_HUMAN (${DISK_SIZE_MB} MiB)"
echo -e "  ${WHT}Available:${RST}    ~${AVAILABLE_MB} MiB (after BIOS Boot partition)"
echo ""
echo -e "  ${WHT}Partition layout:${RST}"
echo -e "    Part 1: ${DIM}BIOS Boot (ef02)${RST}   — 1 MiB (fixed)"
echo -e "    Part 2: ${GRN}FAT32 ESP (ef00)${RST}   — ${WHT}you choose${RST}"
echo -e "             ${DIM}Holds: EFI bootloader + GRUB config + modules + ISOs${RST}"
echo ""
echo -e "  ${WHT}How large should the FAT32 partition be?${RST}"
echo ""
echo -e "    ${CYN}1)${RST}  Use all remaining space  (${AVAILABLE_MB} MiB)"
echo -e "    ${CYN}2)${RST}  Enter a custom size in MiB"
echo -e "    ${CYN}3)${RST}  Enter a custom size in GiB"
echo ""
read -rp "  Select [1/2/3]: " SIZE_CHOICE

case "$SIZE_CHOICE" in
    1)
        FAT32_SIZE_MB=0  # 0 = use remaining space
        FAT32_DISPLAY="${AVAILABLE_MB} MiB (all remaining)"
        ;;
    2)
        read -rp "  Enter size in MiB: " FAT32_SIZE_MB
        if ! [[ "$FAT32_SIZE_MB" =~ ^[0-9]+$ ]] || [[ "$FAT32_SIZE_MB" -lt 32 ]]; then
            echo -e "${RED}ERROR: Invalid size (minimum 32 MiB)${RST}"
            exit 1
        fi
        if [[ "$FAT32_SIZE_MB" -gt "$AVAILABLE_MB" ]]; then
            echo -e "${RED}ERROR: ${FAT32_SIZE_MB} MiB exceeds available space (${AVAILABLE_MB} MiB)${RST}"
            exit 1
        fi
        FAT32_DISPLAY="${FAT32_SIZE_MB} MiB"
        ;;
    3)
        read -rp "  Enter size in GiB: " FAT32_SIZE_GIB
        if ! [[ "$FAT32_SIZE_GIB" =~ ^[0-9]+\.?[0-9]*$ ]]; then
            echo -e "${RED}ERROR: Invalid number${RST}"
            exit 1
        fi
        FAT32_SIZE_MB=$(echo "$FAT32_SIZE_GIB * 1024" | bc | cut -d. -f1)
        if [[ "$FAT32_SIZE_MB" -lt 32 ]]; then
            echo -e "${RED}ERROR: Too small (minimum 32 MiB)${RST}"
            exit 1
        fi
        if [[ "$FAT32_SIZE_MB" -gt "$AVAILABLE_MB" ]]; then
            echo -e "${RED}ERROR: ${FAT32_SIZE_GIB} GiB exceeds available space (${AVAILABLE_MB} MiB)${RST}"
            exit 1
        fi
        FAT32_DISPLAY="${FAT32_SIZE_GIB} GiB (${FAT32_SIZE_MB} MiB)"
        ;;
    *)
        echo -e "${RED}Invalid selection.${RST}"
        exit 1
        ;;
esac

# ─── Confirmation ───────────────────────────────────────────────────
echo ""
box "${RED}  ⚠  WARNING: ALL DATA ON ${DISK} WILL BE DESTROYED  ⚠  ${RST}"
echo ""
echo -e "  ${WHT}Disk:${RST}           $DISK ($DISK_SIZE_HUMAN)"
echo -e "  ${WHT}grub.cfg:${RST}       ${CUSTOM_GRUBCFG:-<default template>}"
echo ""
echo -e "  ${WHT}Partition layout:${RST}"
echo -e "    Part 1: ${CYN}BIOS Boot (ef02)${RST}   — 1 MiB"
echo -e "    Part 2: ${GRN}FAT32 ESP (ef00)${RST}   — $FAT32_DISPLAY"
echo ""
echo -e "  ${WHT}Boot targets:${RST}"
[[ "$HAS_BIOS" == true ]]  && echo -e "    ${GRN}✓${RST} BIOS (i386-pc)      → core.img in Part 1 → grub.cfg on Part 2"
[[ "$HAS_BIOS" == false ]] && echo -e "    ${YLW}✗${RST} BIOS (i386-pc)      → skipped (no modules)"
[[ "$HAS_EFI" == true ]]   && echo -e "    ${GRN}✓${RST} EFI  (x86_64-efi)   → BOOTX64.EFI on Part 2 → grub.cfg on Part 2"
[[ "$HAS_EFI" == false ]]  && echo -e "    ${YLW}✗${RST} EFI  (x86_64-efi)   → skipped (no modules)"
echo ""
read -rp "  Type YES to proceed: " CONFIRM
if [[ "$CONFIRM" != "YES" ]]; then
    echo "Aborted."
    exit 0
fi

echo ""

# ═══════════════════════════════════════════════════════════════════
#  STEP 1: Partition the disk (GPT)
# ═══════════════════════════════════════════════════════════════════
box "${CYN}Step 1/5: Partitioning ${DISK} (GPT)${RST}"

sgdisk --zap-all "$DISK" >/dev/null 2>&1 || true

if [[ "$FAT32_SIZE_MB" -eq 0 ]]; then
    sgdisk \
        --new=1:2048:+1M      --typecode=1:ef02 --change-name=1:"BIOS-Boot" \
        --new=2:0:0           --typecode=2:ef00 --change-name=2:"GRUB-ESP" \
        "$DISK"
else
    sgdisk \
        --new=1:2048:+1M      --typecode=1:ef02 --change-name=1:"BIOS-Boot" \
        --new=2:0:+${FAT32_SIZE_MB}M --typecode=2:ef00 --change-name=2:"GRUB-ESP" \
        "$DISK"
fi

partprobe "$DISK" 2>/dev/null || true
sleep 1

# Determine partition naming
if [[ "$DISK" =~ [0-9]$ ]]; then
    PART1="${DISK}p1"
    PART2="${DISK}p2"
else
    PART1="${DISK}1"
    PART2="${DISK}2"
fi

# Wait for partitions
for i in {1..10}; do
    [[ -b "$PART1" && -b "$PART2" ]] && break
    sleep 0.5
done

if [[ ! -b "$PART1" ]] || [[ ! -b "$PART2" ]]; then
    echo -e "${RED}ERROR: Partitions didn't appear. Check 'lsblk $DISK'${RST}"
    exit 1
fi

echo -e "${GRN}  ✓ Partitioned: $PART1 (BIOS Boot) + $PART2 (FAT32 ESP)${RST}"

# ═══════════════════════════════════════════════════════════════════
#  STEP 2: Format the FAT32 partition
# ═══════════════════════════════════════════════════════════════════
box "${CYN}Step 2/5: Formatting FAT32 partition${RST}"

mkfs.vfat -F 32 -n "GRUB-ESP" "$PART2"
FAT_UUID=$(blkid -s UUID -o value "$PART2")
echo -e "${GRN}  ✓ FAT32 formatted — UUID: ${WHT}${FAT_UUID}${RST}"

# ═══════════════════════════════════════════════════════════════════
#  STEP 3: Populate the FAT32 partition
# ═══════════════════════════════════════════════════════════════════
box "${CYN}Step 3/5: Populating FAT32 partition${RST}"

MNT=$(mktemp -d /tmp/grub-mnt.XXXXXX)
mount "$PART2" "$MNT"

# Create directory structure
mkdir -p "$MNT/boot/grub/i386-pc"
mkdir -p "$MNT/boot/grub/x86_64-efi"
mkdir -p "$MNT/boot/grub/fonts"
mkdir -p "$MNT/boot/grub/themes"
mkdir -p "$MNT/boot/iso"
mkdir -p "$MNT/EFI/BOOT"

# Copy ALL modules for both platforms
if [[ "$HAS_BIOS" == true ]]; then
    cp "$GRUB_BIOS_DIR"/*.mod "$MNT/boot/grub/i386-pc/" 2>/dev/null || true
    cp "$GRUB_BIOS_DIR"/*.lst "$MNT/boot/grub/i386-pc/" 2>/dev/null || true
    BIOS_MOD_COUNT=$(ls "$MNT/boot/grub/i386-pc/"*.mod 2>/dev/null | wc -l)
    echo -e "${GRN}  ✓ Copied ${BIOS_MOD_COUNT} i386-pc modules${RST}"
fi

if [[ "$HAS_EFI" == true ]]; then
    cp "$GRUB_EFI_DIR"/*.mod "$MNT/boot/grub/x86_64-efi/" 2>/dev/null || true
    cp "$GRUB_EFI_DIR"/*.lst "$MNT/boot/grub/x86_64-efi/" 2>/dev/null || true
    EFI_MOD_COUNT=$(ls "$MNT/boot/grub/x86_64-efi/"*.mod 2>/dev/null | wc -l)
    echo -e "${GRN}  ✓ Copied ${EFI_MOD_COUNT} x86_64-efi modules${RST}"
fi

# Copy unicode font
if [[ -f /usr/share/grub/unicode.pf2 ]]; then
    cp /usr/share/grub/unicode.pf2 "$MNT/boot/grub/fonts/"
elif [[ -f /boot/grub/fonts/unicode.pf2 ]]; then
    cp /boot/grub/fonts/unicode.pf2 "$MNT/boot/grub/fonts/"
fi

# ─── Install grub.cfg ───────────────────────────────────────────
if [[ -n "$CUSTOM_GRUBCFG" && -f "$CUSTOM_GRUBCFG" ]]; then
    cp "$CUSTOM_GRUBCFG" "$MNT/boot/grub/grub.cfg"
    echo -e "${GRN}  ✓ Installed custom grub.cfg from: $CUSTOM_GRUBCFG${RST}"
else
    cat > "$MNT/boot/grub/grub.cfg" << 'GRUBCFG'
#═══════════════════════════════════════════════════════════
#  gLiTcH GRUB Multiboot — grub.cfg
#  Works for both BIOS and EFI boot modes.
#  Edit this file on the FAT32 partition: /boot/grub/grub.cfg
#═══════════════════════════════════════════════════════════

set timeout=10
set default=0

# Load modules
insmod fat
insmod part_gpt
insmod all_video
insmod gfxterm
insmod png
insmod iso9660
insmod loopback
insmod search_fs_uuid

# Graphics setup
if loadfont /boot/grub/fonts/unicode.pf2; then
    set gfxmode=auto
    terminal_output gfxterm
fi

# Theme (uncomment and adjust path if you have one)
# set theme=/boot/grub/themes/glitch/theme.txt

set menu_color_normal=white/black
set menu_color_highlight=black/cyan

#───────────────────────────────────────────────────────────
# MENU ENTRIES
#───────────────────────────────────────────────────────────

menuentry "── gLiTcH Multiboot Utility ──" {
    true
}

menuentry "Boot from first hard disk (BIOS chainload)" --class disk {
    set root=(hd1)
    chainloader +1
}

menuentry "Boot from first hard disk (EFI)" --class disk {
    # Replace with the target disk's EFI partition UUID
    search --no-floppy --fs-uuid --set=efiroot <TARGET-EFI-UUID>
    chainloader ($efiroot)/EFI/BOOT/BOOTX64.EFI
}

# ─── Example: ISO loopback boot ─────────────────────────
# Copy ISOs to /boot/iso/ on this partition
#
# menuentry "Ubuntu 24.04 Live ISO" --class ubuntu {
#     set isofile="/boot/iso/ubuntu-24.04-desktop-amd64.iso"
#     loopback loop $isofile
#     linux (loop)/casper/vmlinuz boot=casper iso-scan/filename=$isofile quiet splash
#     initrd (loop)/casper/initrd
# }

menuentry "Reboot" --class restart {
    reboot
}

menuentry "Power Off" --class shutdown {
    halt
}
GRUBCFG
    echo -e "${GRN}  ✓ Default grub.cfg template installed${RST}"
fi

echo -e "${GRN}  ✓ /boot/iso/ directory created for multiboot ISOs${RST}"

# ═══════════════════════════════════════════════════════════════════
#  STEP 4: Install GRUB — both BIOS and EFI
# ═══════════════════════════════════════════════════════════════════

# ─── BIOS (i386-pc) ─────────────────────────────────────────────
if [[ "$HAS_BIOS" == true ]]; then
    box "${CYN}Step 4/5: Installing GRUB — BIOS (i386-pc)${RST}"

    grub-install \
        --target=i386-pc \
        --boot-directory="$MNT/boot" \
        --modules="fat part_gpt biosdisk search_fs_uuid normal configfile boot ext2 gzio" \
        --recheck \
        --no-floppy \
        "$DISK" 2>&1

    echo -e "${GRN}  ✓ BIOS GRUB installed → core.img in $PART1${RST}"
    echo -e "${DIM}    core.img searches UUID ${FAT_UUID} → /boot/grub/grub.cfg${RST}"
else
    box "${YLW}Step 4/5: Skipping BIOS (no i386-pc modules)${RST}"
fi

# ─── EFI (x86_64-efi) ───────────────────────────────────────────
if [[ "$HAS_EFI" == true ]]; then
    box "${CYN}Step 4/5: Installing GRUB — EFI (x86_64-efi)${RST}"

    # Build embedded early config — searches for THIS partition by UUID
    EARLY_CFG=$(mktemp /tmp/grub-early.XXXXXX)
    cat > "$EARLY_CFG" << EOF
search.fs_uuid ${FAT_UUID} root
set prefix=(\$root)/boot/grub
configfile \$prefix/grub.cfg
EOF

    # Build standalone BOOTX64.EFI for removable media boot
    grub-mkimage \
        --format=x86_64-efi \
        --output="$MNT/EFI/BOOT/BOOTX64.EFI" \
        --config="$EARLY_CFG" \
        --prefix="/boot/grub" \
        fat part_gpt search_fs_uuid normal configfile boot \
        efi_gop efi_uga all_video gfxterm png \
        ext2 iso9660 loopback gzio chain \
        search search_fs_file search_label \
        ls cat echo test true

    rm -f "$EARLY_CFG"

    # Some firmware looks for grubx64.efi instead
    cp "$MNT/EFI/BOOT/BOOTX64.EFI" "$MNT/EFI/BOOT/grubx64.efi"

    EFI_SIZE_KB=$(( $(stat -c%s "$MNT/EFI/BOOT/BOOTX64.EFI") / 1024 ))

    echo -e "${GRN}  ✓ BOOTX64.EFI built (${EFI_SIZE_KB} KiB)${RST}"
    echo -e "${GRN}  ✓ Installed to $PART2 → /EFI/BOOT/BOOTX64.EFI${RST}"
    echo -e "${DIM}    EFI early config: search.fs_uuid ${FAT_UUID} → /boot/grub/grub.cfg${RST}"
else
    box "${YLW}Step 4/5: Skipping EFI (no x86_64-efi modules)${RST}"
fi

# ═══════════════════════════════════════════════════════════════════
#  STEP 5: Verify & report
# ═══════════════════════════════════════════════════════════════════
box "${CYN}Step 5/5: Verification${RST}"

# Verify BIOS core.img
if [[ "$HAS_BIOS" == true ]]; then
    EMBEDDED_UUID=$(strings "$PART1" 2>/dev/null | grep 'search.fs_uuid' | head -1)
    if [[ -n "$EMBEDDED_UUID" ]]; then
        echo -e "${GRN}  ✓ BIOS core.img: ${WHT}${EMBEDDED_UUID}${RST}"
    else
        echo -e "${YLW}  ⚠ Could not read embedded UUID from core.img${RST}"
    fi
fi

# Verify EFI
if [[ "$HAS_EFI" == true ]]; then
    if [[ -f "$MNT/EFI/BOOT/BOOTX64.EFI" ]]; then
        echo -e "${GRN}  ✓ /EFI/BOOT/BOOTX64.EFI present${RST}"
    else
        echo -e "${RED}  ✗ BOOTX64.EFI NOT found!${RST}"
    fi
fi

# Verify grub.cfg
if [[ -f "$MNT/boot/grub/grub.cfg" ]]; then
    echo -e "${GRN}  ✓ /boot/grub/grub.cfg present${RST}"
else
    echo -e "${RED}  ✗ grub.cfg NOT found!${RST}"
fi

# Verify key modules
[[ "$HAS_BIOS" == true && -f "$MNT/boot/grub/i386-pc/fat.mod" ]] && \
    echo -e "${GRN}  ✓ i386-pc/fat.mod available${RST}"
[[ "$HAS_EFI" == true && -f "$MNT/boot/grub/x86_64-efi/fat.mod" ]] && \
    echo -e "${GRN}  ✓ x86_64-efi/fat.mod available${RST}"

# Show disk usage
USED=$(du -sh "$MNT" 2>/dev/null | awk '{print $1}')
echo -e "${GRN}  ✓ Total space used on FAT32: ${WHT}${USED}${RST}"

# Clean up
umount "$MNT"
rmdir "$MNT"

# ═══════════════════════════════════════════════════════════════════
#  SUMMARY
# ═══════════════════════════════════════════════════════════════════
echo ""
box "${GRN}  ✓  Dual BIOS/EFI GRUB Installation Complete  ✓  ${RST}"
echo ""
echo -e "  ${WHT}Disk:${RST}         $DISK ($DISK_SIZE_HUMAN)"
echo -e "  ${WHT}Part 1:${RST}       $PART1 — BIOS Boot (ef02) — 1 MiB"
echo -e "  ${WHT}Part 2:${RST}       $PART2 — FAT32 ESP (ef00) — UUID: ${FAT_UUID}"
echo ""
echo -e "  ${WHT}FAT32 contents:${RST}"
echo -e "    /EFI/BOOT/BOOTX64.EFI        ← EFI bootloader"
echo -e "    /boot/grub/grub.cfg           ← shared boot config"
echo -e "    /boot/grub/i386-pc/*.mod      ← BIOS modules"
echo -e "    /boot/grub/x86_64-efi/*.mod   ← EFI modules"
echo -e "    /boot/grub/fonts/             ← fonts"
echo -e "    /boot/iso/                    ← drop ISOs here"
echo ""
echo -e "  ${WHT}Boot chain (BIOS):${RST}"
echo -e "    MBR → core.img ($PART1) → search UUID ${FAT_UUID} → /boot/grub/grub.cfg"
echo ""
echo -e "  ${WHT}Boot chain (EFI):${RST}"
echo -e "    Firmware → /EFI/BOOT/BOOTX64.EFI ($PART2) → search UUID ${FAT_UUID} → /boot/grub/grub.cfg"
echo ""
echo -e "  ${CYN}To edit the boot menu:${RST}"
echo -e "    mount $PART2 /mnt"
echo -e "    nano /mnt/boot/grub/grub.cfg"
echo -e "    umount /mnt"
echo ""
echo -e "  ${CYN}To add ISOs:${RST}"
echo -e "    mount $PART2 /mnt"
echo -e "    cp distro.iso /mnt/boot/iso/"
echo -e "    umount /mnt"
echo ""

# ─── Execution flow ─────────────────────────────────────────────
# 1. Validates dependencies, GRUB modules (BIOS + EFI), target disk
# 2. User selects FAT32 partition size (all remaining / MiB / GiB)
# 3. Creates GPT: 1 MiB BIOS Boot (ef02) + FAT32 ESP (ef00)
# 4. Formats FAT32, creates directory structure
# 5. Copies all GRUB modules (both platforms) + grub.cfg + fonts
# 6. BIOS: grub-install writes MBR + core.img with fat module embedded
# 7. EFI:  grub-mkimage builds standalone BOOTX64.EFI with early
#          config that searches FAT32 UUID → loads grub.cfg
# 8. Both boot paths share the SAME grub.cfg on the SAME partition
# 9. Verifies all components and reports results
