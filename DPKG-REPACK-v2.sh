#!/bin/bash

# Enhanced .deb creator with proper cleanup and error handling
# Fixes the issue where dpkg-repack creates folders instead of .deb files

# Configuration
TIMESTAMP=$(date +"%Y%m%d_%H%M%S")
OUTPUT_DIR="/home/DPKG-REPACK/"
FAILED_LOG="$OUTPUT_DIR/failed_packages.log"
SUCCESS_LOG="$OUTPUT_DIR/success_packages.log"
CLEANUP_LOG="$OUTPUT_DIR/cleanup.log"

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_status() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

show_usage() {
    echo "Usage: $0 [OPTIONS]"
    echo "Create .deb files of installed packages (Enhanced version)"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: /tmp/deb_files_TIMESTAMP)"
    echo "  -m            Only process manually installed packages"
    echo "  -l LIMIT      Limit number of packages to process (default: all)"
    echo "  -c            Clean up any existing dpkg-repack temp directories"
    echo "  -v            Verbose output"
    echo "  -h            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                    # Create .deb files for all packages"
    echo "  $0 -m                 # Only manually installed packages"
    echo "  $0 -l 10 -v           # Process only first 10 packages with verbose output"
    echo "  $0 -c                 # Clean up temp directories first"
}

cleanup_temp_dirs() {
    print_status "Cleaning up temporary dpkg-repack directories..."
    
    # Find and remove dpkg-repack temp directories
    local temp_dirs=$(find /tmp -maxdepth 1 -name "dpkg-repack.*" -type d 2>/dev/null)
    local home_temp_dirs=$(find "$HOME" -maxdepth 1 -name "dpkg-repack.*" -type d 2>/dev/null)
    local output_temp_dirs=$(find "$OUTPUT_DIR" -maxdepth 1 -name "dpkg-repack.*" -type d 2>/dev/null)
    
    local cleaned=0
    
    for dir in $temp_dirs $home_temp_dirs $output_temp_dirs; do
        if [ -d "$dir" ]; then
            print_warning "Removing temp directory: $dir"
            rm -rf "$dir" && ((cleaned++))
            echo "Removed: $dir" >> "$CLEANUP_LOG"
        fi
    done
    
    if [ $cleaned -gt 0 ]; then
        print_success "Cleaned up $cleaned temporary directories"
    else
        print_status "No temporary directories found to clean"
    fi
}

check_dependencies() {
    print_status "Checking dependencies..."
    
    if ! command -v dpkg-repack >/dev/null 2>&1; then
        print_error "dpkg-repack is not installed"
        print_status "Installing dpkg-repack..."
        
        if command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y dpkg-repack
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get update && sudo apt-get install -y dpkg-repack
        else
            print_error "Cannot find package manager to install dpkg-repack"
            exit 1
        fi
        
        if [ $? -ne 0 ]; then
            print_error "Failed to install dpkg-repack"
            exit 1
        fi
    fi
    
    # Check if fakeroot is available (helps with dpkg-repack)
    if ! command -v fakeroot >/dev/null 2>&1; then
        print_warning "fakeroot not found, installing for better dpkg-repack compatibility..."
        if command -v apt >/dev/null 2>&1; then
            sudo apt install -y fakeroot
        elif command -v apt-get >/dev/null 2>&1; then
            sudo apt-get install -y fakeroot
        fi
    fi
    
    print_success "All dependencies satisfied"
}

get_package_list() {
    local temp_file="/tmp/package_list_$$"
    
    if [ "$MANUAL_ONLY" = true ]; then
        print_status "Getting manually installed packages..."
        if command -v apt-mark >/dev/null 2>&1; then
            apt-mark showmanual 2>/dev/null | sort > "$temp_file"
        else
            dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | sort > "$temp_file"
        fi
    else
        print_status "Getting all installed packages..."
        dpkg-query -f '${binary:Package}\n' -W 2>/dev/null | sort > "$temp_file"
    fi
    
    if [ -n "$PACKAGE_LIMIT" ]; then
        head -n "$PACKAGE_LIMIT" "$temp_file"
    else
        cat "$temp_file"
    fi
    
    rm -f "$temp_file"
}

