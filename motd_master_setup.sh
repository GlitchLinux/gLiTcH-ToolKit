#!/bin/bash

# Master MOTD Setup Script for Bonsai Linux
# Configures custom neofetch with editable ASCII art as MOTD
# Author: GlitchLinux
# Compatible with Debian/Ubuntu systems

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
NEOFETCH_DIR="/etc/neofetch"
ASCII_FILE="$NEOFETCH_DIR/ascii.txt"
MOTD_DIR="/etc/update-motd.d"
MOTD_SCRIPT="$MOTD_DIR/01-bonsai-neofetch"
BACKUP_DIR="/etc/motd-backup-$(date +%Y%m%d-%H%M%S)"

# Function to print colored output
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║              Bonsai Linux MOTD Setup Script              ║"
    echo "║                    by GlitchLinux                        ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_info() {
    echo -e "${BLUE}[i]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_step() {
    echo -e "${MAGENTA}[STEP]${NC} $1"
}

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        echo "Usage: sudo $0"
        exit 1
    fi
}

# Detect the distribution
detect_distro() {
    if [[ -f /etc/os-release ]]; then
        . /etc/os-release
        DISTRO=$ID
        VERSION=$VERSION_ID
        print_info "Detected: $PRETTY_NAME"
    else
        print_warning "Could not detect distribution, assuming Debian/Ubuntu compatibility"
        DISTRO="unknown"
    fi
}

# Create necessary directories
create_directories() {
    print_step "Creating directories..."
    
    # Create neofetch config directory
    if [[ ! -d "$NEOFETCH_DIR" ]]; then
        mkdir -p "$NEOFETCH_DIR"
        print_status "Created $NEOFETCH_DIR"
    else
        print_info "$NEOFETCH_DIR already exists"
    fi
    
    # Create MOTD directory if it doesn't exist
    if [[ ! -d "$MOTD_DIR" ]]; then
        mkdir -p "$MOTD_DIR"
        print_status "Created $MOTD_DIR"
    else
        print_info "$MOTD_DIR already exists"
    fi
    
    # Create backup directory for original MOTD files
    mkdir -p "$BACKUP_DIR"
    print_status "Created backup directory: $BACKUP_DIR"
}

# Create the ASCII art file
create_ascii_file() {
    print_step "Creating ASCII art file..."
    
    cat > "$ASCII_FILE" << 'EOF'
                                 
		#@@&@=%#&@@      
          @%@%&%&&%##%~@&#&&¤&@#@#           
         @@%@✱#%@@|&%#@@%||&#&Y_#%@#@##       
          &@#%@&@|&@@@%##@#####/#@#%&@#%      
        &&&@|%%@&@%\==@@=#@&&#%✱@@#&@%#     
    %%@%&✱✱&#&&✻✻@=#;✻✻✻✻%#%&#@@%@✻✻✻✻       
    &@%&@#;%#&✻✻#%#✻%=|/##✻✻###@@%@✻✻✻✻✻✻          
   #@&%_=\@✱✱=@✻/✻~%✱|||✻@✻=✻@#@&%✻✻✻✻✻✻✻       
 @%&%%&%&\##✱✱✱   \||:|:=✻@==#@&#@✻✻✻✻✻      
   #####@@||#       \|||/       @@@@@✻✻✻     
  @#%&&              ||:          @@@@✻@#✻ 
@%#@=/&&✱|           ||;             @#✻✻
  @&✱/       \✻✻✻✻✻✻✻✻✻✻✻✻✻✻✻✻/    ✻#@
   ✻✻✻        \ Bonsai~Linux /     ✻
    ✻          \✻✻✻✻✻✻✻✻✻✻✻✻/

  --> Run: "apps" to start using CLI toolkit
  --> Run: "startx" to launch JWM GUI Desktop 
EOF

    chmod 644 "$ASCII_FILE"
    print_status "Created ASCII art file: $ASCII_FILE"
    print_info "Users can edit this file to customize the ASCII art"
}

# Backup original MOTD files
backup_original_motd() {
    print_step "Backing up original MOTD files..."
    
    # List of files to backup
    local files_to_backup=(
        "/etc/motd"
        "/etc/issue"
        "/etc/issue.net"
        "$MOTD_DIR"
    )
    
    for item in "${files_to_backup[@]}"; do
        if [[ -e "$item" ]]; then
            cp -r "$item" "$BACKUP_DIR/" 2>/dev/null || true
            print_status "Backed up: $item"
        fi
    done
}

