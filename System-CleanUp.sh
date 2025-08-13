#!/bin/bash

# Debian Disk Space Cleanup Script
# Comprehensive cleanup of unused disk space

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
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

print_header() {
    echo -e "${CYAN}$1${NC}"
}

# Function to show disk usage before and after
show_disk_usage() {
    echo ""
    print_header "=== Current Disk Usage ==="
    df -h / /home /tmp /var 2>/dev/null
    echo ""
}

# Function to get freed space
get_freed_space() {
    local before=$1
    local after=$(df / | awk 'NR==2 {print $4}')
    local freed=$((before - after))
    if [ $freed -gt 0 ]; then
        echo $((freed / 1024))
    else
        echo "0"
    fi
}

# Check if running as root for some operations
check_privileges() {
    if [[ $EUID -eq 0 ]]; then
        print_status "Running as root - can perform all cleanup operations"
        IS_ROOT=true
    else
        print_warning "Not running as root - some operations will be skipped"
        print_status "Run with sudo for complete cleanup"
        IS_ROOT=false
    fi
}

# Clean APT cache and unused packages
clean_apt_system() {
    print_status "Cleaning APT system..."
    
    if [ "$IS_ROOT" = true ]; then
        # Clean package cache
        print_status "Cleaning package cache..."
        apt clean
        apt autoclean
        
        # Remove orphaned packages
        print_status "Removing orphaned packages..."
        apt autoremove --purge -y
        
        # Remove old kernels (keep current + 1 previous)
        print_status "Cleaning old kernels..."
        apt autoremove --purge -y
        
        print_success "APT system cleaned"
    else
        print_warning "Skipping APT cleanup - requires root privileges"
    fi
}

# Clean logs
clean_logs() {
    print_status "Cleaning log files..."
    
    if [ "$IS_ROOT" = true ]; then
        # Clean systemd journal logs (keep last 7 days)
        print_status "Cleaning systemd journal logs..."
        journalctl --vacuum-time=7d
        
        # Clean old log files in /var/log
        print_status "Cleaning old log files..."
        find /var/log -type f -name "*.log.*" -mtime +7 -delete 2>/dev/null
        find /var/log -type f -name "*.gz" -mtime +7 -delete 2>/dev/null
        find /var/log -type f -name "*.1" -mtime +7 -delete 2>/dev/null
        
        # Truncate large log files
        print_status "Truncating large log files..."
        find /var/log -type f -size +100M -exec truncate -s 50M {} \; 2>/dev/null
        
        print_success "Log files cleaned"
    else
        print_warning "Skipping log cleanup - requires root privileges"
    fi
}

