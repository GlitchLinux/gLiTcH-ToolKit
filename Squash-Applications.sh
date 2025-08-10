#!/bin/bash

# Create SquashFS from application files
# Author: Claude Assistant
# Description: Packages application files into a SquashFS archive

set -e  # Exit on any error

# Color codes for better output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Function to print colored output
print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if required tools are installed
check_dependencies() {
    local deps=("mksquashfs" "dpkg" "which")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            print_error "$dep is required but not installed."
            echo "Please install squashfs-tools: sudo apt install squashfs-tools"
            exit 1
        fi
    done
}

# Function to find application files
find_app_files() {
    local app_name="$1"
    local temp_dir="$2"
    local found_files=0
    
    print_status "Searching for files related to: $app_name"
    
    # Create app-specific directory
    local app_dir="$temp_dir/$app_name"
    mkdir -p "$app_dir"/{bin,lib,share,etc,var}
    
    # Find executable in PATH
    if command -v "$app_name" &> /dev/null; then
        local exec_path=$(which "$app_name")
        print_status "Found executable: $exec_path"
        
        # Copy executable
        cp "$exec_path" "$app_dir/bin/" 2>/dev/null || print_warning "Could not copy $exec_path"
        ((found_files++))
        
        # Find library dependencies using ldd
        if [[ -x "$exec_path" ]]; then
            print_status "Finding library dependencies..."
            ldd "$exec_path" 2>/dev/null | grep -E "=> /" | awk '{print $3}' | while read lib; do
                if [[ -f "$lib" ]]; then
                    local lib_dir=$(dirname "$lib" | sed 's|^/||')
                    mkdir -p "$app_dir/$lib_dir"
                    cp "$lib" "$app_dir/$lib_dir/" 2>/dev/null || true
                fi
            done
        fi
    fi
    
    # Search common directories for app-related files
    local search_paths=(
        "/usr/bin"
        "/usr/local/bin"
        "/usr/share"
        "/usr/local/share"
        "/etc"
        "/opt"
        "/var/lib"
    )
    
    for search_path in "${search_paths[@]}"; do
        if [[ -d "$search_path" ]]; then
            find "$search_path" -name "*$app_name*" -type f 2>/dev/null | while read file; do
                local rel_path=$(echo "$file" | sed 's|^/||')
                local target_dir="$app_dir/$(dirname "$rel_path")"
                mkdir -p "$target_dir"
                cp "$file" "$target_dir/" 2>/dev/null || true
                ((found_files++))
            done
        fi
    done
    
    # Search for configuration files in /etc
    find /etc -name "*$app_name*" -type f 2>/dev/null | while read config_file; do
        local rel_path=$(echo "$config_file" | sed 's|^/||')
        local target_dir="$app_dir/$(dirname "$rel_path")"
        mkdir -p "$target_dir"
        cp "$config_file" "$target_dir/" 2>/dev/null || true
    done
    
    # If dpkg is available, try to find package files
    if command -v dpkg-query &> /dev/null; then
        if dpkg-query -W "$app_name" &> /dev/null; then
            print_status "Found package: $app_name, extracting package files..."
            dpkg-query -L "$app_name" 2>/dev/null | while read pkg_file; do
                if [[ -f "$pkg_file" ]]; then
                    local rel_path=$(echo "$pkg_file" | sed 's|^/||')
                    local target_dir="$app_dir/$(dirname "$rel_path")"
                    mkdir -p "$target_dir"
                    cp "$pkg_file" "$target_dir/" 2>/dev/null || true
                fi
            done
        fi
    fi
    
    # Check if any files were found
    if [[ $(find "$app_dir" -type f | wc -l) -eq 0 ]]; then
        print_warning "No files found for application: $app_name"
        rm -rf "$app_dir"
        return 1
    else
        local file_count=$(find "$app_dir" -type f | wc -l)
        print_success "Found $file_count files for $app_name"
        return 0
    fi
}

# Main script execution
main() {
    print_status "SquashFS Application Packager 📦"
    echo
    
    # Check dependencies
    check_dependencies
    
    # Prompt for application names
    echo -n "Enter application name(s) (space-separated for multiple): "
    read -r app_input
    
    if [[ -z "$app_input" ]]; then
        print_error "No application names provided!"
        exit 1
    fi
    
    # Convert input to array
    read -ra apps <<< "$app_input"
    
    print_status "Processing ${#apps[@]} application(s): ${apps[*]}"
    
    # Create temporary directory
    local temp_base="/tmp/squashfs_builder_$$"
    mkdir -p "$temp_base"
    
    # Track successful apps
    local successful_apps=()
    
    # Process each application
    for app in "${apps[@]}"; do
        if find_app_files "$app" "$temp_base"; then
            successful_apps+=("$app")
        fi
    done
    
    if [[ ${#successful_apps[@]} -eq 0 ]]; then
        print_error "No files found for any of the specified applications!"
        rm -rf "$temp_base"
        exit 1
    fi
    
    # Determine output filename
    local output_name
    if [[ ${#successful_apps[@]} -eq 1 ]]; then
        output_name="${successful_apps[0]}.squashfs"
        print_status "Using default name: $output_name"
    else
        echo
        echo "Multiple applications found: ${successful_apps[*]}"
        echo -n "Enter name for SquashFS file (without .squashfs extension): "
        read -r custom_name
        
        if [[ -z "$custom_name" ]]; then
            output_name="$(IFS=-; echo "${successful_apps[*]}").squashfs"
        else
            output_name="${custom_name}.squashfs"
        fi
    fi
    
    # Create SquashFS archive
    local output_path="$HOME/$output_name"
    
    print_status "Creating SquashFS archive: $output_path"
    print_status "This may take a while depending on the size..."
    
    if mksquashfs "$temp_base"/* "$output_path" -comp xz -Xbcj x86 -b 1048576 -info; then
        print_success "SquashFS created successfully! 🎉"
        echo
        echo "📁 Output file: $output_path"
        echo "📊 File size: $(du -h "$output_path" | cut -f1)"
        echo
        echo "To mount the SquashFS:"
        echo "  sudo mkdir -p /mnt/squashfs"
        echo "  sudo mount -o loop \"$output_path\" /mnt/squashfs"
        echo
        echo "To unmount:"
        echo "  sudo umount /mnt/squashfs"
    else
        print_error "Failed to create SquashFS archive!"
        rm -rf "$temp_base"
        exit 1
    fi
    
    # Cleanup
    print_status "Cleaning up temporary files..."
    rm -rf "$temp_base"
    
    print_success "Process completed successfully! ✨"
}

# Trap to cleanup on exit
trap 'rm -rf "/tmp/squashfs_builder_$$"' EXIT

# Run main function
main "$@"
