#!/bin/bash
#═══════════════════════════════════════════════════════════════════════
#  grub-multiboot-setup.sh
#
#  Interactive GRUB installer for multiboot USB/disk utilities.
#  Supports GPT, MBR, loop devices with BIOS + EFI boot.
#
#  Modes:
#    1) GPT — BIOS Boot (ef02) + FAT32 ESP (ef00)
#    2) MBR — Single FAT32 partition (GRUB in MBR gap + EFI on FAT32)
#    3) Repair — Reinstall GRUB on existing disk (no format)
#
#  Author: Marcus / gLiTcH Linux
#  Date:   2026-04-14
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
BLD='\033[1m'
RST='\033[0m'

# ─── Borderize (auto-install if missing) ────────────────────────────
if [ ! -f /usr/local/bin/borderize ]; then
    curl -sL https://git.io/borderize -o /usr/local/bin/borderize 2>/dev/null && \
    chmod +x /usr/local/bin/borderize 2>/dev/null || true
fi

box() {
    if command -v borderize &>/dev/null; then
        echo -e "$1" | borderize
    else
        echo -e "  $1"
    fi
}

# ─── Helper functions ───────────────────────────────────────────────
die()     { echo -e "${RED}ERROR: $1${RST}"; exit 1; }
warn()    { echo -e "${YLW}WARNING: $1${RST}"; }
ok()      { echo -e "${GRN}  ✓ $1${RST}"; }
info()    { echo -e "${DIM}    $1${RST}"; }
prompt()  { read -rp "$(echo -e "  ${CYN}▸${RST} $1")" "$2"; }

# Partition name helper (sda1 vs nvme0n1p1 vs loop0p1)
part_name() {
    local disk="$1" num="$2"
    if [[ "$disk" =~ [0-9]$ ]]; then
        echo "${disk}p${num}"
    else
        echo "${disk}${num}"
    fi
}

# Rescan partitions — works for both real disks and loop devices
rescan_partitions() {
    local disk="$1"
    if [[ "$disk" =~ ^/dev/loop ]]; then
        losetup -P "$disk" 2>/dev/null || true
        partx -u "$disk" 2>/dev/null || true
    fi
    partprobe "$disk" 2>/dev/null || true
    sleep 1
}

wait_for_part() {
    local part="$1"
    for i in {1..20}; do
        [[ -b "$part" ]] && return 0
        sleep 0.5
    done
    die "Partition $part didn't appear after 10 seconds"
}

# Check if device or its partitions are mounted
is_mounted() {
    local disk="$1"
    if grep -q "^${disk}[p]*[0-9]* \|^${disk} " /proc/mounts 2>/dev/null; then
        return 0
    fi
    return 1
}

# ─── Root check ─────────────────────────────────────────────────────
[[ $EUID -ne 0 ]] && die "Must run as root (sudo)"

# ─── Dependency check ───────────────────────────────────────────────
MISSING=()
for cmd in sgdisk sfdisk mkfs.vfat grub-install grub-mkimage partprobe blkid lsblk; do
    command -v "$cmd" &>/dev/null || MISSING+=("$cmd")