create_deb_file_enhanced() {
    local package="$1"
    local current="$2"
    local total="$3"
    
    # Progress indicator
    printf "\r${BLUE}[PROGRESS]${NC} Processing $current/$total: %-30s" "$package"
    
    # Check if package is actually installed
    if ! dpkg-query -W "$package" >/dev/null 2>&1; then
        [ "$VERBOSE" = true ] && echo -e "\n${RED}[ERROR]${NC} Package $package not found"
        echo "$package: not installed" >> "$FAILED_LOG"
        return 1
    fi
    
    # Skip problematic packages that are known to cause issues
    case "$package" in
        *-dbg|*-dev|*-doc|linux-image-*|linux-headers-*)
            [ "$VERBOSE" = true ] && echo -e "\n${YELLOW}[SKIP]${NC} Skipping potentially problematic package: $package"
            echo "$package: skipped (problematic)" >> "$FAILED_LOG"
            return 1
            ;;
    esac
    
    local old_pwd=$(pwd)
    cd "$OUTPUT_DIR"
    
    # Clean up any existing temp dirs for this package before starting
    rm -rf dpkg-repack.*"$package"* 2>/dev/null
    
    # Try dpkg-repack with enhanced error handling and cleanup
    local success=false
    local temp_dir=""
    
    # Use fakeroot if available for better compatibility
    local repack_cmd="dpkg-repack"
    if command -v fakeroot >/dev/null 2>&1; then
        repack_cmd="fakeroot dpkg-repack"
    fi
    
    # Run dpkg-repack with timeout and capture any temp directory created
    if timeout 120 $repack_cmd "$package" >/dev/null 2>&1; then
        # Check if .deb file was actually created
        if ls "${package}"_*.deb >/dev/null 2>&1; then
            [ "$VERBOSE" = true ] && echo -e "\n${GREEN}[SUCCESS]${NC} Created .deb for $package"
            echo "$package" >> "$SUCCESS_LOG"
            success=true
        else
            [ "$VERBOSE" = true ] && echo -e "\n${RED}[ERROR]${NC} dpkg-repack completed but no .deb file found for $package"
            echo "$package: no .deb file created" >> "$FAILED_LOG"
        fi
    else
        [ "$VERBOSE" = true ] && echo -e "\n${RED}[ERROR]${NC} dpkg-repack failed or timed out for $package"
        echo "$package: dpkg-repack failed/timeout" >> "$FAILED_LOG"
    fi
    
    # Clean up any leftover temp directories
    temp_dir=$(find . -maxdepth 1 -name "dpkg-repack.*" -type d 2>/dev/null | head -1)
    if [ -n "$temp_dir" ] && [ -d "$temp_dir" ]; then
        [ "$VERBOSE" = true ] && echo -e "\n${YELLOW}[CLEANUP]${NC} Removing temp dir: $temp_dir"
        rm -rf "$temp_dir"
        echo "Cleaned temp dir for $package: $temp_dir" >> "$CLEANUP_LOG"
    fi
    
    cd "$old_pwd"
    
    if [ "$success" = true ]; then
        return 0
    else
        return 1
    fi
}

process_packages() {
    local packages_file="/tmp/packages_to_process_$$"
    get_package_list > "$packages_file"
    
    local total=$(wc -l < "$packages_file")
    local current=0
    local success=0
    local failed=0
    
    if [ "$total" -eq 0 ]; then
        print_error "No packages found"
        rm -f "$packages_file"
        exit 1
    fi
    
    print_status "Processing $total packages..."
    
    while IFS= read -r package; do
        [ -z "$package" ] && continue
        
        ((current++))
        
        if create_deb_file_enhanced "$package" "$current" "$total"; then
            ((success++))
        else
            ((failed++))
        fi
        
        # Periodic cleanup every 10 packages
        if [ $((current % 10)) -eq 0 ]; then
            cleanup_temp_dirs >/dev/null 2>&1
        fi
        
        # Safety check - if too many failures, stop
        if [ "$failed" -gt 20 ] && [ "$failed" -gt $((success * 3)) ]; then
            echo ""
            print_warning "Too many failures ($failed), stopping to prevent issues..."
            break
        fi
        
    done < "$packages_file"
    
    echo ""
    print_status "Completed: $success successful, $failed failed"
    
    rm -f "$packages_file"
}

