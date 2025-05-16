#!/bin/bash

# WinPE ISO Creation Script (Fixed)
# Creates BIOS+UEFI bootable WinPE ISO

install_dependencies() {
    echo "Installing required packages..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y xorriso wimtools
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y xorriso wimlib-utils
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y xorriso wimlib-utils
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm xorriso wimlib
    else
        echo "ERROR: Could not detect package manager to install dependencies."
        exit 1
    fi
}

prepare_bootfiles() {
    local iso_dir="$1"
    
    echo "Preparing WinPE boot files..."
    mkdir -p "$iso_dir"/{sources,boot,efi/boot}
    
    if [ ! -f "$iso_dir/sources/boot.wim" ]; then
        echo "Error: boot.wim not found in $iso_dir/sources/"
        exit 1
    fi
    
    # Download UEFI bootloader if missing
    if [ ! -f "$iso_dir/efi/boot/bootx64.efi" ]; then
        echo "Downloading UEFI bootloader..."
        if wget -q "https://github.com/pbatard/rufus/raw/master/res/uefi/uefi-ntfs.img" -O /tmp/uefi-ntfs.img; then
            7z e -y -o"$iso_dir/efi/boot/" /tmp/uefi-ntfs.img "efi/boot/bootx64.efi" >/dev/null 2>&1 || {
                echo "Warning: Could not extract UEFI bootloader"
            }
            rm /tmp/uefi-ntfs.img
        else
            echo "Warning: Could not download UEFI bootloader"
        fi
    fi
    
    # Check for BIOS boot files
    if [ ! -f "$iso_dir/bootmgr" ]; then
        echo "Warning: bootmgr not found. BIOS boot may not work."
    fi
}

create_winpe_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"
    
    echo "Creating WinPE ISO image..."
    
    xorriso -as mkisofs \
        -iso-level 4 \
        -volid "$iso_label" \
        -b boot/etfsboot.com \
        -no-emul-boot \
        -boot-load-size 8 \
        -eltorito-alt-boot \
        -e efi/boot/bootx64.efi \
        -no-emul-boot \
        -o "$output_file" \
        "$source_dir"
    
    if [ -f "$output_file" ]; then
        echo "ISO created successfully at: $output_file"
    else
        echo "Error: Failed to create ISO"
        exit 1
    fi
}

main() {
    echo "=== WinPE ISO Creation Script ==="
    
    if ! command -v xorriso &>/dev/null; then
        install_dependencies
    fi
    
    read -p "Enter the directory path containing your WinPE files: " WINPE_DIR
    WINPE_DIR=$(realpath "$WINPE_DIR")
    
    if [ ! -d "$WINPE_DIR" ]; then
        echo "Error: Directory $WINPE_DIR does not exist."
        exit 1
    fi
    
    prepare_bootfiles "$WINPE_DIR"
    
    read -p "Enter the output ISO filename (e.g., WinPE.iso): " iso_name
    output_dir=$(dirname "$WINPE_DIR")
    output_file="$output_dir/$iso_name"
    
    read -p "Enter ISO volume label (max 32 chars): " iso_label
    iso_label=$(echo "$iso_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-')
    iso_label=${iso_label:0:32}
    [ -z "$iso_label" ] && iso_label="WINPE"
    
    echo -e "\n=== Summary ==="
    echo "Source Directory: $WINPE_DIR"
    echo "Output ISO: $output_file"
    echo "Volume Label: $iso_label"
    echo -e "\nRequired files:"
    echo "- $WINPE_DIR/sources/boot.wim [✔]"
    
    read -p "Proceed with WinPE ISO creation? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && create_winpe_iso "$WINPE_DIR" "$output_file" "$iso_label"
}

main
