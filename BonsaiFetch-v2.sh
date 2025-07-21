#!/bin/bash

# Bonsai Linux Cyberpunk Fetch Tool Installer - Advanced Boot Detection
# Creates modern cyberpunk-style fetch tool with robust boot detection
# MOTD disabled by default - use 'bonsaifetch' command
# Author: GlitchLinux

set -e  # Exit on any error

# Colors for script output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration variables
MOTD_DIR="/etc/update-motd.d"
BACKUP_DIR="/etc/motd-backup-$(date +%Y%m%d-%H%M%S)"

# Function to print colored output
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║    Bonsai Linux Cyberpunk Fetch Tool Installer v2.0     ║"
    echo "║                    by GlitchLinux                        ║"
    echo "║      Advanced Boot Detection + Fixed UI Formatting      ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_step() { echo -e "${MAGENTA}[STEP]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        echo "Usage: sudo $0"
        exit 1
    fi
}

# Install update-motd package
install_update_motd() {
    print_step "Installing update-motd package..."
    
    local original_dir=$(pwd)
    cd /tmp
    
    print_info "Downloading update-motd package..."
    if wget -q http://archive.ubuntu.com/ubuntu/pool/main/u/update-motd/update-motd_3.10_all.deb; then
        print_status "Downloaded update-motd package"
        
        print_info "Installing update-motd package..."
        dpkg --force-all -i update-motd_3.10_all.deb || {
            print_warning "First installation had dependency issues, fixing..."
        }
        
        print_info "Fixing dependencies..."
        apt-get update -qq && apt-get install -f -y
        
        print_info "Final installation attempt..."
        dpkg --force-all -i update-motd_3.10_all.deb
        
        rm -f update-motd_3.10_all.deb
        print_status "update-motd installation completed"
    else
        print_warning "Failed to download, trying apt-get..."
        apt-get update -qq
        apt-get install -y update-motd || {
            print_warning "Could not install update-motd"
        }
    fi
    
    cd "$original_dir"
}