show_summary() {
    print_status "=== SUMMARY ==="
    
    # Final cleanup
    cleanup_temp_dirs >/dev/null 2>&1
    
    # Count .deb files created
    local deb_count=$(find "$OUTPUT_DIR" -name "*.deb" -type f 2>/dev/null | wc -l)
    local total_size=""
    
    if [ "$deb_count" -gt 0 ]; then
        total_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
        print_success "Created $deb_count .deb files"
        print_status "Output directory: $OUTPUT_DIR"
        print_status "Total size: $total_size"
        
        # List first few .deb files as examples
        print_status "Sample .deb files created:"
        find "$OUTPUT_DIR" -name "*.deb" -type f | head -3 | while read deb_file; do
            echo "  - $(basename "$deb_file")"
        done
        
        # Copy to user directory if not running as root
        if [ "$EUID" -ne 0 ]; then
            local user_dir="$HOME/deb_files_$TIMESTAMP"
            print_status "Copying files to $user_dir..."
            if cp -r "$OUTPUT_DIR" "$user_dir" 2>/dev/null; then
                print_success "Files copied to $user_dir"
            else
                print_warning "Could not copy to user directory"
            fi
        fi
    else
        print_error "No .deb files were created"
        print_status "Check the failed packages log: $FAILED_LOG"
    fi
    
    # Show failed packages summary
    if [ -f "$FAILED_LOG" ] && [ -s "$FAILED_LOG" ]; then
        local failed_count=$(wc -l < "$FAILED_LOG")
        print_warning "$failed_count packages failed"
        
        if [ "$VERBOSE" = true ] && [ "$failed_count" -le 5 ]; then
            print_status "Failed packages:"
            head -5 "$FAILED_LOG" | while read line; do
                echo "  - $line"
            done
        fi
    fi
    
    # Show cleanup summary
    if [ -f "$CLEANUP_LOG" ] && [ -s "$CLEANUP_LOG" ]; then
        local cleanup_count=$(wc -l < "$CLEANUP_LOG")
        print_status "Cleaned up $cleanup_count temporary directories"
    fi
    
    print_status "To install on another system: sudo dpkg -i *.deb"
    print_status "To handle dependencies: sudo apt-get install -f"
}

# Default values
MANUAL_ONLY=false
VERBOSE=false
PACKAGE_LIMIT=""
CLEANUP_FIRST=false

# Parse command line arguments
while [[ $# -gt 0 ]]; do
    case $1 in
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        -m|--manual)
            MANUAL_ONLY=true
            shift
            ;;
        -l|--limit)
            PACKAGE_LIMIT="$2"
            shift 2
            ;;
        -c|--cleanup)
            CLEANUP_FIRST=true
            shift
            ;;
        -v|--verbose)
            VERBOSE=true
            shift
            ;;
        -h|--help)
            show_usage
            exit 0
            ;;
        *)
            print_error "Unknown option: $1"
            show_usage
            exit 1
            ;;
    esac
done

main() {
    print_status "Starting enhanced .deb file creation..."
    print_status "Output directory: $OUTPUT_DIR"
    print_status "Manual packages only: $MANUAL_ONLY"
    [ -n "$PACKAGE_LIMIT" ] && print_status "Package limit: $PACKAGE_LIMIT"
    
    # Check if running as root
    if [ "$EUID" -eq 0 ]; then
        print_warning "Running as root - be careful with file permissions"
    fi
    
    # Clean up first if requested
    if [ "$CLEANUP_FIRST" = true ]; then
        cleanup_temp_dirs
    fi
    
    # Check dependencies
    check_dependencies
    
    # Create output directory
    if ! mkdir -p "$OUTPUT_DIR"; then
        print_error "Failed to create output directory: $OUTPUT_DIR"
        exit 1
    fi
    
    # Initialize log files
    : > "$FAILED_LOG"
    : > "$SUCCESS_LOG"
    : > "$CLEANUP_LOG"
    
    # Process packages
    process_packages
    
    # Show summary
    show_summary
}

# Trap to cleanup on exit
trap 'cleanup_temp_dirs >/dev/null 2>&1; rm -f /tmp/package_list_$$ /tmp/packages_to_process_$$' EXIT

# Run main function
main "$@"