done
if [[ ${#MISSING[@]} -gt 0 ]]; then
    die "Missing: ${MISSING[*]}\nInstall: apt install gdisk util-linux dosfstools grub-pc-bin grub-efi-amd64-bin grub-common parted"
fi

# ─── Detect GRUB platforms ──────────────────────────────────────────
GRUB_BIOS_DIR="/usr/lib/grub/i386-pc"
GRUB_EFI_DIR="/usr/lib/grub/x86_64-efi"
HAS_BIOS=false; HAS_EFI=false
[[ -d "$GRUB_BIOS_DIR" ]] && HAS_BIOS=true
[[ -d "$GRUB_EFI_DIR" ]]  && HAS_EFI=true
[[ "$HAS_BIOS" == false && "$HAS_EFI" == false ]] && \
    die "No GRUB modules found.\napt install grub-pc-bin grub-efi-amd64-bin"

# ─── GRUB modules for embedding ─────────────────────────────────────
BIOS_EMBED_MODS="fat part_gpt part_msdos biosdisk search_fs_uuid normal configfile boot ext2 gzio"
EFI_IMAGE_MODS="fat part_gpt part_msdos search_fs_uuid normal configfile boot efi_gop efi_uga all_video gfxterm png ext2 iso9660 loopback gzio chain search search_fs_file search_label ls cat echo test true"


# ═══════════════════════════════════════════════════════════════════
#  SHARED FUNCTIONS
# ═══════════════════════════════════════════════════════════════════

list_disks() {
    echo ""
    echo -e "  ${WHT}Available block devices:${RST}"
    echo ""

    # Physical disks (skip ram, sr, and unused loop devices)
    lsblk -dno NAME,SIZE,MODEL,TRAN 2>/dev/null | while read -r name size model tran; do
        local dev="/dev/$name"
        [[ "$name" =~ ^(ram|sr) ]] && continue

        # Skip loop devices with no backing file
        if [[ "$name" =~ ^loop ]]; then
            local backing
            backing=$(losetup -n -O BACK-FILE "$dev" 2>/dev/null | xargs)
            [[ -z "$backing" ]] && continue
        fi

        local mounted=""
        is_mounted "$dev" && mounted=" ${RED}[MOUNTED]${RST}"

        local desc=""
        [[ -n "${model:-}" ]] && desc="$model"
        [[ -n "${tran:-}" ]]  && desc="${desc:+$desc }($tran)"

        # For loop devices, show backing file instead of model
        if [[ "$name" =~ ^loop ]]; then
            local backing
            backing=$(losetup -n -O BACK-FILE "$dev" 2>/dev/null | xargs)
            desc="← $backing"
        fi

        echo -e "    ${CYN}${dev}${RST}  ${WHT}${size}${RST}  ${desc}${mounted}"
    done

    echo ""
    echo -e "  ${DIM}To use an image file, first attach it:${RST}"
    echo -e "  ${DIM}  losetup -fP /path/to/disk.img${RST}"
    echo -e "  ${DIM}Or just enter the image path below and it will be auto-attached.${RST}"
    echo ""
}

select_disk() {
    list_disks
    prompt "Enter target device or image file: " DISK

    # If user passed a regular file, offer to loop-mount it
    if [[ -f "$DISK" ]]; then
        echo ""
        echo -e "  ${YLW}'$(basename "$DISK")' is a file — attaching as loop device...${RST}"
        DISK=$(losetup --show -fP "$DISK")
        ok "Attached as: ${WHT}${DISK}${RST}"
    elif [[ ! -b "$DISK" ]]; then
        die "'$DISK' is not a block device or existing file"
    fi

    # Mounted check
    if is_mounted "$DISK"; then
        die "'$DISK' has mounted partitions. Unmount first."
    fi

    DISK_SIZE_BYTES=$(lsblk -bno SIZE "$DISK" | head -1)
    DISK_SIZE_HUMAN=$(lsblk -no SIZE "$DISK" | head -1 | xargs)
    DISK_MODEL=$(lsblk -no MODEL "$DISK" 2>/dev/null | head -1 | xargs)
    DISK_SIZE_MB=$((DISK_SIZE_BYTES / 1024 / 1024))

    # For loop devices, show backing file as the model
    if [[ "$DISK" =~ ^/dev/loop ]]; then
        local backing
        backing=$(losetup -n -O BACK-FILE "$DISK" 2>/dev/null | xargs)
        DISK_MODEL="loop ← ${backing:-unknown}"
    fi
}

select_fat32_size() {
    local available_mb="$1"

    echo ""
    echo -e "  ${WHT}FAT32 partition size:${RST}"
    echo ""
    echo -e "    ${CYN}1)${RST}  Use all remaining space  (~${available_mb} MiB)"
    echo -e "    ${CYN}2)${RST}  Enter custom size in MiB"
    echo -e "    ${CYN}3)${RST}  Enter custom size in GiB"
    echo ""
    prompt "Select [1/2/3]: " SIZE_CHOICE

    case "$SIZE_CHOICE" in
        1)
            FAT32_SIZE_MB=0
            FAT32_DISPLAY="${available_mb} MiB (all remaining)"
            ;;
        2)
            prompt "Size in MiB: " FAT32_SIZE_MB
            [[ "$FAT32_SIZE_MB" =~ ^[0-9]+$ ]] || die "Invalid number"
            [[ "$FAT32_SIZE_MB" -ge 32 ]]       || die "Minimum 32 MiB"
            [[ "$FAT32_SIZE_MB" -le "$available_mb" ]] || die "${FAT32_SIZE_MB} MiB > available ${available_mb} MiB"
            FAT32_DISPLAY="${FAT32_SIZE_MB} MiB"
            ;;
        3)
            prompt "Size in GiB: " FAT32_SIZE_GIB
            [[ "$FAT32_SIZE_GIB" =~ ^[0-9]+\.?[0-9]*$ ]] || die "Invalid number"
            FAT32_SIZE_MB=$(echo "$FAT32_SIZE_GIB * 1024" | bc | cut -d. -f1)
            [[ "$FAT32_SIZE_MB" -ge 32 ]]       || die "Minimum 32 MiB"
            [[ "$FAT32_SIZE_MB" -le "$available_mb" ]] || die "${FAT32_SIZE_GIB} GiB > available ${available_mb} MiB"
            FAT32_DISPLAY="${FAT32_SIZE_GIB} GiB (${FAT32_SIZE_MB} MiB)"
            ;;
        *)  die "Invalid selection" ;;
    esac
}