# Clean existing MOTD scripts
clean_existing_motd() {
    print_step "Cleaning existing MOTD scripts..."
    
    # Create backup directory
    mkdir -p "$BACKUP_DIR"
    
    # Backup existing MOTD directory
    if [[ -d "$MOTD_DIR" ]]; then
        cp -r "$MOTD_DIR" "$BACKUP_DIR/"
        print_status "Backed up existing MOTD to $BACKUP_DIR"
        
        # Remove all existing scripts
        rm -f "$MOTD_DIR"/*
        print_status "Removed all existing MOTD scripts"
    fi
    
    # Ensure MOTD directory exists
    mkdir -p "$MOTD_DIR"
}

# Create the standalone bonsaifetch command with advanced boot detection
create_bonsaifetch() {
    print_step "Creating standalone bonsaifetch command with advanced boot detection..."
    
    cat > "/usr/local/bin/bonsaifetch" << 'EOF'
#!/bin/bash
# Bonsai Linux Fetch Tool - Advanced Boot Detection with Fixed UI
# Works independently of MOTD configuration

# Shared color setup function - handles tput errors gracefully
setup_colors() {
    if [[ -z "$TERM" ]]; then
        export TERM="linux"
    fi
    
    if [[ -t 1 ]] && [[ -n "$TERM" ]] && command -v tput >/dev/null 2>&1; then
        if c1=$(tput setaf 1 2>/dev/null); then
            c1=$(tput setaf 1)   # Red
            c2=$(tput setaf 2)   # Green  
            c3=$(tput setaf 3)   # Yellow
            c4=$(tput setaf 4)   # Blue
            c5=$(tput setaf 5)   # Magenta
            c6=$(tput setaf 6)   # Cyan
            c7=$(tput setaf 7)   # White
            bold=$(tput bold 2>/dev/null) || bold='\033[1m'
            reset=$(tput sgr0 2>/dev/null) || reset='\033[0m'
        else
            setup_ansi_colors
        fi
    else
        setup_ansi_colors
    fi
}

setup_ansi_colors() {
    c1='\033[0;31m'   # Red
    c2='\033[0;32m'   # Green
    c3='\033[0;33m'   # Yellow
    c4='\033[0;34m'   # Blue
    c5='\033[0;35m'   # Magenta
    c6='\033[0;36m'   # Cyan
    c7='\033[0;37m'   # White
    bold='\033[1m'
    reset='\033[0m'
}

# Initialize colors
setup_colors

# Advanced boot detection function with multiple failsafe methods
detect_boot_type() {
    local live_score=0
    local install_score=0
    local detection_methods=()
    
    # Method 1: Kernel command line analysis (most reliable)
    if grep -qE "boot=live|boot=casper|rd.live.image|live:" /proc/cmdline 2>/dev/null; then
        ((live_score += 4))
        detection_methods+=("cmdline")
        
        # Specific live system type detection
        if grep -q "toram" /proc/cmdline 2>/dev/null; then
            echo "${c6} ¤ RAM BOOT    ${bold}${c2}"
            return
        elif grep -q "persistent" /proc/cmdline 2>/dev/null; then
            echo "${c6} ¤ PERSISTENT  ${bold}${c2}"
            return
        fi
    fi
    
    # Method 2: Live system directory structure
    local live_dirs=("/run/live" "/lib/live/mount" "/rofs" "/casper" "/run/live/medium")
    for dir in "${live_dirs[@]}"; do
        if [[ -d "$dir" ]]; then
            ((live_score += 2))
            detection_methods+=("live-dirs")
            break
        fi
    done
    
    # Method 3: SquashFS detection (primary live indicator)
    if mount | grep -q squashfs 2>/dev/null; then
        ((live_score += 3))
        detection_methods+=("squashfs")
    fi
    
    # Method 4: Root filesystem type analysis
    local root_fs_type
    root_fs_type=$(findmnt -n -o FSTYPE / 2>/dev/null || echo "unknown")
    if [[ "$root_fs_type" =~ ^(overlay|overlayfs|aufs|tmpfs)$ ]]; then
        ((live_score += 3))
        detection_methods+=("union-fs")
    elif [[ "$root_fs_type" =~ ^(ext[234]|xfs|btrfs|f2fs)$ ]]; then
        ((install_score += 4))
        detection_methods+=("persistent-fs")
    fi
    
    # Method 5: Check for live media mount points
    if findmnt /run/live/medium >/dev/null 2>&1; then
        ((live_score += 2))
        detection_methods+=("live-medium")
        
        # Check if media is read-only ISO
        if mount | grep -q "/run/live/medium.*ro.*iso9660" 2>/dev/null; then
            echo "${c6} ¤ ISO BOOT    ${bold}${c2}"
            return
        fi
    fi
    
    # Method 6: LUKS encryption detection
    if [[ -d /dev/mapper ]] && ls /dev/mapper/luks-* >/dev/null 2>&1; then
        if findmnt /union >/dev/null 2>&1 || [[ $live_score -gt 0 ]]; then
            echo "${c6} ¤ LIVE LUKS   ${bold}${c2}"
            return
        fi
    fi
    
    # Method 7: EFI detection for system type hints
    local efi_detected=false
    if [[ -d /sys/firmware/efi ]]; then
        efi_detected=true
        # Small EFI partition indicates full installation
        local esp_size
        esp_size=$(lsblk -o SIZE,PARTTYPE 2>/dev/null | grep -i efi | head -1 | awk '{print $1}' | sed 's/[^0-9.]//g')
        if [[ -n "$esp_size" ]] && (( $(echo "$esp_size < 500" | bc -l 2>/dev/null || echo "0") )); then
            ((install_score += 2))
            detection_methods+=("small-esp")
        fi
    fi
    
    # Method 8: tmpfs usage analysis
    local tmpfs_count
    tmpfs_count=$(mount | grep tmpfs | wc -l 2>/dev/null || echo "0")
    if [[ $tmpfs_count -gt 15 ]]; then
        ((live_score += 1))
        detection_methods+=("high-tmpfs")
    fi
    
    # Method 9: RAM vs filesystem size analysis
    local total_ram used_ram root_size
    total_ram=$(free -m 2>/dev/null | awk '/^Mem:/{print $2}' || echo "0")
    root_size=$(df -m / 2>/dev/null | awk 'NR==2{print $3}' || echo "0")
    
    if [[ $root_size -gt 0 && $total_ram -gt 0 ]]; then
        local ratio=$((root_size * 100 / total_ram))
        if [[ $ratio -gt 40 ]]; then
            ((live_score += 2))
            detection_methods+=("ram-ratio")
        fi
    fi
    
    # Method 10: Check for live filesystem files
    local live_files=("/run/live/medium/live/filesystem.squashfs" "/casper/filesystem.squashfs" "/LiveOS/squashfs.img")
    for file in "${live_files[@]}"; do
        if [[ -f "$file" ]]; then
            ((live_score += 3))
            detection_methods+=("live-files")
            break
        fi
    done
    
    # Final determination with confidence scoring
    if [[ $live_score -ge 6 ]]; then
        # High confidence live system - check for RAM boot
        if ! findmnt /run/live/medium >/dev/null 2>&1 && [[ $live_score -ge 8 ]]; then
            echo "${c6} ¤ RAM BOOT    ${bold}${c2}"
        else
            echo "${c6} ¤ LIVE SYSTEM ${bold}${c2}"
        fi
    elif [[ $live_score -ge 3 ]]; then
        # Medium confidence live system
        echo "${c6} ¤ LIVE BOOT   ${bold}${c2}"
    elif [[ $install_score -ge 4 ]]; then
        # High confidence installed system
        echo "${c6} ¤ FULL SYSTEM ${bold}${c2}"
    else
        # Fallback detection
        if [[ -f /etc/fstab ]] && grep -q "UUID=" /etc/fstab 2>/dev/null; then
            echo "${c6} ¤ FULL SYSTEM ${bold}${c2}"
        else
            echo "${c6} ¤ LIVE SYSTEM ${bold}${c2}"
        fi
    fi
}

# Function to get system information
get_system_info() {
    hostname_info=$(hostname 2>/dev/null || echo "Unknown")
    os_info="Bonsai GNU/Linux"
    kernel_info=$(uname -r 2>/dev/null || echo "Unknown")
    uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' || echo "Unknown")
    
    # Get host/model info
    if [[ -f /sys/devices/virtual/dmi/id/product_name ]]; then
        host_info=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "Unknown")
        if [[ -f /sys/devices/virtual/dmi/id/product_version ]]; then
            host_version=$(cat /sys/devices/virtual/dmi/id/product_version 2>/dev/null || echo "")
            [[ "$host_version" != "Unknown" ]] && [[ -n "$host_version" ]] && host_info="$host_info $host_version"
        fi
    else
        host_info="Unknown"
    fi
    
    memory_info=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}' || echo "Unknown")
    disks_space_f=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}' || echo "Unknown")
    
    # Get IP addresses
    private_ipv4_adress_lan=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}' || echo "Unavailable")
    public_ipv4_adress_wan=$(timeout 2 curl -s ifconfig.me 2>/dev/null || echo "Unavailable")
    
    # Get CPU info
    cpu_info=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' | sed 's/ CPU.*//' || echo "Unknown")
    
    # Get package count
    if command -v dpkg >/dev/null 2>&1; then
        packages=$(dpkg -l 2>/dev/null | grep -c "^ii" || echo "Unknown")
    else
        packages="Unknown"
    fi
}

