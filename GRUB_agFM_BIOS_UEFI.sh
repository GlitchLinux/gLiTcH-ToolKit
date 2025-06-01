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

# Function to install dependencies
install_dependencies() {
    echo "Installing required dependencies..."
    apt-get update
    apt-get install -y xorriso isolinux wget syslinux-utils mtools p7zip-full squashfs-tools
}

# Function to generate boot configurations
generate_boot_configs() {
    local ISO_DIR="$1"
    local NAME="$2"
    local VMLINUZ="$3"
    local INITRD="$4"
    local SQUASHFS="$5"
    
    # Create boot/grub directory if it doesn't exist
    mkdir -p "$ISO_DIR/boot/grub"

    # Generate grub.cfg
    cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF
set timeout=5
set default=0
set menu_color_normal=cyan/blue
set menu_color_highlight=white/blue

menuentry "$NAME - LIVE" {
    linux /live/$VMLINUZ boot=live config quiet
    initrd /live/$INITRD
}

menuentry "$NAME - Boot ISO to RAM" {
    linux /live/$VMLINUZ boot=live config quiet toram
    initrd /live/$INITRD
}

menuentry "$NAME - Encrypted Persistence" {
    linux /live/$VMLINUZ boot=live components quiet splash noeject findiso=\${iso_path} persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/$INITRD
}

menuentry "GRUB File Manager" {
    configfile /boot/grub/grub.cfg
}
EOF

    echo "GRUB configuration created: $ISO_DIR/boot/grub/grub.cfg"
}

# Function to add standard ISO
add_standard_iso() {
    read -p "Enter path to ISO file: " ISO_PATH
    if [ ! -f "$ISO_PATH" ]; then
        echo "Error: ISO file not found!"
        return 1
    fi
    
    read -p "Enter destination directory on USB (default: /isos): " DEST_DIR
    DEST_DIR=${DEST_DIR:-/isos}
    
    mkdir -p "${MOUNT_POINT}${DEST_DIR}"
    cp "$ISO_PATH" "${MOUNT_POINT}${DEST_DIR}/"
    echo "ISO file copied to ${DEST_DIR}/$(basename "$ISO_PATH")"
}

# Function to add Linux Live ISO
add_linux_live_iso() {
    read -p "Enter path to Linux Live ISO: " ISO_PATH
    if [ ! -f "$ISO_PATH" ]; then
        echo "Error: ISO file not found!"
        return 1
    fi
    
    TEMP_DIR=$(mktemp -d)
    echo "Extracting ISO to $TEMP_DIR..."
    7z x "$ISO_PATH" -o"$TEMP_DIR" > /dev/null
    
    # Detect live system files
    VMLINUZ=$(find "$TEMP_DIR" -name "vmlinuz*" | head -1)
    INITRD=$(find "$TEMP_DIR" -name "initrd*" | head -1)
    SQUASHFS=$(find "$TEMP_DIR" -name "*.squashfs" | head -1)
    
    if [ -z "$VMLINUZ" ] || [ -z "$INITRD" ] || [ -z "$SQUASHFS" ]; then
        echo "Error: Could not find required live system files!"
        rm -rf "$TEMP_DIR"
        return 1
    fi
    
    # Get distro name
    DISTRO_NAME=$(basename "$ISO_PATH" | cut -d'-' -f1 | tr '[:upper:]' '[:lower:]')
    DEST_DIR="/live/$DISTRO_NAME"
    
    mkdir -p "${MOUNT_POINT}${DEST_DIR}"
    cp "$VMLINUZ" "$INITRD" "$SQUASHFS" "${MOUNT_POINT}${DEST_DIR}/"
    
    # Generate boot configs
    generate_boot_configs "${MOUNT_POINT}" "$DISTRO_NAME" \
        "$(basename "$VMLINUZ")" "$(basename "$INITRD")" "$(basename "$SQUASHFS")"
    
    rm -rf "$TEMP_DIR"
    echo "Linux Live system added to ${DEST_DIR}/"
}

