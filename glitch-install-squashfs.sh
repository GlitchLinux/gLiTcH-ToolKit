#!/bin/bash

# Configuration
LUKS_MAPPER_NAME="glitch_luks"
TARGET_MOUNT="/mnt/glitch_install"
SQUASHFS_IMAGE="/run/live/medium/live/filesystem.squashfs"

# Required dependencies
DEPENDENCIES="wget cryptsetup-bin cryptsetup-initramfs grub-common grub-pc-bin grub-efi-amd64-bin parted squashfs-tools dosfstools mtools pv"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo -e "${RED}This script must be run as root!${NC}" >&2
    exit 1
fi

# Header

echo -e "${YELLOW}:: GLITCH INSTALLER ::${NC}\n"

# Install dependencies
echo -e "${BLUE}[*]${NC} Installing required dependencies..."
if ! apt update || ! apt install -y $DEPENDENCIES; then
    echo -e "${RED}[!] Failed to install dependencies!${NC}" >&2
    exit 1
fi

# Function to clean up
cleanup() {
    echo -e "\n${YELLOW}[?]${NC} Cleanup options:"
    echo -e "1) Keep mounts active for chroot access"
    echo -e "2) Clean up everything and exit"
    read -p "Choose option [1-2]: " CLEANUP_CHOICE
    
    case $CLEANUP_CHOICE in
        1)
            echo -e "${YELLOW}[!] Keeping mounts active. Remember to manually clean up later!${NC}"
            echo -e "Use: umount -R $TARGET_MOUNT"
            [ "$ENCRYPTED" = "yes" ] && echo "cryptsetup close $LUKS_MAPPER_NAME"
            ;;
        2)
            echo -e "${BLUE}[*]${NC} Cleaning up..."
            # Unmount all mounted filesystems
            for mountpoint in "${TARGET_MOUNT}/boot/efi" "${TARGET_MOUNT}/dev/pts" "${TARGET_MOUNT}/dev" \
                            "${TARGET_MOUNT}/proc" "${TARGET_MOUNT}/sys" "${TARGET_MOUNT}/run"; do
                if mountpoint -q "$mountpoint"; then
                    umount -R "$mountpoint" 2>/dev/null
                fi
            done
            
            # Unmount the main filesystem
            if mountpoint -q "$TARGET_MOUNT"; then
                umount -R "$TARGET_MOUNT" 2>/dev/null
            fi
            
            # Close LUKS if open
            if [ "$ENCRYPTED" = "yes" ] && cryptsetup status "$LUKS_MAPPER_NAME" &>/dev/null; then
                cryptsetup close "$LUKS_MAPPER_NAME"
            fi
            
            # Remove mount point if empty
            [ -d "$TARGET_MOUNT" ] && rmdir "$TARGET_MOUNT" 2>/dev/null
            ;;
        *)
            echo -e "${RED}[!] Invalid choice, keeping mounts active.${NC}"
            ;;
    esac
}

trap cleanup EXIT

find_kernel_initrd() {
    local target_root="$1"
    
    KERNEL_VERSION=$(ls -1 "${target_root}/boot" | grep -E "vmlinuz-[0-9]" | sort -V | tail -n1 | sed 's/vmlinuz-//')
    [ -z "$KERNEL_VERSION" ] && { echo -e "${RED}[!] ERROR: Kernel not found!${NC}" >&2; exit 1; }
    
    INITRD=""
    for pattern in "initrd.img-${KERNEL_VERSION}" "initramfs-${KERNEL_VERSION}.img" "initrd-${KERNEL_VERSION}.gz"; do
        [ -f "${target_root}/boot/${pattern}" ] && INITRD="$pattern" && break
    done
    [ -z "$INITRD" ] && { echo -e "${RED}[!] ERROR: Initrd not found for kernel ${KERNEL_VERSION}${NC}" >&2; exit 1; }
    
    echo -e "${GREEN}[+]${NC} Found kernel: vmlinuz-${KERNEL_VERSION}"
    echo -e "${GREEN}[+]${NC} Found initrd: ${INITRD}"
}

get_uuid() {
    local device="$1"
    blkid -s UUID -o value "$device"
}