select_grubcfg() {
    echo ""
    echo -e "  ${WHT}grub.cfg source:${RST}"
    echo ""
    echo -e "    ${CYN}1)${RST}  Generate default multiboot template"
    echo -e "    ${CYN}2)${RST}  Use a custom grub.cfg file"
    echo ""
    prompt "Select [1/2]: " CFG_CHOICE

    CUSTOM_GRUBCFG=""
    if [[ "$CFG_CHOICE" == "2" ]]; then
        prompt "Path to grub.cfg: " CUSTOM_GRUBCFG
        [[ -f "$CUSTOM_GRUBCFG" ]] || die "File not found: $CUSTOM_GRUBCFG"
    fi
}

install_grubcfg() {
    local target_dir="$1"

    if [[ -n "$CUSTOM_GRUBCFG" && -f "$CUSTOM_GRUBCFG" ]]; then
        cp "$CUSTOM_GRUBCFG" "$target_dir/boot/grub/grub.cfg"
        ok "Installed custom grub.cfg"
    else
        cat > "$target_dir/boot/grub/grub.cfg" << 'GRUBCFG'
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
insmod part_msdos
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

# Theme (uncomment if you have one)
# set theme=/boot/grub/themes/glitch/theme.txt

set menu_color_normal=white/black
set menu_color_highlight=black/cyan

#───────────────────────────────────────────────────────────
# MENU ENTRIES
#───────────────────────────────────────────────────────────

menuentry "── gLiTcH Multiboot Utility ──" {
    true
}

menuentry "Boot from first hard disk (BIOS)" --class disk {
    set root=(hd1)
    chainloader +1
}

menuentry "Boot from first hard disk (EFI)" --class disk {
    search --no-floppy --fs-uuid --set=efiroot <TARGET-EFI-UUID>
    chainloader ($efiroot)/EFI/BOOT/BOOTX64.EFI
}

# ─── ISO loopback example ───────────────────────────────
# menuentry "Ubuntu 24.04 Live" --class ubuntu {
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
        ok "Default grub.cfg template installed"
    fi
}