# Typewriter effect function
typewriter() {
    local text="$1"
    local delay="${2:-0.10}"
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%b" "${text:$i:1}"
        sleep "$delay"
    done
    printf "\n"
}

# Main fetch function
main() {
    # Get system information
    get_system_info
    
    # Get dynamic boot status with advanced detection
    local boot_status
    boot_status=$(detect_boot_type)
    
    # Fixed cyberpunk UI display - EXACT formatting preserved (16x37 character area)
    cat << DISPLAY

${c2}${bold}${c2}⊏══════╗${boot_status}
${c2}${bold}${c2}SYSTEM ╚════════════════╗${reset}
${c6}${c5}Linux: ${reset}$os_info${c2} ║${reset}
${c6}${c5}Kernel: ${reset}$kernel_info${c2} ╔╝${reset}
${c2}${bold}${c2}SESSION ⊏══════════════╝⊏═══════╗${reset}
${c2}${c5}CPU:${reset} $cpu_info${c2} ║${reset}
${c2}${c5}Disks: ${reset}$disks_space_f${c2}  ╔══╝${reset}
${c2}${c5}RAM: ${reset}$memory_info${c2} ╔═══════════╝${reset}
${c2}${bold}${c2}NETWORK ⊏════════╝${reset}${c2}⊏══════╗${reset} 
${c2}${c5}WAN-IPv4: ${reset}$public_ipv4_adress_wan${c2}  ║${reset}
${c2}${c5}LAN-IPv4: ${reset}$private_ipv4_adress_lan ${c2}     ║${reset}
${reset}${c2}⊏════════════════════════╝${reset}
DISPLAY
 
    # Add typewriter effects if requested
    if [[ "$1" == "--typewriter" ]] || [[ $- == *i* ]]; then
        typewriter "${c7}-> ${c7}WELCOME${bold}${c7} to Bonsai V4.0"
        typewriter "${c7}-> ${c6}apps${bold}${c7} start CLI Toolkit"
        typewriter "${c7}-> ${c6}startx${bold}${c7} JWM GUI Desktop"
        
        # Show SSH connection info if applicable
        if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
            ssh_ip=$(echo "$SSH_CLIENT" | cut -d' ' -f1 2>/dev/null || echo "Unknown")
            echo ""
            typewriter "   ${c5}SSH connection from: $ssh_ip${reset}" 0.02
        fi
        echo ""
    fi
    
    # Reset colors
    printf "${reset}"
}