# Function to add bootloaders
add_bootloaders() {
    echo "Available bootloaders:"
    echo "1. rEFInd"
    echo "2. Clover"
    echo "3. Ventoy"
    echo "4. netboot.xyz"
    
    read -p "Select bootloader to add (1-4): " CHOICE
    
    case $CHOICE in
        1)
            echo "Adding rEFInd..."
            mkdir -p "${MOUNT_POINT}/EFI/refind"
            wget https://sourceforge.net/projects/refind/files/latest/download -O refind.zip
            unzip refind.zip -d "${MOUNT_POINT}/EFI/refind"
            ;;
        2)
            echo "Adding Clover..."
            mkdir -p "${MOUNT_POINT}/EFI/clover"
            wget https://sourceforge.net/projects/cloverefiboot/files/latest/download -O clover.zip
            unzip clover.zip -d "${MOUNT_POINT}/EFI/clover"
            ;;
        3)
            echo "Adding Ventoy..."
            wget https://github.com/ventoy/Ventoy/releases/latest/download/ventoy-1.0.00-linux.tar.gz -O ventoy.tar.gz
            tar xzf ventoy.tar.gz -C "${MOUNT_POINT}/"
            ;;
        4)
            echo "Adding netboot.xyz..."
            mkdir -p "${MOUNT_POINT}/boot/netboot.xyz"
            wget https://boot.netboot.xyz/ipxe/netboot.xyz.lkrn -O "${MOUNT_POINT}/boot/netboot.xyz/netboot.xyz.lkrn"
            ;;
        *)
            echo "Invalid selection"
            return 1
            ;;
    esac
    
    echo "Bootloader added successfully!"
}

# Main installation function
main_installation() {
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

    # Install GRUB for BIOS (to partition)
    echo "Installing GRUB for BIOS..."
    grub-install --target=i386-pc --boot-directory="$MOUNT_POINT/boot" --force "$USB_DEVICE"

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
    mkdir -p "$MOUNT_POINT/boot/grub"
    cp -r grub2-filemanager/build/* "$MOUNT_POINT/boot/grub/"
    cp grub2-filemanager/grubfm.iso "$MOUNT_POINT/boot/grub/"

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

    # Create main GRUB configuration that directly boots agFM
    echo "Creating GRUB configuration..."
    cat > "$MOUNT_POINT/boot/grub/grub.cfg" <<EOF
set default=0
set timeout=5
set menu_color_normal=cyan/blue
set menu_color_highlight=white/blue

if [ -f /boot/grub/loadfm ]; then
    linux /boot/grub/loadfm
    initrd /boot/grub/grubfm.iso
    boot
else
    menuentry "GRUB File Manager not found!" {
        echo "GRUB File Manager files are missing"
        sleep 5
    }
fi
EOF

    # Create UEFI configuration that directly boots agFM
    echo "Creating UEFI configuration..."
    mkdir -p "$MOUNT_POINT/efi/boot"
    cat > "$MOUNT_POINT/efi/boot/grub.cfg" <<EOF
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

    # Clean up temporary files
    echo "Cleaning up temporary files..."
    rm -rf grub2-filemanager Multibooters-agFM-rEFInd-GRUBFM

    echo ""
    echo "Success! Target $USB_PARTITION is now ready with:"
    echo "1. Direct agFM boot for both BIOS and UEFI"
    echo "2. All required GRUB File Manager components"
    echo "3. Support for x86_64, i386, and AA64 UEFI systems"
    if [[ "$TARGET" == *.img ]]; then
        echo ""
        echo "You can test the image with:"
        echo "qemu-system-x86_64 -hda $TARGET"
    fi

    # Offer to add bootable files
    echo ""
    read -p "Would you like to add bootable files to the drive now? (y/N): " add_files
    if [ "${add_files,,}" = "y" ]; then
        while true; do
            echo ""
            echo "Add bootable media, select type:"
            echo "1. Standard intact ISO (any type)"
            echo "2. Linux Live ISO with customized boot modes"
            echo "3. Bootloaders (rEFInd, Clover, Ventoy, netboot.xyz)"
            echo "4. Exit"
            
            read -p "Enter your choice (1-4): " choice
            
            case $choice in
                1)
                    add_standard_iso
                    ;;
                2)
                    add_linux_live_iso
                    ;;
                3)
                    add_bootloaders
                    ;;
                4)
                    break
                    ;;
                *)
                    echo "Invalid choice, please try again."
                    ;;
            esac
        done
    fi

    # Final clean up
    echo "Unmounting and cleaning up..."
    umount "$MOUNT_POINT"
    rm -rf "$MOUNT_POINT"
    
    # Detach loop device if we used one
    if [ -n "$LOOP_DEV" ]; then
        losetup -d "$LOOP_DEV"
    fi

    echo "All operations completed successfully!"
}

# Run main installation
main_installation