configure_system_files() {
    local target_root="$1"
    local target_device="$2"
    
    if [ "$ENCRYPTED" = "yes" ]; then
        # Get actual UUIDs from the system for encrypted setup
        local root_part_uuid=$(get_uuid "$ROOT_PART")
        local root_fs_uuid=$(get_uuid "/dev/mapper/$LUKS_MAPPER_NAME")
        
        if [ -z "$root_part_uuid" ] || [ -z "$root_fs_uuid" ]; then
            echo -e "${RED}[!] ERROR: Failed to get UUIDs for partitions!${NC}" >&2
            exit 1
        fi

        # Verify UUIDs are correct
        echo -e "${BLUE}[*]${NC} Verifying UUIDs:"
        echo -e "- Partition UUID: ${root_part_uuid}"
        echo -e "- Filesystem UUID: ${root_fs_uuid}"
        lsblk -o NAME,UUID | grep -E "(${LUKS_MAPPER_NAME}|${ROOT_PART##*/})"

        # Create /etc/crypttab
        echo -e "${BLUE}[*]${NC} Creating /etc/crypttab..."
        cat > "${target_root}/etc/crypttab" << EOF
${LUKS_MAPPER_NAME} UUID=${root_part_uuid} none luks,discard
EOF

        # Configure cryptsetup for initramfs
        echo -e "${BLUE}[*]${NC} Configuring cryptsetup for initramfs..."
        mkdir -p "${target_root}/etc/initramfs-tools/conf.d"
        cat > "${target_root}/etc/initramfs-tools/conf.d/cryptsetup" << EOF
KEYFILE_PATTERN=/etc/luks/*.keyfile
UMASK=0077
EOF

        # Add necessary modules to initramfs
        echo -e "${BLUE}[*]${NC} Adding required modules to initramfs..."
        cat > "${target_root}/etc/initramfs-tools/modules" << EOF
dm-crypt
cryptodisk
luks
aes
sha256
ext4
EOF

        # Create /etc/fstab with correct UUIDs
        echo -e "${BLUE}[*]${NC} Creating /etc/fstab..."
        cat > "${target_root}/etc/fstab" << EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=${root_fs_uuid} /               ext4    errors=remount-ro 0       1
EOF

        # Update GRUB configuration
        echo -e "${BLUE}[*]${NC} Updating GRUB configuration..."
        find_kernel_initrd "$target_root"
        
        # Ensure GRUB cryptodisk support is enabled
        echo -e "${BLUE}[*]${NC} Configuring GRUB_ENABLE_CRYPTODISK..."
        mkdir -p "${target_root}/etc/default"
        if [ -f "${target_root}/etc/default/grub" ]; then
            sed -i 's/^GRUB_ENABLE_CRYPTODISK=.*/GRUB_ENABLE_CRYPTODISK=y/' "${target_root}/etc/default/grub"
        fi
        if ! grep -q '^GRUB_ENABLE_CRYPTODISK=y' "${target_root}/etc/default/grub"; then
            echo "GRUB_ENABLE_CRYPTODISK=y" >> "${target_root}/etc/default/grub"
        fi
        
        mkdir -p "${target_root}/boot/grub"
        cat > "${target_root}/boot/grub/grub.cfg" << EOF
loadfont /usr/share/grub/unicode.pf2

set gfxmode=640x480
load_video
insmod gfxterm
set locale_dir=/boot/grub/locale
set lang=C
insmod gettext
background_image -m stretch /boot/grub/grub.png
terminal_output gfxterm
insmod png
if background_image /boot/grub/grub.png; then
    true
else
    set menu_color_normal=cyan/blue
    set menu_color_highlight=white/blue
fi

menuentry "Glitch Linux" {
    insmod part_gpt
    insmod cryptodisk
    insmod luks
    insmod ext2
    
    cryptomount -u ${root_part_uuid}
    set root='(crypto0)'
    search --no-floppy --fs-uuid --set=root ${root_fs_uuid}
    linux /boot/vmlinuz-${KERNEL_VERSION} root=UUID=${root_fs_uuid} cryptdevice=UUID=${root_part_uuid}:${LUKS_MAPPER_NAME} ro quiet
    initrd /boot/${INITRD}
}

menuentry "Glitch Linux (recovery mode)" {
    insmod part_gpt
    insmod cryptodisk
    insmod luks
    insmod ext2
    
    cryptomount -u ${root_part_uuid}
    set root='(crypto0)'
    search --no-floppy --fs-uuid --set=root ${root_fs_uuid}
    linux /boot/vmlinuz-${KERNEL_VERSION} root=UUID=${root_fs_uuid} cryptdevice=UUID=${root_part_uuid}:${LUKS_MAPPER_NAME} ro single
    initrd /boot/${INITRD}
}
EOF
    else
        # Unencrypted setup
        local root_fs_uuid=$(get_uuid "$ROOT_PART")
        
        if [ -z "$root_fs_uuid" ]; then
            echo -e "${RED}[!] ERROR: Failed to get UUID for root partition!${NC}" >&2
            exit 1
        fi

        # Create /etc/fstab
        echo -e "${BLUE}[*]${NC} Creating /etc/fstab..."
        cat > "${target_root}/etc/fstab" << EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=${root_fs_uuid} /               ext4    errors=remount-ro 0       1
EOF

        # Update GRUB configuration
        echo -e "${BLUE}[*]${NC} Updating GRUB configuration..."
        find_kernel_initrd "$target_root"
        
        mkdir -p "${target_root}/boot/grub"
        cat > "${target_root}/boot/grub/grub.cfg" << EOF
loadfont /usr/share/grub/unicode.pf2

set gfxmode=640x480
load_video
insmod gfxterm
set locale_dir=/boot/grub/locale
set lang=C
insmod gettext
background_image -m stretch /boot/grub/grub.png
terminal_output gfxterm
insmod png
if background_image /boot/grub/grub.png; then
    true
else
    set menu_color_normal=cyan/blue
    set menu_color_highlight=white/blue
fi

menuentry "Glitch Linux" {
    insmod part_gpt
    insmod ext2
    
    search --no-floppy --fs-uuid --set=root ${root_fs_uuid}
    linux /boot/vmlinuz-${KERNEL_VERSION} root=UUID=${root_fs_uuid} ro quiet
    initrd /boot/${INITRD}
}

menuentry "Glitch Linux (recovery mode)" {
    insmod part_gpt
    insmod ext2
    
    search --no-floppy --fs-uuid --set=root ${root_fs_uuid}
    linux /boot/vmlinuz-${KERNEL_VERSION} root=UUID=${root_fs_uuid} ro single
    initrd /boot/${INITRD}
}
EOF
    fi

    echo -e "${BLUE}[*]${NC} Initramfs will be updated after chroot environment is prepared"
}