# Parse arguments
case "$1" in
    "--help"|"-h")
        echo "Bonsai Linux Fetch Tool - Advanced Detection Edition"
        echo "Usage: bonsaifetch [options]"
        echo ""
        echo "Options:"
        echo "  --typewriter    Include typewriter effects"
        echo "  --help, -h      Show this help message"
        echo ""
        echo "Examples:"
        echo "  bonsaifetch                # Cyberpunk system info"
        echo "  bonsaifetch --typewriter   # With typewriter effects"
        echo ""
        echo "Advanced Boot Detection:"
        echo "  • LIVE SYSTEM   - Standard live system"
        echo "  • RAM BOOT      - Live system copied to RAM"
        echo "  • LIVE LUKS     - Encrypted live system"
        echo "  • ISO BOOT      - Booted from ISO/IMG"
        echo "  • PERSISTENT    - Live system with persistence"
        echo "  • FULL SYSTEM   - Normal installed system"
        echo ""
        echo "Detection Methods:"
        echo "  • Kernel command line analysis"
        echo "  • Filesystem type detection"
        echo "  • SquashFS and overlay detection"
        echo "  • Live directory structure analysis"
        echo "  • EFI system partition analysis"
        echo "  • Memory usage pattern analysis"
        echo "  • Multi-method verification with scoring"
        exit 0
        ;;
    *)
        main "$@"
        ;;
esac
EOF
    
    chmod +x "/usr/local/bin/bonsaifetch"
    print_status "Created advanced bonsaifetch command: /usr/local/bin/bonsaifetch"
}

# Create the MOTD header script (DISABLED by default)
create_sidebyside_header() {
    print_step "Creating MOTD header script (disabled by default)..."
    
    cat > "$MOTD_DIR/01-bonsai-header" << 'EOF'
#!/bin/bash
# Bonsai Linux MOTD - Advanced Cyberpunk Header
# This script is disabled by default - use 'bonsaifetch' command instead

# Execute the standalone bonsaifetch command
if command -v bonsaifetch >/dev/null 2>&1; then
    bonsaifetch --typewriter
else
    echo "bonsaifetch command not found"
fi
EOF
    
    chmod -x "$MOTD_DIR/01-bonsai-header"  # DISABLED by default
    print_status "Created disabled header script: 01-bonsai-header (use 'sudo bonsai-motd enable' to activate)"
}

# Create disabled system info script
create_disabled_sysinfo() {
    print_step "Creating disabled system info script..."
    
    cat > "$MOTD_DIR/02-bonsai-sysinfo" << 'EOF'
#!/bin/bash
# Bonsai Linux MOTD - System Information (Disabled - integrated into bonsaifetch)
# This script is disabled because system info is now in the standalone bonsaifetch tool

exit 0
EOF
    
    chmod -x "$MOTD_DIR/02-bonsai-sysinfo"  # Make it non-executable
    print_status "Created disabled system info script: 02-bonsai-sysinfo"
}

