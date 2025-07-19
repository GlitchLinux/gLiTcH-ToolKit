#!/bin/bash

# Simple script to create .deb files of all installed packages
# Uses dpkg-repack to create .deb files from currently installed packages

# Configuration
OUTPUT_DIR="deb_files_$(date +%Y%m%d_%H%M%S)"
FAILED_LOG="failed_packages.log"
SUCCESS_LOG="success_packages.log"

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
    echo "Create .deb files of all installed packages"
    echo ""
    echo "Options:"
    echo "  -o DIR        Output directory (default: deb_files_TIMESTAMP)"
    echo "  -m            Only process manually installed packages"
    echo "  -p NUM        Number of parallel processes (default: 4)"
    echo "  -v            Verbose output"
    echo "  -h            Show this help"
    echo ""
    echo "Examples:"
    echo "  $0                    # Create .deb files for all packages"
    echo "  $0 -m                 # Only manually installed packages"
    echo "  $0 -o my_debs -p 8    # Custom output dir, 8 parallel processes"
}

check_dependencies() {
    if ! command -v dpkg-repack >/dev/null 2>&1; then
        print_error "dpkg-repack is not installed"
        print_status "Installing dpkg-repack..."
        sudo apt update && sudo apt install -y dpkg-repack
        if [ $? -ne 0 ]; then
            print_error "Failed to install dpkg-repack"
            exit 1
        fi
    fi
    
    if [ "$USE_PARALLEL" = true ] && ! command -v parallel >/dev/null 2>&1; then
        print_warning "GNU parallel not found, falling back to sequential processing"
        USE_PARALLEL=false
    fi
}

get_package_list() {
    if [ "$MANUAL_ONLY" = true ]; then
        print_status "Getting manually installed packages..."
        apt-mark showmanual | sort
    else
        print_status "Getting all installed packages..."
        dpkg-query -f '${binary:Package}\n' -W | sort
    fi
}

create_deb_file() {
    local package="$1"
    local output_dir="$2"
    local verbose="$3"
    
    # Check if package is actually installed
    if ! dpkg-query -W "$package" >/dev/null 2>&1; then
        [ "$verbose" = true ] && print_error "Package $package not found"
        echo "$package: not installed" >> "$FAILED_LOG"
        return 1
    fi
    
    # Create .deb file
    cd "$output_dir"
    if dpkg-repack "$package" >/dev/null 2>&1; then
        [ "$verbose" = true ] && print_success "Created .deb for $package"
        echo "$package" >> "$SUCCESS_LOG"
        return 0
    else
        [ "$verbose" = true ] && print_error "Failed to create .deb for $package"
        echo "$package: dpkg-repack failed" >> "$FAILED_LOG"
        return 1
    fi
}

process_packages_sequential() {
    local packages=("$@")
    local total=${#packages[@]}
    local current=0
    local success=0
    local failed=0
    
    print_status "Processing $total packages sequentially..."
    
    for package in "${packages[@]}"; do
        ((current++))
        
        # Progress indicator
        printf "\r${BLUE}[PROGRESS]${NC} Processing $current/$total: %-30s" "$package"
        
        if create_deb_file "$package" "$OUTPUT_DIR" "$VERBOSE"; then
            ((success++))
        else
            ((failed++))
        fi
    done
    
    echo ""
    print_status "Completed: $success successful, $failed failed"
}

process_packages_parallel() {
    local packages=("$@")
    local total=${#packages[@]}
    
    print_status "Processing $total packages with $PARALLEL_JOBS parallel processes..."
    
    # Export function and variables for parallel
    export -f create_deb_file print_success print_error
    export OUTPUT_DIR VERBOSE FAILED_LOG SUCCESS_LOG
    export RED GREEN YELLOW BLUE NC
    
    # Process packages in parallel
    printf '%s\n' "${packages[@]}" | \
        parallel -j "$PARALLEL_JOBS" create_deb_file {} "$OUTPUT_DIR" "$VERBOSE"
    
    # Count results
    local success=$(wc -l < "$SUCCESS_LOG" 2>/dev/null || echo "0")
    local failed=$(wc -l < "$FAILED_LOG" 2>/dev/null || echo "0")
    
    print_status "Completed: $success successful, $failed failed"
}

cleanup_and_summary() {
    cd "$ORIGINAL_DIR"
    
    print_status "=== SUMMARY ==="
    
    # Count .deb files created
    local deb_count=$(ls -1 "$OUTPUT_DIR"/*.deb 2>/dev/null | wc -l)
    local total_size=$(du -sh "$OUTPUT_DIR" 2>/dev/null | cut -f1)
    
    print_success "Created $deb_count .deb files"
    print_status "Output directory: $OUTPUT_DIR"
    print_status "Total size: $total_size"
    
    # Show failed packages if any
    if [ -f "$OUTPUT_DIR/$FAILED_LOG" ] && [ -s "$OUTPUT_DIR/$FAILED_LOG" ]; then
        local failed_count=$(wc -l < "$OUTPUT_DIR/$FAILED_LOG")
        print_warning "$failed_count packages failed:"
        head -10 "$OUTPUT_DIR/$FAILED_LOG" | while read line; do
            echo "  - $line"
        done
        if [ "$failed_count" -gt 10 ]; then
            echo "  ... and $((failed_count - 10)) more (see $OUTPUT_DIR/$FAILED_LOG)"
        fi
    fi
    
    print_status "All .deb files are in: $OUTPUT_DIR"
    print_status "To install on another system: sudo dpkg -i *.deb"
}

# Default values
MANUAL_ONLY=false
PARALLEL_JOBS=4
USE_PARALLEL=true
VERBOSE=false
ORIGINAL_DIR=$(pwd)

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
        -p|--parallel)
            PARALLEL_JOBS="$2"
            if [ "$PARALLEL_JOBS" -eq 1 ]; then
                USE_PARALLEL=false
            fi
            shift 2
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
    print_status "Starting .deb file creation..."
    print_status "Output directory: $OUTPUT_DIR"
    print_status "Manual packages only: $MANUAL_ONLY"
    print_status "Parallel processing: $USE_PARALLEL"
    if [ "$USE_PARALLEL" = true ]; then
        print_status "Parallel jobs: $PARALLEL_JOBS"
    fi
    
    # Check dependencies
    check_dependencies
    
    # Create output directory
    mkdir -p "$OUTPUT_DIR"
    cd "$OUTPUT_DIR"
    
    # Initialize log files
    > "$FAILED_LOG"
    > "$SUCCESS_LOG"
    
    # Get package list
    mapfile -t packages < <(get_package_list)
    local package_count=${#packages[@]}
    
    if [ $package_count -eq 0 ]; then
        print_error "No packages found"
        exit 1
    fi
    
    print_status "Found $package_count packages to process"
    
    # Process packages
    if [ "$USE_PARALLEL" = true ]; then
        process_packages_parallel "${packages[@]}"
    else
        process_packages_sequential "${packages[@]}"
    fi
    
    # Show summary
    cleanup_and_summary
}

# Check if running as root (warn but don't exit)
if [ "$EUID" -eq 0 ]; then
    print_warning "Running as root - this is not necessary for creating .deb files"
fi

# Run main function
main "$@"
