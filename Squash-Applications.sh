#!/bin/bash

# Create SquashFS from application files with proper filesystem structure
# Author: Claude Assistant
# Description: Packages application files into a SquashFS that can be mounted to root

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
    local deps=("mksquashfs" "which" "find")
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" >/dev/null 2>&1; then
            print_error "$dep is required but not installed."
            if [[ "$dep" == "mksquashfs" ]]; then
                echo "Please install squashfs-tools: sudo apt install squashfs-tools"
            fi
            exit 1
        fi
    done
}

# Function to safely copy file maintaining directory structure
safe_copy() {
    local src_file="$1"
    local dest_root="$2"
    
    # Remove leading slash to get relative path
    local rel_path="${src_file#/}"
    local dest_file="$dest_root/$rel_path"
    local dest_dir
    dest_dir=$(dirname "$dest_file")
    
    # Create directory structure
    mkdir -p "$dest_dir"
    
    # Copy file if it exists and is readable
    if [[ -r "$src_file" ]]; then
        if cp "$src_file" "$dest_file" 2>/dev/null; then
            return 0
        fi
    fi
    return 1
}

# Function to find and copy application files
find_app_files() {
    local app_name="$1"
    local squashfs_root="$2"
    local found_files=0
    
    print_status "🔍 Searching for files related to: $app_name"
    
    # Find executable in PATH and get its location
    local exec_path=""
    if command -v "$app_name" >/dev/null 2>&1; then
        exec_path=$(which "$app_name")
        print_status "Found executable: $exec_path"
        
        # Copy executable
        if safe_copy "$exec_path" "$squashfs_root"; then
            ((found_files++))
            print_status "✓ Copied executable: $exec_path"
        fi
        
        # Find and copy library dependencies
        if [[ -x "$exec_path" ]] && command -v ldd >/dev/null 2>&1; then
            print_status "🔗 Finding library dependencies..."
            local lib_count=0
            local lib_file
            
            # Process library dependencies one by one
            ldd "$exec_path" 2>/dev/null | grep -E "=> /" | awk '{print $3}' | while IFS= read -r lib_file; do
                if [[ -f "$lib_file" ]] && safe_copy "$lib_file" "$squashfs_root"; then
                    echo "Library copied: $lib_file" >&2
                fi
            done
            
            print_status "✓ Processed library dependencies"
        fi
    fi
    
    # Search for application files in common system directories
    local search_patterns=(
        "/usr/bin/*$app_name*"
        "/usr/local/bin/*$app_name*"
        "/usr/sbin/*$app_name*"
        "/usr/local/sbin/*$app_name*"
        "/usr/share/$app_name"
        "/usr/share/*$app_name*"
        "/usr/local/share/$app_name"
        "/usr/local/share/*$app_name*"
        "/usr/lib/$app_name"
        "/usr/lib/*$app_name*"
        "/usr/local/lib/$app_name"
        "/usr/local/lib/*$app_name*"
        "/usr/lib64/$app_name"
        "/usr/lib64/*$app_name*"
        "/opt/$app_name"
        "/opt/*$app_name*"
    )
    
    print_status "🗂️  Searching system directories..."
    local pattern
    local file
    for pattern in "${search_patterns[@]}"; do
        for file in $pattern; do
            if [[ -e "$file" ]] 2>/dev/null; then
                if [[ -d "$file" ]]; then
                    # Copy entire directory structure
                    print_status "📁 Found directory: $file"
                    local subfile
                    find "$file" -type f 2>/dev/null | while IFS= read -r subfile; do
                        safe_copy "$subfile" "$squashfs_root" && echo "File copied: $subfile" >&2
                    done
                    ((found_files++))
                elif [[ -f "$file" ]]; then
                    # Copy individual file
                    if safe_copy "$file" "$squashfs_root"; then
                        ((found_files++))
                        print_status "📄 Found file: $file"
                    fi
                fi
            fi
        done 2>/dev/null
    done
    
    # Search for configuration files in /etc
    print_status "⚙️  Searching for configuration files..."
    local config_patterns=(
        "/etc/$app_name"
        "/etc/$app_name.conf"
        "/etc/$app_name.cfg"
        "/etc/$app_name/*"
        "/etc/default/$app_name"
        "/etc/sysconfig/$app_name"
        "/etc/conf.d/$app_name"
    )
    
    local config_item
    for pattern in "${config_patterns[@]}"; do
        for config_item in $pattern; do
            if [[ -e "$config_item" ]] 2>/dev/null; then
                if [[ -d "$config_item" ]]; then
                    print_status "📁 Found config directory: $config_item"
                    local config_file
                    find "$config_item" -type f 2>/dev/null | while IFS= read -r config_file; do
                        safe_copy "$config_file" "$squashfs_root" && echo "Config copied: $config_file" >&2
                    done
                    ((found_files++))
                elif [[ -f "$config_item" ]]; then
                    if safe_copy "$config_item" "$squashfs_root"; then
                        ((found_files++))
                        print_status "⚙️  Found config: $config_item"
                    fi
                fi
            fi
        done 2>/dev/null
    done
    
    # Search for systemd service files
    print_status "🔧 Searching for service files..."
    local service_patterns=(
        "/lib/systemd/system/$app_name.service"
        "/lib/systemd/system/*$app_name*.service"
        "/usr/lib/systemd/system/$app_name.service"
        "/usr/lib/systemd/system/*$app_name*.service"
        "/etc/systemd/system/$app_name.service"
        "/etc/systemd/system/*$app_name*.service"
    )
    
    local service_file
    for pattern in "${service_patterns[@]}"; do
        for service_file in $pattern; do
            if [[ -f "$service_file" ]] 2>/dev/null; then
                if safe_copy "$service_file" "$squashfs_root"; then
                    ((found_files++))
                    print_status "🔧 Found service: $service_file"
                fi
            fi
        done 2>/dev/null
    done
    
    # Search for variable data in /var
    print_status "💾 Searching for application data..."
    local var_patterns=(
        "/var/lib/$app_name"
        "/var/cache/$app_name"
        "/var/log/$app_name"
        "/var/spool/$app_name"
    )
    
    for pattern in "${var_patterns[@]}"; do
        if [[ -d "$pattern" ]]; then
            print_status "💾 Found data directory: $pattern"
            local data_file
            find "$pattern" -type f 2>/dev/null | while IFS= read -r data_file; do
                safe_copy "$data_file" "$squashfs_root" && echo "Data copied: $data_file" >&2
            done
            ((found_files++))
        fi
    done
    
    # Try to find files using dpkg if available
    if command -v dpkg-query >/dev/null 2>&1; then
        if dpkg-query -W "$app_name" >/dev/null 2>&1; then
            print_status "📦 Found package: $app_name, extracting files..."
            local pkg_file
            
            dpkg-query -L "$app_name" 2>/dev/null | grep -v "^/\.$" | sort | while IFS= read -r pkg_file; do
                if [[ -f "$pkg_file" ]]; then
                    safe_copy "$pkg_file" "$squashfs_root" && echo "Package file copied: $pkg_file" >&2
                fi
            done
            ((found_files++))
        fi
    fi
    
    # Count actual files copied
    local actual_files
    actual_files=$(find "$squashfs_root" -type f 2>/dev/null | wc -l)
    
    if [[ $actual_files -eq 0 ]]; then
        print_warning "No files found for application: $app_name"
        return 1
    else
        print_success "✅ Collected $actual_files files for $app_name"
        return 0
    fi
}