# Create disabled typewriter script
create_disabled_typewriter() {
    print_step "Creating disabled typewriter script..."
    
    cat > "$MOTD_DIR/03-bonsai-typewriter" << 'EOF'
#!/bin/bash
# Bonsai Linux MOTD - Typewriter Effects (Disabled - integrated into bonsaifetch)
# This script is disabled because typewriter effects are now in the standalone bonsaifetch tool

exit 0
EOF
    
    chmod -x "$MOTD_DIR/03-bonsai-typewriter"  # Make it non-executable
    print_status "Created disabled typewriter script: 03-bonsai-typewriter"
}

# Create management tools
create_management_tools() {
    print_step "Creating management tools..."
    
    cat > "/usr/local/bin/bonsai-motd" << 'EOF'
#!/bin/bash
# Bonsai Linux MOTD Management Tool - Advanced Edition

MOTD_DIR="/etc/update-motd.d"

case "$1" in
    "test")
        echo "Testing Bonsai Linux Advanced MOTD (same as 'bonsaifetch --typewriter')..."
        echo ""
        if command -v bonsaifetch >/dev/null 2>&1; then
            bonsaifetch --typewriter
        else
            echo "bonsaifetch command not found"
        fi
        ;;
    "enable")
        chmod +x "$MOTD_DIR/01-bonsai-header"
        echo "Bonsai Advanced MOTD enabled - will show on login"
        echo "Note: This uses the standalone bonsaifetch command with advanced detection"
        ;;
    "disable")
        chmod -x "$MOTD_DIR"/??-bonsai-*
        echo "Bonsai MOTD disabled - use 'bonsaifetch' command manually"
        ;;
    "update")
        if command -v update-motd >/dev/null 2>&1; then
            update-motd
            echo "MOTD cache updated"
        else
            echo "update-motd command not available"
        fi
        ;;
    *)
        echo "Bonsai Linux Advanced MOTD Management Tool"
        echo "Usage: $0 {command}"
        echo ""
        echo "Commands:"
        echo "  test     - Show MOTD preview (same as 'bonsaifetch --typewriter')"
        echo "  enable   - Enable MOTD on login"
        echo "  disable  - Disable MOTD on login"
        echo "  update   - Update MOTD cache"
        echo ""
        echo "Primary Usage:"
        echo "  bonsaifetch              - Show cyberpunk system info anytime"
        echo "  bonsaifetch --typewriter - Show with typewriter effects"
        echo ""
        echo "Advanced Detection Features:"
        echo "  • Multi-method boot type detection with scoring system"
        echo "  • Kernel command line analysis for accurate live detection"
        echo "  • Filesystem type analysis (overlay, squashfs, ext4, etc.)"
        echo "  • EFI system partition analysis for installation type hints"
        echo "  • Memory usage pattern analysis for RAM boot detection"
        echo "  • LUKS encryption detection for encrypted live systems"
        echo "  • Cross-verification with multiple detection methods"
        echo "  • Failsafe detection with confidence scoring"
        echo ""
        echo "Note: MOTD is disabled by default. Use 'bonsaifetch' command instead."
        exit 1
        ;;
esac
EOF

    chmod +x "/usr/local/bin/bonsai-motd"
    print_status "Created advanced management tool: bonsai-motd"
}