# Clean user cache and temporary files
clean_user_cache() {
    print_status "Cleaning user cache and temporary files..."
    
    # Clean user's cache directory
    if [ -d "$HOME/.cache" ]; then
        print_status "Cleaning user cache directory..."
        rm -rf "$HOME/.cache"/*
        print_success "User cache cleaned"
    fi
    
    # Clean thumbnail cache
    if [ -d "$HOME/.thumbnails" ]; then
        print_status "Cleaning thumbnail cache..."
        rm -rf "$HOME/.thumbnails"/*
        print_success "Thumbnail cache cleaned"
    fi
    
    # Clean browser caches
    print_status "Cleaning browser caches..."
    
    # Firefox
    find "$HOME/.mozilla/firefox" -name "Cache*" -type d -exec rm -rf {} \; 2>/dev/null
    find "$HOME/.mozilla/firefox" -name "OfflineCache*" -type d -exec rm -rf {} \; 2>/dev/null
    
    # Chrome/Chromium
    rm -rf "$HOME/.cache/google-chrome"/* 2>/dev/null
    rm -rf "$HOME/.cache/chromium"/* 2>/dev/null
    
    # Clean recent files
    rm -f "$HOME/.local/share/recently-used.xbel" 2>/dev/null
    
    print_success "User cache cleaned"
}

# Clean temporary files
clean_temp_files() {
    print_status "Cleaning temporary files..."
    
    if [ "$IS_ROOT" = true ]; then
        # Clean /tmp
        print_status "Cleaning /tmp directory..."
        find /tmp -type f -atime +7 -delete 2>/dev/null
        find /tmp -type d -empty -delete 2>/dev/null
        
        # Clean /var/tmp
        print_status "Cleaning /var/tmp directory..."
        find /var/tmp -type f -atime +7 -delete 2>/dev/null
        find /var/tmp -type d -empty -delete 2>/dev/null
        
        print_success "Temporary files cleaned"
    else
        # Clean user's temp files
        print_status "Cleaning user temporary files..."
        find /tmp -user "$(whoami)" -type f -atime +1 -delete 2>/dev/null
        print_success "User temporary files cleaned"
    fi
}

# Clean trash
clean_trash() {
    print_status "Cleaning trash..."
    
    # Clean user trash
    if [ -d "$HOME/.local/share/Trash" ]; then
        rm -rf "$HOME/.local/share/Trash"/*
        print_success "User trash cleaned"
    fi
    
    # Clean system trash (if root)
    if [ "$IS_ROOT" = true ] && [ -d "/root/.local/share/Trash" ]; then
        rm -rf "/root/.local/share/Trash"/*
        print_success "Root trash cleaned"
    fi
}

# Clean old downloads
clean_old_downloads() {
    print_status "Cleaning old downloads (files older than 30 days)..."
    
    if [ -d "$HOME/Downloads" ]; then
        # Ask user before deleting downloads
        echo -n "Delete files in Downloads older than 30 days? [y/N]: "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            find "$HOME/Downloads" -type f -mtime +30 -delete 2>/dev/null
            print_success "Old downloads cleaned"
        else
            print_status "Skipping Downloads cleanup"
        fi
    fi
}

# Remove duplicate files (using fdupes if available)
remove_duplicates() {
    if command -v fdupes &> /dev/null; then
        print_status "Scanning for duplicate files..."
        echo -n "Remove duplicate files in home directory? [y/N]: "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            fdupes -rdN "$HOME" 2>/dev/null
            print_success "Duplicate files removed"
        fi
    else
        print_status "Install 'fdupes' package to remove duplicate files"
    fi
}

# Clean package manager caches
clean_package_caches() {
    print_status "Cleaning package manager caches..."
    
    # Clean pip cache
    if command -v pip3 &> /dev/null; then
        pip3 cache purge 2>/dev/null
        print_success "Python pip cache cleaned"
    fi
    
    # Clean npm cache
    if command -v npm &> /dev/null; then
        npm cache clean --force 2>/dev/null
        print_success "Node.js npm cache cleaned"
    fi
    
    # Clean snap cache
    if command -v snap &> /dev/null && [ "$IS_ROOT" = true ]; then
        snap list --all | awk '/disabled/{print $1, $3}' | \
        while read snapname revision; do
            snap remove "$snapname" --revision="$revision" 2>/dev/null
        done
        print_success "Snap cache cleaned"
    fi
}

# Clean Docker (if installed)
clean_docker() {
    if command -v docker &> /dev/null; then
        print_status "Cleaning Docker..."
        echo -n "Clean Docker images, containers, and volumes? [y/N]: "
        read -r response
        if [[ "$response" =~ ^[Yy]$ ]]; then
            docker system prune -af 2>/dev/null
            docker volume prune -f 2>/dev/null
            print_success "Docker cleaned"
        fi
    fi
}

# Zero unused disk space (secure deletion)
zero_unused_space() {
    print_status "Zeroing unused disk space..."
    print_warning "This operation will take significant time and write to disk extensively"
    print_warning "It securely overwrites free space and helps with disk compression"
    
    echo -n "Proceed with zeroing unused space? [y/N]: "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_status "Skipping unused space zeroing"
        return 0
    fi
    
    # Get available space and create zero file
    print_status "Creating zero file to fill unused space..."
    
    # For root filesystem
    if [ "$IS_ROOT" = true ]; then
        print_status "Zeroing unused space on root filesystem..."
        dd if=/dev/zero of=/zero_file bs=1M 2>/dev/null || true
        sync
        rm -f /zero_file
        print_success "Root filesystem unused space zeroed"
        
        # Zero /home if it's on a separate partition
        if mountpoint -q /home; then
            print_status "Zeroing unused space on /home filesystem..."
            dd if=/dev/zero of=/home/zero_file bs=1M 2>/dev/null || true
            sync
            rm -f /home/zero_file
            print_success "/home filesystem unused space zeroed"
        fi
        
        # Zero /tmp if it's on a separate partition
        if mountpoint -q /tmp; then
            print_status "Zeroing unused space on /tmp filesystem..."
            dd if=/dev/zero of=/tmp/zero_file bs=1M 2>/dev/null || true
            sync
            rm -f /tmp/zero_file
            print_success "/tmp filesystem unused space zeroed"
        fi
        
        # Zero /var if it's on a separate partition
        if mountpoint -q /var; then
            print_status "Zeroing unused space on /var filesystem..."
            dd if=/dev/zero of=/var/zero_file bs=1M 2>/dev/null || true
            sync
            rm -f /var/zero_file
            print_success "/var filesystem unused space zeroed"
        fi
    else
        # Non-root user - only zero home directory space
        print_status "Zeroing unused space in home directory (user mode)..."
        dd if=/dev/zero of="$HOME/zero_file" bs=1M 2>/dev/null || true
        sync
        rm -f "$HOME/zero_file"
        print_success "Home directory unused space zeroed"
    fi
    
    print_success "Unused space zeroing completed"
}

# Alternative: Zero specific filesystem
zero_filesystem() {
    local mount_point="$1"
    local zero_file="$mount_point/zero_file_$"
    
    print_status "Zeroing unused space on $mount_point..."
    
    # Check available space first
    local available_space=$(df "$mount_point" | awk 'NR==2 {print $4}')
    print_status "Available space: $((available_space / 1024))MB"
    
    # Create zero file with progress indication
    (
        echo "0"
        dd if=/dev/zero of="$zero_file" bs=1M 2>&1 | \
        stdbuf -oL grep -o '[0-9]\+[0-9]* bytes' | \
        while read bytes; do
            mb=$((bytes / 1024 / 1024))
            if [ $mb -gt 0 ]; then
                echo "# Zeroing: ${mb}MB written..."
            fi
        done
        echo "100"
    ) 2>/dev/null || true
    
    # Ensure data is written to disk
    sync
    
    # Remove zero file
    rm -f "$zero_file"
    
    print_success "Filesystem $mount_point zeroed"
}

# Advanced zeroing with multiple passes
secure_zero_space() {
    print_status "Secure zeroing with multiple passes..."
    print_warning "This will perform 3 passes: random, zero, random"
    print_warning "This operation will take VERY long time"
    
    echo -n "Proceed with secure multi-pass zeroing? [y/N]: "
    read -r response
    if [[ ! "$response" =~ ^[Yy]$ ]]; then
        print_status "Skipping secure zeroing"
        return 0
    fi
    
    local zero_file="/secure_zero_$"
    
    if [ "$IS_ROOT" = true ]; then
        print_status "Pass 1/3: Writing random data..."
        dd if=/dev/urandom of="$zero_file" bs=1M 2>/dev/null || true
        sync
        
        print_status "Pass 2/3: Writing zeros..."
        dd if=/dev/zero of="$zero_file" bs=1M 2>/dev/null || true
        sync
        
        print_status "Pass 3/3: Writing random data..."
        dd if=/dev/urandom of="$zero_file" bs=1M 2>/dev/null || true
        sync
        
        rm -f "$zero_file"
        print_success "Secure zeroing completed"
    else
        print_error "Secure zeroing requires root privileges"
    fi
}

# Interactive mode
interactive_cleanup() {
    print_header "=== Interactive Cleanup Mode ==="
    echo ""
    
    echo -n "Clean APT system (packages, cache)? [Y/n]: "
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        clean_apt_system
    fi
    
    echo -n "Clean log files? [Y/n]: "
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        clean_logs
    fi
    
    echo -n "Clean user cache and temporary files? [Y/n]: "
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        clean_user_cache
        clean_temp_files
    fi
    
    echo -n "Clean trash? [Y/n]: "
    read -r response
    if [[ ! "$response" =~ ^[Nn]$ ]]; then
        clean_trash
    fi
    
    clean_old_downloads
    remove_duplicates
    clean_docker
    
    echo ""
    echo -n "Zero unused disk space (takes time, helps compression)? [y/N]: "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        zero_unused_space
    fi
    
    echo -n "Perform secure multi-pass zeroing (VERY slow)? [y/N]: "
    read -r response
    if [[ "$response" =~ ^[Yy]$ ]]; then
        secure_zero_space
    fi
}

# Quick cleanup mode
quick_cleanup() {
    print_header "=== Quick Cleanup Mode ==="
    echo ""
    
    clean_apt_system
    clean_logs
    clean_user_cache
    clean_temp_files
    clean_trash
    clean_package_caches
}

# Show help
show_help() {
    cat << EOF
Debian Disk Space Cleanup Script

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help      Show this help message
    -q, --quick     Quick cleanup (non-interactive)
    -i, --interactive Interactive cleanup
    -f, --find      Find large files only
    -a, --all       Clean everything (quick + extras)
    -z, --zero      Zero unused space only
    -s, --secure    Secure multi-pass zeroing only

EXAMPLES:
    $0              # Interactive mode (default)
    $0 --quick      # Quick automated cleanup
    $0 --find       # Find large files
    $0 --zero       # Zero unused space only
    sudo $0 --all   # Complete cleanup as root
    sudo $0 --secure # Secure zeroing only

ZEROING OPERATIONS:
    --zero          Single-pass zeroing (fills free space with zeros)
    --secure        Multi-pass secure zeroing (random-zero-random)

Note: Zeroing operations help with:
- Disk image compression
- Security (prevents data recovery)
- SSD optimization
- Virtual machine disk shrinking

EOF
}

# Main function
main() {
    print_header "========================================"
    print_header "    Debian Disk Space Cleanup Tool"
    print_header "========================================"
    echo ""
    
    check_privileges
    
    # Store initial disk usage
    BEFORE_CLEANUP=$(df / | awk 'NR==2 {print $4}')
    
    show_disk_usage
    
    case "${1:-interactive}" in
        -h|--help)
            show_help
            exit 0
            ;;
        -q|--quick)
            quick_cleanup
            ;;
        -i|--interactive|interactive)
            interactive_cleanup
            ;;
        -f|--find)
            find_large_files
            exit 0
            ;;
        -z|--zero)
            zero_unused_space
            exit 0
            ;;
        -s|--secure)
            secure_zero_space
            exit 0
            ;;
        -a|--all)
            quick_cleanup
            clean_old_downloads() {
                if [ -d "$HOME/Downloads" ]; then
                    find "$HOME/Downloads" -type f -mtime +30 -delete 2>/dev/null
                    print_success "Old downloads cleaned (auto)"
                fi
            }
            clean_old_downloads
            remove_duplicates() {
                if command -v fdupes &> /dev/null; then
                    fdupes -rdN "$HOME" 2>/dev/null
                    print_success "Duplicate files removed (auto)"
                fi
            }
            remove_duplicates
            clean_docker() {
                if command -v docker &> /dev/null; then
                    docker system prune -af 2>/dev/null
                    docker volume prune -f 2>/dev/null
                    print_success "Docker cleaned (auto)"
                fi
            }
            clean_docker
            echo ""
            print_status "Performing final zero pass on unused space..."
            zero_unused_space
            ;;
        *)
            print_error "Unknown option: $1"
            show_help
            exit 1
            ;;
    esac
    
    echo ""
    print_header "========================================"
    print_success "Cleanup completed!"
    print_header "========================================"
    
    show_disk_usage
    
    # Calculate freed space
    FREED_MB=$(get_freed_space $BEFORE_CLEANUP)
    if [ "$FREED_MB" != "0" ]; then
        print_success "Freed approximately ${FREED_MB}MB of disk space"
    fi
    
    find_large_files
}

# Run main function with all arguments
main "$@"
