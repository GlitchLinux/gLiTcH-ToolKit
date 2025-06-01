#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Function to list disks and partitions
list_devices() {
    echo "Available disks and partitions:"
    lsblk -o NAME,SIZE,TYPE,MOUNTPOINT,FSTYPE,MODEL | grep -v 'loop'
    echo ""
    echo "Note: You can also specify a disk image file (e.g., /path/to/image.img)"
}

# Show available disks and partitions
list_devices

# Ask user for target
while true; do
    read -rp "Enter the USB partition to use (e.g. /dev/sde1) or disk image path: " TARGET
    
    # Check if target is a disk image
    if [[ "$TARGET" == *.img ]]; then
        if [ -f "$TARGET" ]; then
            # Setup loop device for the image
            echo "Setting up loop device for $TARGET..."
            LOOP_DEV=$(losetup -f --show -P "$TARGET")
            if [ -z "$LOOP_DEV" ]; then
                echo "Error: Failed to setup loop device"
                exit 1
            fi
            USB_PARTITION="${LOOP_DEV}p1"
            USB_DEVICE="$LOOP_DEV"
            IMAGE_MODE=1
            break
        else
            echo "Error: Image file $TARGET does not exist"
            continue
        fi
    elif [ -e "$TARGET" ]; then
        # Handle regular device/partition
        USB_PARTITION="$TARGET"
        USB_DEVICE=$(echo "$TARGET" | sed 's/[0-9]*$//')
        if [ "$USB_DEVICE" = "$USB_PARTITION" ]; then
            echo "Error: You must specify a partition, not a whole disk"
            continue
        fi
        IMAGE_MODE=0
        break
    else
        echo "Error: Target $TARGET does not exist. Please try again."
        list_devices
    fi
done

