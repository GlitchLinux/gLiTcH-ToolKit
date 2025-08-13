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

# Find large files
find_large_files() {
    print_status "Finding large files (>100MB)..."
    print_status "Large files in home directory:"
    find "$HOME" -type f -size +100M -exec ls -lh {} \; 2>/dev/null | \
    awk '{print $5 " " $9}' | sort -hr | head -10
    
    if [ "$IS_ROOT" = true ]; then
        print_status "Large files system-wide:"
        find / -type f -size +100M -not -path "/proc/*" -not -path "/sys/*" \
        -not -path "/dev/*" -exec ls -lh {} \; 2>/dev/null | \
        awk '{print $5 " " $9}' | sort -hr | head -10
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

EXAMPLES:
    $0              # Interactive mode (default)
    $0 --quick      # Quick automated cleanup
    $0 --find       # Find large files
    sudo $0 --all   # Complete cleanup as root

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