prepare_chroot() {
    local target_root="$1"
    local target_device="$2"
    
    echo -e "${BLUE}[*]${NC} Mounting required filesystems for chroot..."
    mount --bind /dev "${target_root}/dev" || { echo -e "${RED}[!] Failed to mount /dev${NC}"; exit 1; }
    mount --bind /dev/pts "${target_root}/dev/pts" || { echo -e "${RED}[!] Failed to mount /dev/pts${NC}"; exit 1; }
    mount -t proc proc "${target_root}/proc" || { echo -e "${RED}[!] Failed to mount /proc${NC}"; exit 1; }
    mount -t sysfs sys "${target_root}/sys" || { echo -e "${RED}[!] Failed to mount /sys${NC}"; exit 1; }
    mount -t tmpfs tmpfs "${target_root}/run" || { echo -e "${RED}[!] Failed to mount /run${NC}"; exit 1; }
    
    [ -e "/etc/resolv.conf" ] && cp --dereference /etc/resolv.conf "${target_root}/etc/"
    
    cat > "${target_root}/chroot_prep.sh" << EOF
#!/bin/bash
# Set up basic system
echo "glitch" > /etc/hostname
echo "127.0.1.1 glitch" >> /etc/hosts

# Install required packages in chroot
echo -e "${BLUE}[*]${NC} Installing required packages..."
apt-get update
[ "$ENCRYPTED" = "yes" ] && apt-get install -y cryptsetup-initramfs cryptsetup

# Reinstall the latest kernel to ensure proper boot files
echo -e "${BLUE}[*]${NC} Reinstalling kernel..."
KERNEL_PKG=\$(dpkg -l | grep '^ii.*linux-image' | awk '{print \$2}' | sort -V | tail -n1)
apt-get install --reinstall -y \$KERNEL_PKG

# First update initramfs with proper mounts available
echo -e "${BLUE}[*]${NC} Updating initramfs..."
update-initramfs -u -k all || { echo -e "${RED}[!] Initramfs update failed${NC}"; exit 1; }

# Then install GRUB
echo -e "${BLUE}[*]${NC} Installing GRUB..."
if [ -d "/sys/firmware/efi" ]; then
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=GRUB --recheck || { echo -e "${RED}[!] EFI GRUB install failed${NC}"; exit 1; }
else
    grub-install ${target_device} --recheck || { echo -e "${RED}[!] BIOS GRUB install failed${NC}"; exit 1; }
fi
update-grub || { echo -e "${RED}[!] GRUB update failed${NC}"; exit 1; }

# Verify cryptsetup in initramfs if encrypted
if [ "$ENCRYPTED" = "yes" ]; then
    echo -e "${BLUE}[*]${NC} Verifying cryptsetup in initramfs..."
    lsinitramfs /boot/initrd.img-*\$(uname -r) | grep cryptsetup || echo -e "${YELLOW}[!] Warning: cryptsetup not found in initramfs${NC}"
fi

# Clean up
rm -f /chroot_prep.sh
EOF
    chmod +x "${target_root}/chroot_prep.sh"
    
    echo -e "\n${GREEN}[+]${NC} Chroot environment ready!"
    echo -e "To complete setup:"
    echo -e "1. chroot ${target_root}"
    echo -e "2. Run /chroot_prep.sh"
    echo -e "3. Exit and reboot"
    
    # Offer to automatically run chroot commands
    read -p "$(echo -e ${YELLOW}"Would you like to automatically run the chroot commands now? [y/N] "${NC})" AUTO_CHROOT
    if [[ "$AUTO_CHROOT" =~ [Yy] ]]; then
        echo -e "${BLUE}[*]${NC} Running chroot commands..."
        if ! chroot "${target_root}" /bin/bash -c "/chroot_prep.sh"; then
            echo -e "${RED}[!] Chroot preparation failed!${NC}" >&2
            exit 1
        fi
        echo -e "${GREEN}[+]${NC} Chroot preparation completed successfully!"
    else
        echo -e "${YELLOW}[!]${NC} You can manually run the chroot commands later with:"
        echo -e "  chroot ${target_root} /bin/bash"
        echo -e "  /chroot_prep.sh"
    fi
}