# Confirm with user
echo ""
echo "WARNING: This will modify $USB_PARTITION"
echo "All data on this target will be erased!"
read -rp "Are you sure you want to continue? (y/N): " confirm
if [ "${confirm,,}" != "y" ]; then
    # Clean up loop device if we created one
    if [ -n "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV"
    fi
    echo "Operation cancelled"
    exit 0
fi

# Install required packages
echo "Installing required packages..."
apt-get update
apt-get install -y grub-efi-amd64-bin grub-pc-bin git wget unzip mtools lzma

# Clone and prepare both repositories
echo "Cloning repositories..."
rm -rf grub2-filemanager Multibooters-agFM-rEFInd-GRUBFM 2>/dev/null
git clone https://github.com/a1ive/grub2-filemanager.git
git clone https://github.com/GlitchLinux/Multibooters-agFM-rEFInd-GRUBFM.git

# Build the main grub2-filemanager project
echo "Building grub2-filemanager..."
cd grub2-filemanager || exit
./update_grub2.sh
./build.sh
cd ..

# Extract additional files
echo "Extracting additional files..."
cd Multibooters-agFM-rEFInd-GRUBFM || exit
tar --lzma -xvf GRUB_FM_FILES.tar.lzma
cd ..

# Prepare the USB partition
echo "Preparing target partition..."

# Unmount if mounted
umount "$USB_PARTITION" 2>/dev/null

# Format as FAT32 (keep existing partition)
echo "Formatting partition as FAT32..."
mkfs.fat -F32 "$USB_PARTITION"

# Create mount point and mount
echo "Mounting partition..."
MOUNT_POINT="/mnt/usb"
mkdir -p "$MOUNT_POINT"
mount "$USB_PARTITION" "$MOUNT_POINT"

# Create organized directories for boot files
echo "Creating boot directories..."
mkdir -p "$MOUNT_POINT/boot/{isos,img,efi}"
mkdir -p "$MOUNT_POINT/live"

# Install GRUB for BIOS (to partition) - handle loop devices differently
echo "Installing GRUB for BIOS..."
if [ "$IMAGE_MODE" -eq 1 ]; then
    echo "Using alternative BIOS boot installation for disk image..."
    # Manually create BIOS boot files for loop device
    mkdir -p "$MOUNT_POINT/boot/grub/i386-pc"
    cp /usr/lib/grub/i386-pc/*.{mod,lst} "$MOUNT_POINT/boot/grub/i386-pc/"
    grub-mkimage -O i386-pc -o "$MOUNT_POINT/boot/grub/i386-pc/core.img" \
        -p /boot/grub biosdisk part_msdos fat
    cat /usr/lib/grub/i386-pc/lnxboot.img "$MOUNT_POINT/boot/grub/i386-pc/core.img" > \
        "$MOUNT_POINT/boot/grub/i386-pc/boot.img"
else
    grub-install --target=i386-pc --boot-directory="$MOUNT_POINT/boot" --force "$USB_DEVICE"
fi

# Create BIOS GRUB configuration that directly boots agFM
echo "Creating BIOS GRUB configuration..."
cat > "$MOUNT_POINT/boot/grub/grub.cfg" <<'EOF'
# BIOS GRUB CONFIG - DO NOT EDIT MANUALLY
# This immediately loads agFM without showing a menu

set default=0
set timeout=0

if [ -f /boot/grub/loadfm ]; then
    linux /boot/grub/loadfm
    initrd /boot/grub/grubfm.iso
    boot
else
    echo "GRUB File Manager files missing!"
    sleep 5
fi
EOF

# Install GRUB for UEFI
echo "Installing GRUB for UEFI..."
mkdir -p "$MOUNT_POINT/EFI/BOOT"
grub-mkimage -p /efi/boot -O x86_64-efi -o "$MOUNT_POINT/EFI/BOOT/grubx64.efi" \
    all_video boot btrfs cat chain configfile echo efifwsetup efinet ext2 fat font \
    gfxmenu gfxterm gzio halt hfsplus iso9660 jpeg keystatus loadenv loopback linux \
    lsefimmap lsefi lsefisystab lssal memdisk minicmd normal ntfs part_apple part_msdos \
    part_gpt password_pbkdf2 png probe reboot regexp search search_fs_uuid search_fs_file \
    search_label sleep smbios squash4 test true video xfs zstd

# Copy files from both repositories
echo "Copying files..."

# From grub2-filemanager
if [ -d "grub2-filemanager/build" ]; then
    cp -r grub2-filemanager/build/* "$MOUNT_POINT/boot/grub/"
fi
if [ -f "grub2-filemanager/grubfm.iso" ]; then
    cp grub2-filemanager/grubfm.iso "$MOUNT_POINT/boot/grub/"
fi

# From Multibooters-agFM-rEFInd-GRUBFM
cp Multibooters-agFM-rEFInd-GRUBFM/grubfmx64.efi "$MOUNT_POINT/EFI/BOOT/"
cp Multibooters-agFM-rEFInd-GRUBFM/grubfmia32.efi "$MOUNT_POINT/EFI/BOOT/"
cp Multibooters-agFM-rEFInd-GRUBFM/grubfmaa64.efi "$MOUNT_POINT/EFI/BOOT/"
cp Multibooters-agFM-rEFInd-GRUBFM/grubfm.elf "$MOUNT_POINT/boot/grub/"
cp Multibooters-agFM-rEFInd-GRUBFM/grubfm_multiarch.iso "$MOUNT_POINT/boot/grub/"
cp Multibooters-agFM-rEFInd-GRUBFM/loadfm "$MOUNT_POINT/boot/grub/"
cp Multibooters-agFM-rEFInd-GRUBFM/fmldr "$MOUNT_POINT/"
cp Multibooters-agFM-rEFInd-GRUBFM/ventoy.dat "$MOUNT_POINT/"
cp Multibooters-agFM-rEFInd-GRUBFM/efi.img "$MOUNT_POINT/"

# Create UEFI configuration that directly boots agFM
echo "Creating UEFI configuration..."
mkdir -p "$MOUNT_POINT/efi/boot"
cat > "$MOUNT_POINT/efi/boot/grub.cfg" <<'EOF'
# Directly load agFM for UEFI
if [ -f /efi/boot/grubfmx64.efi ]; then
    chainloader /efi/boot/grubfmx64.efi
    boot
else
    echo "GRUB File Manager UEFI version not found!"
    sleep 5
fi
EOF

# Set up UEFI fallback entries
echo "Setting up UEFI fallback entries..."
cp "$MOUNT_POINT/EFI/BOOT/grubfmx64.efi" "$MOUNT_POINT/EFI/BOOT/bootx64.efi"
cp "$MOUNT_POINT/EFI/BOOT/grubfmia32.efi" "$MOUNT_POINT/EFI/BOOT/bootia32.efi"
cp "$MOUNT_POINT/EFI/BOOT/grubfmaa64.efi" "$MOUNT_POINT/EFI/BOOT/bootaa64.efi"

# Create the add-bootables helper script
echo "Creating add-bootables.sh helper script..."
cat > "$MOUNT_POINT/add-bootables.sh" <<'EOF'
#!/bin/bash
# GRUB agFM Bootable Files Helper
# Safe way to add bootable files without breaking core functionality

if [ "$(id -u)" -ne 0 ]; then
    echo "Please run as root" >&2
    exit 1
fi

MOUNT_POINT=$(findmnt -n -o TARGET "$1" 2>/dev/null || echo "$PWD")
GRUB_DIR="$MOUNT_POINT/boot/grub"

# Function to add standard ISO
add_iso() {
    read -p "Enter path to ISO file: " ISO_PATH
    if [ ! -f "$ISO_PATH" ]; then
        echo "Error: File not found!"
        return 1
    fi
    
    echo "Copying ISO file..."
    cp "$ISO_PATH" "$MOUNT_POINT/boot/isos/"
    
    # Add to ISO menu
    ISO_NAME=$(basename "$ISO_PATH")
    cat >> "$GRUB_DIR/iso-menu.cfg" <<CFG
menuentry "$ISO_NAME" {
    set isofile="/boot/isos/$ISO_NAME"
    loopback loop \$isofile
    root=(loop)
    configfile /boot/grub/loopback.cfg || chainloader (loop)/EFI/BOOT/bootx64.efi || boot
}
CFG
    echo "Added $ISO_NAME to boot menu"
}

# Function to add Linux Live ISO (deconstructed)
add_live_iso() {
    read -p "Enter path to Linux Live ISO: " ISO_PATH
    if [ ! -f "$ISO_PATH" ]; then
        echo "Error: File not found!"
        return 1
    fi
    
    DISTRO_NAME=$(basename "$ISO_PATH" | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]')
    LIVE_DIR="$MOUNT_POINT/live/$DISTRO_NAME"
    
    echo "Extracting Live ISO components..."
    mkdir -p "$LIVE_DIR"
    7z x "$ISO_PATH" -o"$LIVE_DIR" -x'![BOOT]' >/dev/null
    
    # Find kernel and initrd
    VMLINUZ=$(find "$LIVE_DIR" -type f -name 'vmlinuz*' -print -quit)
    INITRD=$(find "$LIVE_DIR" -type f -name 'initrd*' -print -quit)
    
    if [ -z "$VMLINUZ" ] || [ -z "$INITRD" ]; then
        echo "Error: Couldn't find kernel/initrd in ISO!"
        return 1
    fi
    
    # Add to Live menu
    cat >> "$GRUB_DIR/live-menu.cfg" <<CFG
menuentry "$DISTRO_NAME - Live" {
    linux /live/$DISTRO_NAME/$(basename "$VMLINUZ") boot=live components quiet
    initrd /live/$DISTRO_NAME/$(basename "$INITRD")
}

menuentry "$DISTRO_NAME - Live (RAM)" {
    linux /live/$DISTRO_NAME/$(basename "$VMLINUZ") boot=live components quiet toram
    initrd /live/$DISTRO_NAME/$(basename "$INITRD")
}

menuentry "$DISTRO_NAME - Persistent" {
    linux /live/$DISTRO_NAME/$(basename "$VMLINUZ") boot=live components quiet persistent
    initrd /live/$DISTRO_NAME/$(basename "$INITRD")
}
CFG
    echo "Added $DISTRO_NAME Live system to boot menu"
}

# Function to add bootloader
add_bootloader() {
    echo "Available bootloaders:"
    echo "1) rEFInd"
    echo "2) Clover"
    echo "3) Ventoy"
    echo "4) netboot.xyz"
    read -p "Select bootloader: " choice
    
    case $choice in
        1) BL_NAME="rEFInd" ;;
        2) BL_NAME="Clover" ;;
        3) BL_NAME="Ventoy" ;;
        4) BL_NAME="netboot.xyz" ;;
        *) echo "Invalid choice"; return 1 ;;
    esac
    
    echo "Adding $BL_NAME..."
    mkdir -p "$MOUNT_POINT/boot/efi/$BL_NAME"
    
    case $choice in
        1)
            wget -qO- https://sourceforge.net/projects/refind/files/latest/download | \
            tar xz -C "$MOUNT_POINT/boot/efi/$BL_NAME" --strip-components=1
            ;;
        2)
            wget -qO- https://sourceforge.net/projects/cloverefiboot/files/latest/download | \
            tar xz -C "$MOUNT_POINT/boot/efi/$BL_NAME" --strip-components=1
            ;;
        3)
            wget -q https://github.com/ventoy/Ventoy/releases/latest/download/ventoy-1.0.00-linux.tar.gz
            tar xzf ventoy-1.0.00-linux.tar.gz -C "$MOUNT_POINT/boot/efi/$BL_NAME"
            ;;
        4)
            wget -q https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn -O \
            "$MOUNT_POINT/boot/efi/$BL_NAME/netboot.xyz.lkrn"
            ;;
    esac
    
    # Add to EFI menu
    cat >> "$GRUB_DIR/efi-menu.cfg" <<CFG
menuentry "$BL_NAME" {
    chainloader /boot/efi/$BL_NAME/${BL_NAME,,}.efi || \
    chainloader /boot/efi/$BL_NAME/bootx64.efi || \
    linux16 /boot/efi/$BL_NAME/netboot.xyz.lkrn
}
CFG
    echo "Added $BL_NAME to boot menu"
}

# Main menu
while true; do
    clear
    echo "GRUB agFM Bootable Files Helper"
    echo "-------------------------------"
    echo "1) Add Standard ISO"
    echo "2) Add Linux Live ISO (Deconstructed)"
    echo "3) Add Bootloader"
    echo "4) Exit"
    
    read -p "Select option: " opt
    case $opt in
        1) add_iso ;;
        2) add_live_iso ;;
        3) add_bootloader ;;
        4) exit 0 ;;
        *) echo "Invalid option"; sleep 1 ;;
    esac
done
EOF

chmod +x "$MOUNT_POINT/add-bootables.sh"

# Create empty menu files for the helper script
touch "$MOUNT_POINT/boot/grub/"{iso-menu.cfg,live-menu.cfg,efi-menu.cfg}

# Clean up
echo "Cleaning up..."
umount "$MOUNT_POINT"
rm -rf "$MOUNT_POINT"
rm -rf grub2-filemanager Multibooters-agFM-rEFInd-GRUBFM

# Detach loop device if we used one
if [ -n "$LOOP_DEV" ]; then
    losetup -d "$LOOP_DEV"
fi

echo ""
echo "Success! Target $USB_PARTITION is now ready with:"
echo "1. Direct agFM boot for both BIOS and UEFI (no intermediate menus)"
echo "2. Organized directory structure for boot files"
echo "3. add-bootables.sh helper script for future management"
echo "4. Support for x86_64, i386, and AA64 UEFI systems"
if [[ "$TARGET" == *.img ]]; then
    echo ""
    echo "You can test the image with:"
    echo "qemu-system-x86_64 -hda $TARGET -m 2G"
fi
