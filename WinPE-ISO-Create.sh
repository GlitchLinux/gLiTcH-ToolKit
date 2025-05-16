#!/bin/bash

# WinPE ISO Creation Script (Fixed for your structure)
# Creates UEFI bootable WinPE ISO

install_dependencies() {
    echo "Installing required packages..."
    if [ -x "$(command -v apt-get)" ]; then
        sudo apt-get install -y xorriso wimtools p7zip-full
    elif [ -x "$(command -v dnf)" ]; then
        sudo dnf install -y xorriso wimlib-utils p7zip
    elif [ -x "$(command -v yum)" ]; then
        sudo yum install -y xorriso wimlib-utils p7zip
    elif [ -x "$(command -v pacman)" ]; then
        sudo pacman -S --noconfirm xorriso wimlib p7zip
    else
        echo "ERROR: Could not detect package manager to install dependencies."
        exit 1
    fi
}

prepare_bootfiles() {
    local iso_dir="$1"
    
    echo "Preparing WinPE boot files..."
    mkdir -p "$iso_dir"/{sources,EFI/Boot}
    
    # Verify boot.wim exists
    if [ ! -f "$iso_dir/sources/boot.wim" ]; then
        echo "Error: boot.wim not found in $iso_dir/sources/"
        exit 1
    fi

    # Verify UEFI bootloader exists
    if [ ! -f "$iso_dir/EFI/Boot/bootx64.efi" ]; then
        echo "Error: bootx64.efi not found in $iso_dir/EFI/Boot/"
        echo "Please ensure you have UEFI boot files in EFI/Boot/"
        exit 1
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
        -eltorito-boot EFI/Boot/bootx64.efi \
        -no-emul-boot \
        -boot-load-size 8 \
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
    echo "- $WINPE_DIR/EFI/Boot/bootx64.efi [✔]"
    
    read -p "Proceed with WinPE ISO creation? (y/n): " confirm
    [[ "$confirm" =~ ^[Yy]$ ]] && create_winpe_iso "$WINPE_DIR" "$output_file" "$iso_label"
}

main