# Test the bonsaifetch command
test_bonsaifetch() {
    print_step "Testing advanced bonsaifetch command..."
    
    echo ""
    print_info "Advanced Bonsaifetch Preview:"
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                      ADVANCED BONSAIFETCH PREVIEW                          ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    # Test bonsaifetch
    if command -v bonsaifetch >/dev/null 2>&1; then
        bonsaifetch --typewriter 2>/dev/null || {
            print_warning "bonsaifetch test completed with warnings"
        }
    else
        print_error "bonsaifetch command not found"
    fi
    
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Main installation function
main() {
    print_banner
    
    check_root
    
    print_info "Starting Bonsai Linux Advanced Fetch Tool installation..."
    print_info "This will create:"
    print_info "  • 'bonsaifetch' - Advanced cyberpunk fetch tool (primary tool)"
    print_info "  • Multi-method boot detection with 10+ verification methods"
    print_info "  • Fixed UI formatting (exact 16x37 character layout)"
    print_info "  • Robust error handling and fallback detection"
    print_info "  • MOTD components (DISABLED by default)"
    print_info "  • Management tools for optional MOTD activation"
    
    # Ask for confirmation
    read -p "Continue with installation? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Installation steps
    install_update_motd
    clean_existing_motd
    create_bonsaifetch
    create_sidebyside_header
    create_disabled_sysinfo
    create_disabled_typewriter
    create_management_tools
    test_bonsaifetch
    
    # Final information
    echo ""
    print_status "Bonsai Linux Advanced Fetch Tool installation completed successfully!"
    echo ""
    print_info "🎯 Primary Tool Installed:"
    echo -e "  ${GREEN}• bonsaifetch${NC}               - Advanced cyberpunk system info"
    echo -e "  ${GREEN}• bonsaifetch --typewriter${NC}  - With typewriter effects"
    echo ""
    print_info "📁 Files Created:"
    echo "  • Fetch Tool: /usr/local/bin/bonsaifetch"
    echo "  • MOTD Management: /usr/local/bin/bonsai-motd"
    echo "  • MOTD Scripts: $MOTD_DIR (DISABLED by default)"
    echo "  • Backup: $BACKUP_DIR"
    echo ""
    print_info "🔧 Usage Examples:"
    echo -e "  ${CYAN}bonsaifetch${NC}                    # Advanced system info"
    echo -e "  ${CYAN}bonsaifetch --typewriter${NC}       # With animations"
    echo -e "  ${CYAN}sudo bonsai-motd enable${NC}        # Enable MOTD on login"
    echo -e "  ${CYAN}sudo bonsai-motd disable${NC}       # Disable MOTD"
    echo -e "  ${CYAN}echo 'bonsaifetch' >> ~/.bashrc${NC} # Add to bashrc"
    echo ""
    print_info "🎨 Advanced Features:"
    echo "  • 10+ detection methods with confidence scoring"
    echo "  • Kernel command line analysis (most reliable)"
    echo "  • Filesystem type detection (overlay, squashfs, ext4)"
    echo "  • Live directory structure analysis"
    echo "  • EFI system partition analysis"
    echo "  • Memory usage pattern analysis for RAM boot"
    echo "  • LUKS encryption detection"
    echo "  • Multi-method cross-verification"
    echo "  • Fixed UI formatting (16x37 character layout)"
    echo "  • Robust error handling and fallbacks"
    echo ""
    print_info "🚀 Boot Detection Types:"
    echo "  • LIVE SYSTEM   - Standard live system from media"
    echo "  • RAM BOOT      - Live system copied to RAM (toram parameter)"
    echo "  • LIVE LUKS     - Encrypted live system with LUKS"
    echo "  • ISO BOOT      - Booted from read-only ISO/IMG"
    echo "  • PERSISTENT    - Live system with persistence layer"
    echo "  • FULL SYSTEM   - Normal installed system (high confidence)"
    echo ""
    print_warning "MOTD is DISABLED by default - use 'bonsaifetch' command instead!"
    print_info "Try it now: bonsaifetch --typewriter"
    
    echo ""
    print_info "🔬 Detection Methods Used:"
    echo "  1. Kernel command line analysis (boot=live, toram, etc.)"
    echo "  2. Live system directory structure (/run/live, /casper, etc.)"
    echo "  3. SquashFS filesystem detection (mount analysis)"
    echo "  4. Root filesystem type (overlay vs ext4/xfs/btrfs)"
    echo "  5. Live media mount point verification"
    echo "  6. LUKS encryption device detection"
    echo "  7. EFI system partition size analysis"
    echo "  8. tmpfs usage pattern analysis"
    echo "  9. RAM vs filesystem size ratio analysis"
    echo "  10. Live filesystem file detection"
    echo "  + Fallback methods with confidence scoring"
}

# Run the main function
main "$@"