partition_disk() {
    local target_device="$1"
    
    # Wipe the disk
    echo -e "${BLUE}[*]${NC} Wiping disk..."
    wipefs -a "$target_device"
    
    # Create GPT partition table
    echo -e "${BLUE}[*]${NC} Creating GPT partition table..."
    parted -s "$target_device" mklabel gpt
    
    # Create EFI partition (100MB)
    echo -e "${BLUE}[*]${NC} Creating EFI partition (100MB)..."
    parted -s "$target_device" mkpart primary fat32 1MiB 101MiB
    parted -s "$target_device" set 1 esp on
    
    # Create root partition (remaining space)
    echo -e "${BLUE}[*]${NC} Creating root partition..."
    parted -s "$target_device" mkpart primary ext4 101MiB 100%
    
    # Wait for partitions to settle
    sleep 2
    partprobe "$target_device"
    sleep 2
    
    # Determine partition names
    if [[ "$target_device" =~ "nvme" ]]; then
        EFI_PART="${target_device}p1"
        ROOT_PART="${target_device}p2"
    else
        EFI_PART="${target_device}1"
        ROOT_PART="${target_device}2"
    fi
    
    # Format EFI partition
    echo -e "${BLUE}[*]${NC} Formatting EFI partition as FAT32..."
    mkfs.vfat -F32 "$EFI_PART"
    
    if [ "$ENCRYPTED" = "yes" ]; then
        # Set up LUKS encryption
        echo -e "${BLUE}[*]${NC} Setting up LUKS encryption on root partition..."
        cryptsetup luksFormat --type luks1 -v -y "$ROOT_PART"
        echo -e "${BLUE}[*]${NC} Opening encrypted partition..."
        cryptsetup open "$ROOT_PART" "$LUKS_MAPPER_NAME"
        
        # Format the encrypted partition
        echo -e "${BLUE}[*]${NC} Formatting encrypted partition as ext4..."
        mkfs.ext4 "/dev/mapper/$LUKS_MAPPER_NAME"
    else
        # Format root partition directly
        echo -e "${BLUE}[*]${NC} Formatting root partition as ext4..."
        mkfs.ext4 "$ROOT_PART"
    fi
}