populate_fat32() {
    local mnt="$1"

    mkdir -p "$mnt/boot/grub/i386-pc"
    mkdir -p "$mnt/boot/grub/x86_64-efi"
    mkdir -p "$mnt/boot/grub/fonts"
    mkdir -p "$mnt/boot/grub/themes"
    mkdir -p "$mnt/boot/iso"
    mkdir -p "$mnt/EFI/BOOT"

    if [[ "$HAS_BIOS" == true ]]; then
        cp "$GRUB_BIOS_DIR"/*.mod "$mnt/boot/grub/i386-pc/" 2>/dev/null || true
        cp "$GRUB_BIOS_DIR"/*.lst "$mnt/boot/grub/i386-pc/" 2>/dev/null || true
        local cnt
        cnt=$(ls "$mnt/boot/grub/i386-pc/"*.mod 2>/dev/null | wc -l)
        ok "Copied ${cnt} i386-pc modules"
    fi

    if [[ "$HAS_EFI" == true ]]; then
        cp "$GRUB_EFI_DIR"/*.mod "$mnt/boot/grub/x86_64-efi/" 2>/dev/null || true
        cp "$GRUB_EFI_DIR"/*.lst "$mnt/boot/grub/x86_64-efi/" 2>/dev/null || true
        local cnt
        cnt=$(ls "$mnt/boot/grub/x86_64-efi/"*.mod 2>/dev/null | wc -l)
        ok "Copied ${cnt} x86_64-efi modules"
    fi

    # Font
    if [[ -f /usr/share/grub/unicode.pf2 ]]; then
        cp /usr/share/grub/unicode.pf2 "$mnt/boot/grub/fonts/"
    elif [[ -f /boot/grub/fonts/unicode.pf2 ]]; then
        cp /boot/grub/fonts/unicode.pf2 "$mnt/boot/grub/fonts/"
    fi

    install_grubcfg "$mnt"
    ok "/boot/iso/ directory ready for multiboot ISOs"
}

install_bios_grub() {
    local disk="$1" mnt="$2" extra_flags="${3:-}"

    if [[ "$HAS_BIOS" == false ]]; then
        warn "Skipping BIOS (no i386-pc modules)"
        return
    fi

    grub-install \
        --target=i386-pc \
        --boot-directory="$mnt/boot" \
        --modules="$BIOS_EMBED_MODS" \
        --recheck \
        --no-floppy \
        $extra_flags \
        "$disk" 2>&1

    ok "BIOS GRUB installed to $disk"
}

install_efi_grub() {
    local mnt="$1" uuid="$2"

    if [[ "$HAS_EFI" == false ]]; then
        warn "Skipping EFI (no x86_64-efi modules)"
        return
    fi

    mkdir -p "$mnt/EFI/BOOT"

    local early_cfg
    early_cfg=$(mktemp /tmp/grub-early.XXXXXX)
    cat > "$early_cfg" << EOF
search.fs_uuid ${uuid} root
set prefix=(\$root)/boot/grub
configfile \$prefix/grub.cfg
EOF

    grub-mkimage \
        --format=x86_64-efi \
        --output="$mnt/EFI/BOOT/BOOTX64.EFI" \
        --config="$early_cfg" \
        --prefix="/boot/grub" \
        $EFI_IMAGE_MODS

    rm -f "$early_cfg"

    cp "$mnt/EFI/BOOT/BOOTX64.EFI" "$mnt/EFI/BOOT/grubx64.efi"

    local size_kb=$(( $(stat -c%s "$mnt/EFI/BOOT/BOOTX64.EFI") / 1024 ))
    ok "BOOTX64.EFI built (${size_kb} KiB)"
    info "EFI early config: search.fs_uuid ${uuid} → /boot/grub/grub.cfg"
}

verify_install() {
    local disk="$1" mnt="$2" bios_part="${3:-}"

    echo ""
    box "${CYN}Verification${RST}"

    # BIOS — check core.img content
    if [[ "$HAS_BIOS" == true ]]; then
        local embedded=""

        if [[ -n "$bios_part" && -b "$bios_part" ]]; then
            # GPT: dedicated BIOS Boot partition (small, safe to strings)
            embedded=$(strings "$bios_part" 2>/dev/null | grep 'search.fs_uuid' | head -1) || true
            if [[ -n "$embedded" ]]; then
                ok "BIOS core.img: ${WHT}${embedded}${RST}"
            fi
        fi

        if [[ -z "$embedded" ]]; then
            # MBR / fallback: only read the post-MBR gap (sectors 1-2047, ~1 MiB)
            # NEVER strings the entire disk — it would hang on large devices
            embedded=$(dd if="$disk" bs=512 skip=1 count=2046 2>/dev/null | strings | grep 'search.fs_uuid' | head -1) || true
            if [[ -n "$embedded" ]]; then
                ok "BIOS core.img (MBR gap): ${WHT}${embedded}${RST}"
            else
                warn "Could not verify BIOS core.img UUID"
            fi
        fi
    fi

    # EFI
    if [[ "$HAS_EFI" == true && -f "$mnt/EFI/BOOT/BOOTX64.EFI" ]]; then
        ok "/EFI/BOOT/BOOTX64.EFI present"
    elif [[ "$HAS_EFI" == true ]]; then
        echo -e "${RED}  ✗ BOOTX64.EFI NOT found!${RST}"
    fi

    # grub.cfg
    if [[ -f "$mnt/boot/grub/grub.cfg" ]]; then
        ok "/boot/grub/grub.cfg present"
    else
        echo -e "${RED}  ✗ grub.cfg NOT found!${RST}"
    fi

    # Modules
    [[ -f "$mnt/boot/grub/i386-pc/fat.mod" ]]     && ok "i386-pc/fat.mod available"
    [[ -f "$mnt/boot/grub/x86_64-efi/fat.mod" ]]  && ok "x86_64-efi/fat.mod available"

    # Usage
    local used
    used=$(du -sh "$mnt" 2>/dev/null | awk '{print $1}')
    ok "Space used: ${WHT}${used}${RST}"
}

print_summary() {
    local disk="$1" scheme="$2" fat_part="$3" fat_uuid="$4"

    echo ""
    box "${GRN}  ✓  GRUB Installation Complete  ✓  ${RST}"
    echo ""
    echo -e "  ${WHT}Disk:${RST}         $disk ($DISK_SIZE_HUMAN) — ${scheme}"

    if [[ "$scheme" == "GPT" ]]; then
        echo -e "  ${WHT}Part 1:${RST}       $(part_name "$disk" 1) — BIOS Boot (ef02) — 1 MiB"
        echo -e "  ${WHT}Part 2:${RST}       $fat_part — FAT32 ESP (ef00) — UUID: ${fat_uuid}"
    else
        echo -e "  ${WHT}Part 1:${RST}       $fat_part — FAT32 — UUID: ${fat_uuid}"
        echo -e "  ${DIM}              GRUB core.img in MBR post-gap${RST}"
    fi

    echo ""
    echo -e "  ${WHT}FAT32 contents:${RST}"
    echo -e "    /EFI/BOOT/BOOTX64.EFI        ← EFI bootloader"
    echo -e "    /boot/grub/grub.cfg           ← shared boot config"
    echo -e "    /boot/grub/i386-pc/*.mod      ← BIOS modules"
    echo -e "    /boot/grub/x86_64-efi/*.mod   ← EFI modules"
    echo -e "    /boot/iso/                    ← drop ISOs here"
    echo ""
    echo -e "  ${WHT}Boot chain (BIOS):${RST}"
    echo -e "    MBR → core.img → search UUID ${fat_uuid} → /boot/grub/grub.cfg"
    echo ""
    echo -e "  ${WHT}Boot chain (EFI):${RST}"
    echo -e "    Firmware → /EFI/BOOT/BOOTX64.EFI → search UUID ${fat_uuid} → /boot/grub/grub.cfg"
    echo ""
    echo -e "  ${CYN}To edit:${RST}  mount $fat_part /mnt && nano /mnt/boot/grub/grub.cfg"
    echo -e "  ${CYN}Add ISO:${RST}  cp distro.iso /mnt/boot/iso/ (then add menuentry)"
    echo ""

    # Loop device reminder
    if [[ "$disk" =~ ^/dev/loop ]]; then
        local backing
        backing=$(losetup -n -O BACK-FILE "$disk" 2>/dev/null | xargs)
        echo -e "  ${YLW}Loop device note:${RST}"
        echo -e "    Backing file: $backing"
        echo -e "    Detach:       losetup -d $disk"
        echo -e "    Reattach:     losetup -fP $backing"
        echo ""
    fi
}


# ═══════════════════════════════════════════════════════════════════
#  MODE 1: GPT — BIOS Boot partition + FAT32 ESP
# ═══════════════════════════════════════════════════════════════════
mode_gpt() {
    echo ""
    box "${MAG}  Mode: GPT — BIOS Boot + FAT32 ESP  ${RST}"

    select_disk

    local available_mb=$((DISK_SIZE_MB - 3))
    [[ $available_mb -le 32 ]] && die "Disk too small (need >35 MiB)"

    select_fat32_size "$available_mb"
    select_grubcfg

    echo ""
    box "${RED}  ⚠  ALL DATA ON ${DISK} WILL BE DESTROYED  ⚠  ${RST}"
    echo ""
    echo -e "  ${WHT}Disk:${RST}       $DISK ($DISK_SIZE_HUMAN)"
    [[ -n "${DISK_MODEL:-}" ]] && echo -e "  ${WHT}Device:${RST}     ${DISK_MODEL}"
    echo -e "  ${WHT}Scheme:${RST}     GPT"
    echo -e "  ${WHT}Part 1:${RST}     BIOS Boot (ef02) — 1 MiB"
    echo -e "  ${WHT}Part 2:${RST}     FAT32 ESP (ef00) — $FAT32_DISPLAY"
    echo -e "  ${WHT}grub.cfg:${RST}   ${CUSTOM_GRUBCFG:-default template}"
    echo -e "  ${WHT}BIOS:${RST}       $([[ "$HAS_BIOS" == true ]] && echo -e "${GRN}yes${RST}" || echo -e "${YLW}skip${RST}")"
    echo -e "  ${WHT}EFI:${RST}        $([[ "$HAS_EFI" == true ]] && echo -e "${GRN}yes${RST}" || echo -e "${YLW}skip${RST}")"
    echo ""
    prompt "Type YES to proceed: " CONFIRM
    [[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 0; }
    echo ""

    box "${CYN}Partitioning (GPT)${RST}"
    sgdisk --zap-all "$DISK" >/dev/null 2>&1 || true

    if [[ "$FAT32_SIZE_MB" -eq 0 ]]; then
        sgdisk \
            --new=1:2048:+1M  --typecode=1:ef02 --change-name=1:"BIOS-Boot" \
            --new=2:0:0       --typecode=2:ef00 --change-name=2:"GRUB-ESP" \
            "$DISK"
    else
        sgdisk \
            --new=1:2048:+1M  --typecode=1:ef02 --change-name=1:"BIOS-Boot" \
            --new=2:0:+${FAT32_SIZE_MB}M --typecode=2:ef00 --change-name=2:"GRUB-ESP" \
            "$DISK"
    fi

    rescan_partitions "$DISK"

    local PART1 PART2
    PART1=$(part_name "$DISK" 1)
    PART2=$(part_name "$DISK" 2)
    wait_for_part "$PART1"
    wait_for_part "$PART2"
    ok "Partitioned: $PART1 (BIOS Boot) + $PART2 (FAT32 ESP)"

    box "${CYN}Formatting FAT32${RST}"
    mkfs.vfat -F 32 -n "GRUB-ESP" "$PART2"
    local FAT_UUID
    FAT_UUID=$(blkid -s UUID -o value "$PART2")
    ok "FAT32 UUID: ${WHT}${FAT_UUID}${RST}"

    box "${CYN}Populating FAT32${RST}"
    local MNT
    MNT=$(mktemp -d /tmp/grub-mnt.XXXXXX)
    mount "$PART2" "$MNT"

    populate_fat32 "$MNT"

    box "${CYN}Installing GRUB (BIOS)${RST}"
    install_bios_grub "$DISK" "$MNT"

    box "${CYN}Installing GRUB (EFI)${RST}"
    install_efi_grub "$MNT" "$FAT_UUID"

    verify_install "$DISK" "$MNT" "$PART1"

    umount "$MNT"; rmdir "$MNT"
    print_summary "$DISK" "GPT" "$PART2" "$FAT_UUID"
}


# ═══════════════════════════════════════════════════════════════════
#  MODE 2: MBR — Single FAT32 partition, GRUB in MBR gap
# ═══════════════════════════════════════════════════════════════════
mode_mbr() {
    echo ""
    box "${MAG}  Mode: MBR — Single FAT32 + GRUB in MBR gap  ${RST}"

    select_disk

    local available_mb=$((DISK_SIZE_MB - 1))
    [[ $available_mb -le 32 ]] && die "Disk too small"

    select_fat32_size "$available_mb"
    select_grubcfg

    echo ""
    box "${RED}  ⚠  ALL DATA ON ${DISK} WILL BE DESTROYED  ⚠  ${RST}"
    echo ""
    echo -e "  ${WHT}Disk:${RST}       $DISK ($DISK_SIZE_HUMAN)"
    [[ -n "${DISK_MODEL:-}" ]] && echo -e "  ${WHT}Device:${RST}     ${DISK_MODEL}"
    echo -e "  ${WHT}Scheme:${RST}     MBR (msdos)"
    echo -e "  ${WHT}Part 1:${RST}     FAT32 — $FAT32_DISPLAY"
    echo -e "  ${DIM}              GRUB core.img in post-MBR gap (sectors 1-2047)${RST}"
    echo -e "  ${WHT}grub.cfg:${RST}   ${CUSTOM_GRUBCFG:-default template}"
    echo -e "  ${WHT}BIOS:${RST}       $([[ "$HAS_BIOS" == true ]] && echo -e "${GRN}yes${RST}" || echo -e "${YLW}skip${RST}")"
    echo -e "  ${WHT}EFI:${RST}        $([[ "$HAS_EFI" == true ]] && echo -e "${GRN}yes${RST}" || echo -e "${YLW}skip${RST}")"
    echo ""
    prompt "Type YES to proceed: " CONFIRM
    [[ "$CONFIRM" == "YES" ]] || { echo "Aborted."; exit 0; }
    echo ""

    box "${CYN}Partitioning (MBR)${RST}"

    # Wipe
    dd if=/dev/zero of="$DISK" bs=512 count=1 conv=notrunc 2>/dev/null
    sgdisk --zap-all "$DISK" >/dev/null 2>&1 || true

    # sfdisk for reliable MBR creation (works with loop devices)
    if [[ "$FAT32_SIZE_MB" -eq 0 ]]; then
        echo -e "label: dos\nstart=2048, type=c, bootable" | sfdisk "$DISK" 2>/dev/null
    else
        local size_sectors=$((FAT32_SIZE_MB * 2048))
        echo -e "label: dos\nstart=2048, size=${size_sectors}, type=c, bootable" | sfdisk "$DISK" 2>/dev/null
    fi

    rescan_partitions "$DISK"

    local PART1
    PART1=$(part_name "$DISK" 1)
    wait_for_part "$PART1"
    ok "MBR partitioned: $PART1 (FAT32, boot flag set)"

    box "${CYN}Formatting FAT32${RST}"
    mkfs.vfat -F 32 -n "GRUB-MBR" "$PART1"
    local FAT_UUID
    FAT_UUID=$(blkid -s UUID -o value "$PART1")
    ok "FAT32 UUID: ${WHT}${FAT_UUID}${RST}"

    box "${CYN}Populating FAT32${RST}"
    local MNT
    MNT=$(mktemp -d /tmp/grub-mnt.XXXXXX)
    mount "$PART1" "$MNT"

    populate_fat32 "$MNT"

    box "${CYN}Installing GRUB (BIOS → MBR gap)${RST}"
    install_bios_grub "$DISK" "$MNT" "--force"

    box "${CYN}Installing GRUB (EFI)${RST}"
    install_efi_grub "$MNT" "$FAT_UUID"

    verify_install "$DISK" "$MNT"

    umount "$MNT"; rmdir "$MNT"
    print_summary "$DISK" "MBR" "$PART1" "$FAT_UUID"
}


# ═══════════════════════════════════════════════════════════════════
#  MODE 3: Repair — Reinstall GRUB on existing disk
# ═══════════════════════════════════════════════════════════════════
mode_repair() {
    echo ""
    box "${MAG}  Mode: Repair — Reinstall GRUB (no format)  ${RST}"
    echo ""
    echo -e "  ${DIM}Reinstalls GRUB boot code and EFI image without formatting.${RST}"
    echo -e "  ${DIM}Your grub.cfg, ISOs, and other files will be preserved.${RST}"

    select_disk

    echo ""
    echo -e "  ${WHT}Current layout of ${DISK}:${RST}"
    echo ""
    lsblk -o NAME,SIZE,FSTYPE,LABEL,UUID "$DISK" 2>/dev/null | sed 's/^/    /'
    echo ""

    local PTTYPE
    PTTYPE=$(blkid -o value -s PTTYPE "$DISK" 2>/dev/null || echo "unknown")
    echo -e "  ${WHT}Partition table:${RST} $PTTYPE"

    prompt "Which partition has /boot/grub? (e.g. $(part_name "$DISK" 1)): " TARGET_PART
    [[ -b "$TARGET_PART" ]] || die "'$TARGET_PART' is not a block device"

    local FSTYPE
    FSTYPE=$(blkid -o value -s TYPE "$TARGET_PART" 2>/dev/null || echo "")
    [[ "$FSTYPE" == "vfat" ]] || warn "Partition is '$FSTYPE', expected 'vfat' (FAT32)"

    local MNT
    MNT=$(mktemp -d /tmp/grub-repair.XXXXXX)
    mount "$TARGET_PART" "$MNT"

    if [[ ! -d "$MNT/boot/grub" ]]; then
        warn "/boot/grub not found on $TARGET_PART"
        echo ""
        echo -e "  ${WHT}What would you like to do?${RST}"
        echo -e "    ${CYN}1)${RST}  Create /boot/grub and populate (modules + default grub.cfg)"
        echo -e "    ${CYN}2)${RST}  Abort"
        echo ""
        prompt "Select [1/2]: " REPAIR_ACTION
        if [[ "$REPAIR_ACTION" == "1" ]]; then
            select_grubcfg
            populate_fat32 "$MNT"
        else
            umount "$MNT"; rmdir "$MNT"
            echo "Aborted."; exit 0
        fi
    else
        ok "Found /boot/grub on $TARGET_PART"

        echo ""
        echo -e "  ${WHT}Refresh GRUB modules?${RST}"
        echo -e "    ${CYN}1)${RST}  Yes — update modules (preserves grub.cfg and ISOs)"
        echo -e "    ${CYN}2)${RST}  No  — only reinstall boot code"
        echo ""
        prompt "Select [1/2]: " REFRESH_CHOICE

        if [[ "$REFRESH_CHOICE" == "1" ]]; then
            local had_cfg=false
            [[ -f "$MNT/boot/grub/grub.cfg" ]] && had_cfg=true

            if [[ "$HAS_BIOS" == true ]]; then
                rm -f "$MNT/boot/grub/i386-pc/"*.mod "$MNT/boot/grub/i386-pc/"*.lst 2>/dev/null || true
                mkdir -p "$MNT/boot/grub/i386-pc"
                cp "$GRUB_BIOS_DIR"/*.mod "$MNT/boot/grub/i386-pc/" 2>/dev/null || true
                cp "$GRUB_BIOS_DIR"/*.lst "$MNT/boot/grub/i386-pc/" 2>/dev/null || true
                ok "Refreshed i386-pc modules"
            fi

            if [[ "$HAS_EFI" == true ]]; then
                rm -f "$MNT/boot/grub/x86_64-efi/"*.mod "$MNT/boot/grub/x86_64-efi/"*.lst 2>/dev/null || true
                mkdir -p "$MNT/boot/grub/x86_64-efi"
                cp "$GRUB_EFI_DIR"/*.mod "$MNT/boot/grub/x86_64-efi/" 2>/dev/null || true
                cp "$GRUB_EFI_DIR"/*.lst "$MNT/boot/grub/x86_64-efi/" 2>/dev/null || true
                ok "Refreshed x86_64-efi modules"
            fi

            mkdir -p "$MNT/boot/grub/fonts"
            [[ -f /usr/share/grub/unicode.pf2 ]] && cp /usr/share/grub/unicode.pf2 "$MNT/boot/grub/fonts/"

            if [[ "$had_cfg" == true ]]; then
                ok "Existing grub.cfg preserved"
            else
                warn "No grub.cfg found — generating default"
                CUSTOM_GRUBCFG=""
                install_grubcfg "$MNT"
            fi
        fi
    fi

    mkdir -p "$MNT/EFI/BOOT"

    local FAT_UUID
    FAT_UUID=$(blkid -s UUID -o value "$TARGET_PART")

    echo ""
    box "${YLW}  Repair: Reinstalling GRUB boot code  ${RST}"
    echo ""
    echo -e "  ${WHT}Disk:${RST}       $DISK"
    [[ -n "${DISK_MODEL:-}" ]] && echo -e "  ${WHT}Device:${RST}     ${DISK_MODEL}"
    echo -e "  ${WHT}Partition:${RST}  $TARGET_PART (UUID: $FAT_UUID)"
    echo -e "  ${WHT}Table:${RST}      $PTTYPE"
    echo -e "  ${WHT}Action:${RST}     Reinstall BIOS + EFI boot code"
    echo -e "  ${DIM}            No data will be formatted or deleted${RST}"
    echo ""
    prompt "Type YES to proceed: " CONFIRM
    [[ "$CONFIRM" == "YES" ]] || { umount "$MNT"; rmdir "$MNT"; echo "Aborted."; exit 0; }
    echo ""

    if [[ "$HAS_BIOS" == true ]]; then
        box "${CYN}Reinstalling GRUB (BIOS)${RST}"

        local bios_flags="--force"
        if [[ "$PTTYPE" == "gpt" ]]; then
            if sgdisk -p "$DISK" 2>/dev/null | grep -q "EF02"; then
                bios_flags=""
                ok "Found BIOS Boot partition (ef02)"
            else
                warn "No BIOS Boot partition — using --force (MBR gap)"
            fi
        fi

        install_bios_grub "$DISK" "$MNT" "$bios_flags"
    fi

    if [[ "$HAS_EFI" == true ]]; then
        box "${CYN}Reinstalling GRUB (EFI)${RST}"
        install_efi_grub "$MNT" "$FAT_UUID"
    fi

    verify_install "$DISK" "$MNT"

    umount "$MNT"; rmdir "$MNT"

    echo ""
    box "${GRN}  ✓  GRUB Repair Complete  ✓  ${RST}"
    echo ""
    echo -e "  ${WHT}Disk:${RST}       $DISK ($PTTYPE)"
    echo -e "  ${WHT}Partition:${RST}  $TARGET_PART — UUID: ${FAT_UUID}"
    echo -e "  ${DIM}  All existing data preserved.${RST}"
    echo ""

    if [[ "$DISK" =~ ^/dev/loop ]]; then
        local backing
        backing=$(losetup -n -O BACK-FILE "$DISK" 2>/dev/null | xargs)
        echo -e "  ${YLW}Loop device:${RST} $backing"
        echo -e "  ${DIM}  Detach: losetup -d $DISK${RST}"
        echo ""
    fi
}


# ═══════════════════════════════════════════════════════════════════
#  MAIN MENU
# ═══════════════════════════════════════════════════════════════════
clear 2>/dev/null || true
echo ""
box "${WHT}  gLiTcH GRUB Multiboot Setup  ${RST}"
echo ""
echo -e "  ${WHT}Available GRUB platforms:${RST}"
[[ "$HAS_BIOS" == true ]]  && echo -e "    ${GRN}✓${RST} BIOS (i386-pc)"      || echo -e "    ${RED}✗${RST} BIOS (i386-pc)"
[[ "$HAS_EFI" == true ]]   && echo -e "    ${GRN}✓${RST} EFI  (x86_64-efi)"   || echo -e "    ${RED}✗${RST} EFI  (x86_64-efi)"
echo ""
echo -e "  ${WHT}Select installation mode:${RST}"
echo ""
echo -e "    ${CYN}1)${RST}  ${BLD}GPT disk${RST} — BIOS Boot partition + FAT32 ESP"
echo -e "        ${DIM}Best for: modern systems, >2TB disks, UEFI + legacy BIOS${RST}"
echo ""
echo -e "    ${CYN}2)${RST}  ${BLD}MBR disk${RST} — Single FAT32 partition, GRUB in MBR gap"
echo -e "        ${DIM}Best for: max compatibility, old BIOS, simple layout${RST}"
echo ""
echo -e "    ${CYN}3)${RST}  ${BLD}Repair${RST}   — Reinstall GRUB on existing disk (no format)"
echo -e "        ${DIM}Fix broken boot without losing data, grub.cfg, or ISOs${RST}"
echo ""
echo -e "    ${CYN}q)${RST}  Quit"
echo ""
prompt "Select [1/2/3/q]: " MODE

case "$MODE" in
    1) mode_gpt    ;;
    2) mode_mbr    ;;
    3) mode_repair ;;
    q|Q) echo "Bye."; exit 0 ;;
    *) die "Invalid selection" ;;
esac
