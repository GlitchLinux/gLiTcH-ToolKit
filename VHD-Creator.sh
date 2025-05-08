#!/bin/bash

# VHD Creator Tool
# A simple CLI utility to create VHD files on Debian/Ubuntu systems

# Check if qemu-img is installed
check_dependencies() {
    if ! command -v qemu-img &> /dev/null; then
        echo "Error: qemu-img is not installed. Please install qemu-utils first."
        echo "Run: sudo apt install qemu-utils"
        exit 1
    fi
}

# Prompt for file path
get_file_path() {
    while true; do
        read -p "Enter directory path to save VHD (default: current directory): " vhd_path
        vhd_path=${vhd_path:-.}  # Default to current directory
        
        # Check if path exists
        if [ ! -d "$vhd_path" ]; then
            echo "Error: Directory does not exist. Please try again."
        else
            break
        fi
    done
}

# Prompt for filename
get_filename() {
    while true; do
        read -p "Enter VHD filename (without extension): " vhd_name
        
        # Check if filename is empty
        if [ -z "$vhd_name" ]; then
            echo "Error: Filename cannot be empty. Please try again."
        else
            vhd_file="${vhd_path}/${vhd_name}.vhd"
            
            # Check if file already exists
            if [ -f "$vhd_file" ]; then
                read -p "File already exists. Overwrite? (y/n): " overwrite
                if [[ "$overwrite" =~ ^[Yy]$ ]]; then
                    break
                fi
            else
                break
            fi
        fi
    done
}

# Prompt for size
get_size() {
    while true; do
        read -p "Enter VHD size (e.g., 10G for 10GB, 500M for 500MB): " vhd_size
        
        # Validate size format
        if [[ "$vhd_size" =~ ^[0-9]+[MG]$ ]]; then
            break
        else
            echo "Error: Invalid size format. Use format like 10G or 500M"
        fi
    done
}

# Prompt for disk type
get_disk_type() {
    while true; do
        read -p "Create dynamic (1) or fixed (2) VHD? [1/2]: " disk_type
        
        case $disk_type in
            1) vhd_type="dynamic"; break ;;
            2) vhd_type="fixed"; break ;;
            *) echo "Invalid choice. Please enter 1 or 2" ;;
        esac
    done
}

# Main function
main() {
    echo "=== VHD Creator Tool ==="
    check_dependencies
    
    get_file_path
    get_filename
    get_size
    get_disk_type
    
    echo -e "\nCreating VHD file with these settings:"
    echo "Path: $vhd_file"
    echo "Size: $vhd_size"
    echo "Type: $vhd_type"
    
    # Create the VHD
    if [ "$vhd_type" == "dynamic" ]; then
        qemu-img create -f vpc "$vhd_file" "$vhd_size"
    else
        qemu-img create -f vpc -o subformat=fixed "$vhd_file" "$vhd_size"
    fi
    
    # Verify creation
    if [ $? -eq 0 ]; then
        echo -e "\nSuccessfully created VHD file: $vhd_file"
        qemu-img info "$vhd_file"
    else
        echo "Error: Failed to create VHD file"
        exit 1
    fi
}

# Run the main function
main