install_system() {
    local target_root="$1"
    
    # Check if SquashFS image exists
    if [ ! -f "$SQUASHFS_IMAGE" ]; then
        echo -e "${RED}[!] ERROR: SquashFS image not found at $SQUASHFS_IMAGE${NC}" >&2
        exit 1
    fi
    
    echo -e "${BLUE}[*]${NC} Installing system from SquashFS image..."
    
    # Create temporary directory for unsquashing
    TEMP_DIR=$(mktemp -d)
    
    # Unsquash the filesystem
    echo -e "${BLUE}[*]${NC} Extracting SquashFS image..."
    if ! unsquashfs -f -d "$TEMP_DIR" "$SQUASHFS_IMAGE"; then
        echo -e "${RED}[!] Failed to extract SquashFS image!${NC}" >&2
        rm -rf "$TEMP_DIR"
        exit 1
    fi
    
    # Copy files to target
    echo -e "${BLUE}[*]${NC} Copying files to target..."
    cp -a "$TEMP_DIR"/* "$target_root"/
    
    # Clean up temporary directory
    rm -rf "$TEMP_DIR"
    
    echo -e "${GREEN}[+]${NC} System installation complete."
}

main_install() {
    # List available disks
    echo -e "\n${BLUE}[*]${NC} Available disks:"
    lsblk -d -o NAME,SIZE,MODEL | grep -v "NAME"
    
    # Get target device
    read -p "$(echo -e ${YELLOW}"Enter target device (e.g., /dev/sdX): "${NC})" TARGET_DEVICE
    [ ! -b "$TARGET_DEVICE" ] && { echo -e "${RED}[!] Invalid device!${NC}"; exit 1; }
    read -p "$(echo -e ${RED}"This will ERASE ${TARGET_DEVICE}! Continue? (yes/no): "${NC})" CONFIRM
    [ "$CONFIRM" != "yes" ] && exit 0
    
    # Ask for encryption
    read -p "$(echo -e ${YELLOW}"Enable disk encryption? (yes/no) [default: yes]: "${NC})" ENCRYPTED
    ENCRYPTED=${ENCRYPTED:-yes}
    
    # Partition and format disk
    partition_disk "$TARGET_DEVICE"
    
    # Mount the filesystems
    echo -e "${BLUE}[*]${NC} Mounting filesystems..."
    mkdir -p "$TARGET_MOUNT"
    
    if [ "$ENCRYPTED" = "yes" ]; then
        mount "/dev/mapper/$LUKS_MAPPER_NAME" "$TARGET_MOUNT" || { echo -e "${RED}[!] Failed to mount encrypted root!${NC}"; exit 1; }
    else
        mount "$ROOT_PART" "$TARGET_MOUNT" || { echo -e "${RED}[!] Failed to mount root partition!${NC}"; exit 1; }
    fi
    
    mkdir -p "${TARGET_MOUNT}/boot/efi"
    mount "$EFI_PART" "${TARGET_MOUNT}/boot/efi" || { echo -e "${RED}[!] Failed to mount EFI partition!${NC}"; exit 1; }
    
    # Install system from SquashFS
    install_system "$TARGET_MOUNT"
    
    configure_system_files "$TARGET_MOUNT" "$TARGET_DEVICE"
    prepare_chroot "$TARGET_MOUNT" "$TARGET_DEVICE"

    # Keep system running for chroot access if not automated
    if [[ ! "$AUTO_CHROOT" =~ [Yy] ]]; then
        while true; do
            read -p "$(echo -e ${YELLOW}"Enter 'exit' when done with chroot to cleanup: "${NC})" cmd
            [ "$cmd" = "exit" ] && break
        done
    fi
}

main_install