# Create the main MOTD script
create_motd_script() {
    print_step "Creating MOTD script..."
    
    cat > "$MOTD_SCRIPT" << 'EOF'
#!/bin/bash

# Bonsai Linux Custom MOTD Script
# ASCII art is stored in /etc/neofetch/ascii.txt for easy editing

# Color definitions
c1=$(tput setaf 1)  # Red
c2=$(tput setaf 2)  # Green  
c3=$(tput setaf 3)  # Yellow
c4=$(tput setaf 4)  # Blue
c5=$(tput setaf 5)  # Magenta
c6=$(tput setaf 6)  # Cyan
c7=$(tput setaf 7)  # White
bold=$(tput bold)
reset=$(tput sgr0)

# ASCII art file location
ASCII_FILE="/etc/neofetch/ascii.txt"

# Function to display ASCII art with colors
display_ascii() {
    if [[ -f "$ASCII_FILE" ]]; then
        # Read and display ASCII art with green highlighting for "Bonsai~Linux"
        while IFS= read -r line; do
            if [[ "$line" == *"Bonsai~Linux"* ]]; then
                echo -e "${c2}$line${reset}"
            elif [[ "$line" == *"-->"* ]]; then
                # Color the instruction lines
                echo -e "${c7}${line/apps/${c2}apps${c7}}"
                echo -e "${c7}${line/startx/${c2}startx${c7}}"
            else
                echo -e "${c6}$line${reset}"
            fi
        done < "$ASCII_FILE"
    else
        echo -e "${c1}Error: ASCII file not found at $ASCII_FILE${reset}"
        echo -e "${c3}Please run the setup script again to restore it.${reset}"
    fi
}

# Typewriter effect function (optional, faster for login)
typewriter_fast() {
    local text="$1"
    local delay="${2:-0.01}"  # Faster default delay
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%b" "${text:$i:1}"
        sleep "$delay"
    done
    printf "\n"
}

# Main display function
main() {
    # Clear screen for clean display
    clear
    
    # Display ASCII art
    display_ascii
    
    # Add some spacing
    echo ""
    
    # System information section
    echo -e "${bold}${c6}═══ System Information ═══${reset}"
    
    # Get system info
    local hostname=$(hostname)
    local uptime=$(uptime -p 2>/dev/null || echo "Unknown")
    local load=$(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3 || echo "Unknown")
    local memory=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}' || echo "Unknown")
    local disk=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}' || echo "Unknown")
    local kernel=$(uname -r 2>/dev/null || echo "Unknown")
    local users=$(who | wc -l 2>/dev/null || echo "Unknown")
    
    # Display system info with colors
    printf "${c3}%-12s${reset} %s\n" "Hostname:" "$hostname"
    printf "${c3}%-12s${reset} %s\n" "Kernel:" "$kernel"
    printf "${c3}%-12s${reset} %s\n" "Uptime:" "$uptime"
    printf "${c3}%-12s${reset} %s\n" "Load:" "$load"
    printf "${c3}%-12s${reset} %s\n" "Memory:" "$memory"
    printf "${c3}%-12s${reset} %s\n" "Disk:" "$disk"
    printf "${c3}%-12s${reset} %s\n" "Users:" "$users"
    
    echo ""
    
    # Welcome message
    echo -e "${bold}${c2}Welcome to Bonsai Linux!${reset}"
    echo -e "${c7}For support, visit: ${c4}https://github.com/GlitchLinux${reset}"
    
    # Show last login (for SSH users)
    if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
        echo -e "${c5}SSH connection from: ${SSH_CLIENT%% *}${reset}"
    fi
    
    echo ""
}

# Run only for interactive sessions
if [[ $- == *i* ]] || [[ -n "$SSH_TTY" ]]; then
    main
fi
EOF

    chmod +x "$MOTD_SCRIPT"
    print_status "Created MOTD script: $MOTD_SCRIPT"
}

# Disable default MOTD components
disable_default_motd() {
    print_step "Managing default MOTD components..."
    
    # List of default MOTD scripts to disable
    local default_scripts=(
        "00-header"
        "10-help-text"
        "50-motd-news"
        "50-landscape-sysinfo"
        "80-esm"
        "90-updates-available"
        "95-hwe-eol"
        "10-uname"
    )
    
    for script in "${default_scripts[@]}"; do
        local script_path="$MOTD_DIR/$script"
        if [[ -f "$script_path" ]]; then
            # Backup before disabling
            cp "$script_path" "$BACKUP_DIR/" 2>/dev/null || true
            chmod -x "$script_path" 2>/dev/null || true
            print_status "Disabled: $script"
        fi
    done
    
    # Disable Ubuntu Pro advertisements
    if [[ -f /etc/apt/apt.conf.d/20apt-esm-hook.conf ]]; then
        mv /etc/apt/apt.conf.d/20apt-esm-hook.conf /etc/apt/apt.conf.d/20apt-esm-hook.conf.disabled 2>/dev/null || true
        print_status "Disabled Ubuntu Pro advertisements"
    fi
    
    # Disable motd-news
    if command -v ubuntu-advantage >/dev/null 2>&1; then
        sed -i 's/^ENABLED=.*/ENABLED=0/' /etc/default/motd-news 2>/dev/null || true
        print_status "Disabled motd-news"
    fi
}

