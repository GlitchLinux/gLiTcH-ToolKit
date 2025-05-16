#!/bin/bash

# WinPE ISO Creation Script
# Creates BIOS+UEFI bootable WinPE ISO from directory structure

# Install required dependencies
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

# Prepare WinPE boot files
prepare_bootfiles() {
    local iso_dir="$1"
    
    echo "Preparing WinPE boot files..."
    
    # Create required directories
    mkdir -p "$iso_dir"/{sources,boot,efi/boot}
    
    # Check for required WinPE files
    if [ ! -f "$iso_dir/sources/boot.wim" ]; then
        echo "Error: boot.wim not found in $iso_dir/sources/"
        echo "Please place your WinPE boot.wim file in the sources directory"
        exit 1
    fi
    
    # Download or create required boot files if missing
    if [ ! -f "$iso_dir/boot/bcd" ]; then
        echo "Creating basic BCD store..."
        bcdedit /createstore "$iso_dir/boot/bcd" >/dev/null 2>&1 || {
            echo "Warning: Could not create BCD store. You may need to provide one."
        }
    fi
    
    if [ ! -f "$iso_dir/boot/boot.sdi" ]; then
        echo "Downloading boot.sdi..."
        wget -q "https://raw.githubusercontent.com/pebakery/pebakery/master/boot/boot.sdi" -O "$iso_dir/boot/boot.sdi" || {
            echo "Warning: Could not download boot.sdi. You may need to provide one."
        }
    fi
    
    # Create UEFI boot files if missing
    if [ ! -f "$iso_dir/efi/boot/bootx64.efi" ]; then
        echo "Downloading UEFI bootloader..."
        wget -q "https://github.com/pbatard/rufus/raw/master/res/uefi/uefi-ntfs.img" -O /tmp/uefi-ntfs.img
        if [ -f /tmp/uefi-ntfs.img ]; then
            7z e -y -o"$iso_dir/efi/boot/" /tmp/uefi-ntfs.img "efi/boot/bootx64.efi" >/dev/null 2>&1 || {
                echo "Warning: Could not extract UEFI bootloader"
            }
            rm /tmp/uefi-ntfs.img
        else
            echo "Warning: Could not download UEFI bootloader"
        fi
    fi
    
    # Create BIOS boot files if missing
    if [ ! -f "$iso_dir/bootmgr" ]; then
        echo "Warning: bootmgr not found. BIOS boot may not work without it."
    fi
}

# Create the WinPE ISO
create_winpe_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"
    
    echo "Creating WinPE ISO image..."
    
    xorriso -as mkisofs \
        -iso-level 4 \
        -udf \
        -volid "$iso_label" \
        -b boot/etfsboot.com \
        -no-emul-boot \
        -boot-load-size 8 \
        -eltorito-alt-boot \
        -eltorito-platform efi \
        -b efi/boot/bootx64.efi \
        -no-emul-boot \
        -o "$output_file" \
        "$source_dir"
    
    echo "ISO created successfully at: $output_file"
}

# Main script
main() {
    echo "=== WinPE ISO Creation Script ==="
    
    # Check and install dependencies
    if ! command -v xorriso &>/dev/null || ! command -v wiminfo &>/dev/null; then
        install_dependencies
    fi
    
    # Get source directory
    read -p "Enter the directory path containing your WinPE files: " WINPE_DIR
    WINPE_DIR=$(realpath "$WINPE_DIR")
    
    # Verify the directory exists
    if [ ! -d "$WINPE_DIR" ]; then
        echo "Error: Directory $WINPE_DIR does not exist."
        exit 1
    fi
    
    # Check for required files
    if [ ! -f "$WINPE_DIR/sources/boot.wim" ]; then
        echo "Error: boot.wim not found in $WINPE_DIR/sources/"
        echo "This is required for WinPE. Please provide a boot.wim file."
        exit 1
    fi
    
    # Prepare boot files
    prepare_bootfiles "$WINPE_DIR"
    
    # Get output filename
    read -p "Enter the output ISO filename (e.g., WinPE.iso): " iso_name
    
    # Set output directory to parent of WINPE_DIR
    output_dir=$(dirname "$WINPE_DIR")
    output_file="$output_dir/$iso_name"
    
    # Get volume label
    read -p "Enter ISO volume label (max 32 chars, no spaces/special chars): " iso_label
    iso_label=$(echo "$iso_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-')
    iso_label=${iso_label:0:32}
    if [ -z "$iso_label" ]; then
        iso_label="WINPE"
    fi
    
    # Confirm and create ISO
    echo -e "\n=== Summary ==="
    echo "Source Directory: $WINPE_DIR"
    echo "Output ISO: $output_file"
    echo "Volume Label: $iso_label"
    echo -e "\nRequired files:"
    echo "- $WINPE_DIR/sources/boot.wim [✔]"
    
    read -p "Proceed with WinPE ISO creation? (y/n): " confirm
    if [[ "$confirm" =~ ^[Yy]$ ]]; then
        create_winpe_iso "$WINPE_DIR" "$output_file" "$iso_label"
    else
        echo "ISO creation cancelled."
        exit 0
    fi
}

# Run main function
main