# Main script execution
main() {
    print_status "🚀 SquashFS Application Packager (Root-mountable)"
    echo "   Creates SquashFS with proper filesystem structure for root mounting"
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
    
    # Create temporary directory with filesystem structure
    local temp_base="/tmp/squashfs_builder_$$"
    local squashfs_root="$temp_base/rootfs"
    mkdir -p "$squashfs_root"
    
    # Track successful apps
    local successful_apps=()
    
    # Process each application (files will merge naturally in same filesystem structure)
    local app
    for app in "${apps[@]}"; do
        echo
        print_status "🔄 Processing application: $app"
        if find_app_files "$app" "$squashfs_root"; then
            successful_apps+=("$app")
        fi
    done
    
    if [[ ${#successful_apps[@]} -eq 0 ]]; then
        print_error "No files found for any of the specified applications!"
        rm -rf "$temp_base"
        exit 1
    fi
    
    echo
    print_success "Successfully processed: ${successful_apps[*]}"
    
    # Show filesystem structure
    print_status "📂 Filesystem structure created:"
    find "$squashfs_root" -type d 2>/dev/null | head -20 | sed "s|$squashfs_root|.|g"
    local dir_count
    dir_count=$(find "$squashfs_root" -type d 2>/dev/null | wc -l)
    if [[ $dir_count -gt 20 ]]; then
        echo "   ... and $((dir_count - 20)) more directories"
    fi
    
    # Determine output filename
    local output_name
    if [[ ${#successful_apps[@]} -eq 1 ]]; then
        output_name="${successful_apps[0]}.squashfs"
        print_status "Using default name: $output_name"
    else
        echo
        echo "Multiple applications packaged: ${successful_apps[*]}"
        echo -n "Enter name for SquashFS file (without .squashfs extension): "
        read -r custom_name
        
        if [[ -z "$custom_name" ]]; then
            local joined_names
            IFS=-
            joined_names="${successful_apps[*]}"
            IFS=' '
            output_name="$joined_names.squashfs"
        else
            output_name="${custom_name}.squashfs"
        fi
    fi
    
    # Create SquashFS archive
    local output_path="$HOME/$output_name"
    
    echo
    print_status "📦 Creating SquashFS archive: $output_path"
    print_status "Using XZ compression for optimal size..."
    
    if mksquashfs "$squashfs_root" "$output_path" -comp xz -Xbcj x86 -b 1048576 -info -progress; then
        echo
        print_success "🎉 SquashFS created successfully!"
        echo
        echo "📁 Output file: $output_path"
        local file_size
        file_size=$(du -h "$output_path" | cut -f1)
        echo "📊 File size: $file_size"
        local file_count
        file_count=$(find "$squashfs_root" -type f 2>/dev/null | wc -l)
        echo "📈 File count: $file_count files"
        local dir_count_final
        dir_count_final=$(find "$squashfs_root" -type d 2>/dev/null | wc -l)
        echo "🗂️  Directory count: $dir_count_final directories"
        echo
        echo "🔧 To mount at boot (add to /etc/fstab):"
        echo "   $output_path / squashfs loop,ro 0 0"
        echo
        echo "🔧 Manual mount commands:"
        echo "   sudo mount -o loop,ro \"$output_path\" /mnt"
        echo "   # Or overlay mount:"
        echo "   sudo mount -t overlay overlay -o lowerdir=/mnt:/,upperdir=/tmp/upper,workdir=/tmp/work /"
        echo
        echo "⚠️  Warning: Mounting to root (/) will overlay your filesystem!"
        echo "   Test first by mounting to /mnt to verify contents."
    else
        print_error "Failed to create SquashFS archive!"
        rm -rf "$temp_base"
        exit 1
    fi
    
    # Cleanup
    print_status "🧹 Cleaning up temporary files..."
    rm -rf "$temp_base"
    
    print_success "✨ Process completed successfully!"
    echo
    echo "💡 Tip: You can now configure this SquashFS to mount at boot"
    echo "   and your applications will be immediately available!"
}

# Trap to cleanup on exit
trap 'rm -rf "/tmp/squashfs_builder_$$"' EXIT

# Run main function
main "$@"