# Install required packages
install_dependencies() {
    print_step "Checking dependencies..."
    
    local packages_needed=()
    
    # Check for required commands
    if ! command -v tput >/dev/null 2>&1; then
        packages_needed+=("ncurses-utils")
    fi
    
    if ! command -v update-motd >/dev/null 2>&1; then
        packages_needed+=("update-motd")
    fi
    
    if [[ ${#packages_needed[@]} -gt 0 ]]; then
        print_info "Installing required packages: ${packages_needed[*]}"
        apt-get update -qq
        apt-get install -y "${packages_needed[@]}"
        print_status "Dependencies installed"
    else
        print_status "All dependencies satisfied"
    fi
}

# Test the MOTD setup
test_motd() {
    print_step "Testing MOTD setup..."
    
    # Update MOTD
    if command -v update-motd >/dev/null 2>&1; then
        update-motd
        print_status "MOTD updated"
    fi
    
    # Test run
    echo ""
    print_info "MOTD Preview:"
    echo -e "${CYAN}╔════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                PREVIEW                 ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    
    if [[ -x "$MOTD_SCRIPT" ]]; then
        "$MOTD_SCRIPT"
    else
        print_error "MOTD script is not executable"
        return 1
    fi
    
    echo -e "${CYAN}╚════════════════════════════════════════╝${NC}"
    echo ""
}

# Create management scripts
create_management_scripts() {
    print_step "Creating management scripts..."
    
    # Create MOTD management script
    cat > "/usr/local/bin/motd-manage" << 'EOF'
#!/bin/bash

# MOTD Management Script for Bonsai Linux

case "$1" in
    "edit")
        if [[ -f /etc/neofetch/ascii.txt ]]; then
            ${EDITOR:-nano} /etc/neofetch/ascii.txt
            echo "ASCII art updated. Changes will appear on next login."
        else
            echo "Error: ASCII file not found"
            exit 1
        fi
        ;;
    "test")
        if [[ -x /etc/update-motd.d/01-bonsai-neofetch ]]; then
            /etc/update-motd.d/01-bonsai-neofetch
        else
            echo "Error: MOTD script not found or not executable"
            exit 1
        fi
        ;;
    "enable")
        chmod +x /etc/update-motd.d/01-bonsai-neofetch
        echo "MOTD enabled"
        ;;
    "disable")
        chmod -x /etc/update-motd.d/01-bonsai-neofetch
        echo "MOTD disabled"
        ;;
    "restore")
        if [[ -d /etc/motd-backup-* ]]; then
            backup_dir=$(ls -td /etc/motd-backup-* | head -1)
            echo "Restoring from: $backup_dir"
            cp -r "$backup_dir"/* /etc/ 2>/dev/null
            echo "Original MOTD restored"
        else
            echo "No backup found"
            exit 1
        fi
        ;;
    *)
        echo "Bonsai Linux MOTD Management"
        echo "Usage: $0 {edit|test|enable|disable|restore}"
        echo ""
        echo "Commands:"
        echo "  edit     - Edit the ASCII art file"
        echo "  test     - Preview the MOTD"
        echo "  enable   - Enable custom MOTD"
        echo "  disable  - Disable custom MOTD"
        echo "  restore  - Restore original MOTD"
        exit 1
        ;;
esac
EOF

    chmod +x "/usr/local/bin/motd-manage"
    print_status "Created management script: /usr/local/bin/motd-manage"
}

# Main installation function
main() {
    print_banner
    
    check_root
    detect_distro
    
    print_info "Starting Bonsai Linux MOTD setup..."
    print_info "This will configure a custom MOTD with editable ASCII art"
    
    # Ask for confirmation
    read -p "Continue with installation? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Run installation steps
    create_directories
    backup_original_motd
    install_dependencies
    create_ascii_file
    create_motd_script
    disable_default_motd
    create_management_scripts
    test_motd
    
    # Final information
    echo ""
    print_status "Installation completed successfully!"
    echo ""
    print_info "Configuration Details:"
    echo "  • ASCII art file: $ASCII_FILE"
    echo "  • MOTD script: $MOTD_SCRIPT"
    echo "  • Backup location: $BACKUP_DIR"
    echo "  • Management tool: motd-manage"
    echo ""
    print_info "Usage Examples:"
    echo "  • Edit ASCII art: sudo motd-manage edit"
    echo "  • Test MOTD: motd-manage test"
    echo "  • Disable MOTD: sudo motd-manage disable"
    echo "  • Restore original: sudo motd-manage restore"
    echo ""
    print_warning "The custom MOTD will appear on your next login session."
    print_info "To see it now, run: motd-manage test"
}

# Run the main function
main "$@"