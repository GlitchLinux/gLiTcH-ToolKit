#!/bin/bash

# Master Bonsai MOTD Installer with Configuration System
# Creates fastfetch/neofetch style side-by-side layout with full configuration
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
BOLD='\033[1m'
NC='\033[0m' # No Color

# Configuration variables
MOTD_DIR="/etc/update-motd.d"
CONFIG_FILE="$MOTD_DIR/bonsai-motd.conf"
BACKUP_DIR="/etc/motd-backup-$(date +%Y%m%d-%H%M%S)"

# Function to print colored output
print_banner() {
    echo -e "${CYAN}"
    echo "╔══════════════════════════════════════════════════════════════════╗"
    echo "║                 Bonsai Linux MOTD Master Installer              ║"
    echo "║                        by GlitchLinux                           ║"
    echo "║           Fastfetch/Neofetch Style with Configuration           ║"
    echo "╚══════════════════════════════════════════════════════════════════╝"
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

# Install update-motd package and dependencies
install_dependencies() {
    print_step "Installing dependencies and update-motd package..."
    
    # Install basic dependencies first
    apt-get update -qq
    apt-get install -y wget curl lsb-release lshw || {
        print_warning "Some basic packages failed to install, continuing..."
    }
    
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
        apt-get install -y update-motd || {
            print_warning "Could not install update-motd"
        }
    fi
    
    cd "$original_dir"
}

# Create configuration file
create_config_file() {
    print_step "Creating configuration file..."
    
    cat > "$CONFIG_FILE" << 'EOF'
# Bonsai Linux MOTD Configuration File
# Edit these settings to customize your MOTD display
# Values: true/false

# Core MOTD Settings
Enable_System_Motd=true
Enable_Login_Display=true

# Display Components
Ascii_Art=true
System_Info_Header=true
Typewriter_Text=true

# System Information Details
Show_Hostname=true
Show_Kernel=true
Show_Uptime=true
Show_Model=true
Show_Memory=true
Show_Disk=true
Show_Theme=true
Show_CPU=true
Show_GPU=true
Show_Video_Resolution=true
Show_Package_Count=true
Show_Network_Info=true
Show_SSH_Info=true

# Display Preferences
Clear_Screen=true
Use_Colors=true
Fast_Mode=false

# Typewriter Settings
Typewriter_Speed=0.03
Show_Apps_Command=true
Show_Startx_Command=true
Show_Support_Link=false

# Network Settings
Public_IP_Timeout=2
Skip_Public_IP=false

# Theme and Colors
ASCII_Color=cyan
Info_Color=yellow
Header_Color=cyan
Text_Color=white

# Advanced Settings
Debug_Mode=false
Log_Errors=false
EOF
    
    chmod 644 "$CONFIG_FILE"
    print_status "Created configuration file: $CONFIG_FILE"
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
        
        # Remove all existing scripts except our config
        find "$MOTD_DIR" -type f ! -name "bonsai-motd.conf" -delete 2>/dev/null || true
        print_status "Removed all existing MOTD scripts"
    fi
    
    # Ensure MOTD directory exists
    mkdir -p "$MOTD_DIR"
}

# Create the main MOTD script with configuration support
create_main_motd_script() {
    print_step "Creating main configurable MOTD script..."
    
    cat > "$MOTD_DIR/01-bonsai-motd" << 'EOF'
#!/bin/bash
# Bonsai Linux Configurable MOTD Script

# Configuration file
CONFIG_FILE="/etc/update-motd.d/bonsai-motd.conf"

# Load configuration with defaults
load_config() {
    # Default values
    Enable_System_Motd="true"
    Enable_Login_Display="true"
    Ascii_Art="true"
    System_Info_Header="true"
    Typewriter_Text="true"
    Show_Hostname="true"
    Show_Kernel="true"
    Show_Uptime="true"
    Show_Model="true"
    Show_Memory="true"
    Show_Disk="true"
    Show_Theme="true"
    Show_CPU="true"
    Show_GPU="true"
    Show_Video_Resolution="true"
    Show_Package_Count="true"
    Show_Network_Info="true"
    Show_SSH_Info="true"
    Clear_Screen="true"
    Use_Colors="true"
    Fast_Mode="false"
    Typewriter_Speed="0.03"
    Show_Apps_Command="true"
    Show_Startx_Command="true"
    Show_Support_Link="false"
    Public_IP_Timeout="2"
    Skip_Public_IP="false"
    ASCII_Color="cyan"
    Info_Color="yellow"
    Header_Color="cyan"
    Text_Color="white"
    Debug_Mode="false"
    Log_Errors="false"
    
    # Load from config file if it exists
    if [[ -f "$CONFIG_FILE" ]]; then
        while IFS='=' read -r key value; do
            # Skip comments and empty lines
            [[ $key =~ ^#.*$ ]] && continue
            [[ -z $key ]] && continue
            
            # Remove any trailing comments
            value=$(echo "$value" | cut -d'#' -f1 | sed 's/[[:space:]]*$//')
            
            # Set the variable
            case "$key" in
                Enable_System_Motd) Enable_System_Motd="$value" ;;
                Enable_Login_Display) Enable_Login_Display="$value" ;;
                Ascii_Art) Ascii_Art="$value" ;;
                System_Info_Header) System_Info_Header="$value" ;;
                Typewriter_Text) Typewriter_Text="$value" ;;
                Show_Hostname) Show_Hostname="$value" ;;
                Show_Kernel) Show_Kernel="$value" ;;
                Show_Uptime) Show_Uptime="$value" ;;
                Show_Model) Show_Model="$value" ;;
                Show_Memory) Show_Memory="$value" ;;
                Show_Disk) Show_Disk="$value" ;;
                Show_Theme) Show_Theme="$value" ;;
                Show_CPU) Show_CPU="$value" ;;
                Show_GPU) Show_GPU="$value" ;;
                Show_Video_Resolution) Show_Video_Resolution="$value" ;;
                Show_Package_Count) Show_Package_Count="$value" ;;
                Show_Network_Info) Show_Network_Info="$value" ;;
                Show_SSH_Info) Show_SSH_Info="$value" ;;
                Clear_Screen) Clear_Screen="$value" ;;
                Use_Colors) Use_Colors="$value" ;;
                Fast_Mode) Fast_Mode="$value" ;;
                Typewriter_Speed) Typewriter_Speed="$value" ;;
                Show_Apps_Command) Show_Apps_Command="$value" ;;
                Show_Startx_Command) Show_Startx_Command="$value" ;;
                Show_Support_Link) Show_Support_Link="$value" ;;
                Public_IP_Timeout) Public_IP_Timeout="$value" ;;
                Skip_Public_IP) Skip_Public_IP="$value" ;;
                ASCII_Color) ASCII_Color="$value" ;;
                Info_Color) Info_Color="$value" ;;
                Header_Color) Header_Color="$value" ;;
                Text_Color) Text_Color="$value" ;;
                Debug_Mode) Debug_Mode="$value" ;;
                Log_Errors) Log_Errors="$value" ;;
            esac
        done < "$CONFIG_FILE"
    fi
}

# Color setup function
setup_colors() {
    if [[ "$Use_Colors" != "true" ]]; then
        c1="" c2="" c3="" c4="" c5="" c6="" c7="" bold="" reset=""
        return
    fi
    
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
    
    # Set theme colors based on config
    case "$ASCII_Color" in
        red) ascii_color="$c1" ;;
        green) ascii_color="$c2" ;;
        yellow) ascii_color="$c3" ;;
        blue) ascii_color="$c4" ;;
        magenta) ascii_color="$c5" ;;
        cyan) ascii_color="$c6" ;;
        white) ascii_color="$c7" ;;
        *) ascii_color="$c6" ;;
    esac
    
    case "$Info_Color" in
        red) info_color="$c1" ;;
        green) info_color="$c2" ;;
        yellow) info_color="$c3" ;;
        blue) info_color="$c4" ;;
        magenta) info_color="$c5" ;;
        cyan) info_color="$c6" ;;
        white) info_color="$c7" ;;
        *) info_color="$c3" ;;
    esac
    
    case "$Header_Color" in
        red) header_color="$c1" ;;
        green) header_color="$c2" ;;
        yellow) header_color="$c3" ;;
        blue) header_color="$c4" ;;
        magenta) header_color="$c5" ;;
        cyan) header_color="$c6" ;;
        white) header_color="$c7" ;;
        *) header_color="$c6" ;;
    esac
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

# System information gathering
get_system_info() {
    [[ "$Show_Hostname" == "true" ]] && hostname_info=$(hostname 2>/dev/null || echo "Unknown")
    [[ "$Show_Kernel" == "true" ]] && kernel_info=$(uname -r 2>/dev/null || echo "Unknown")
    [[ "$Show_Uptime" == "true" ]] && uptime_info=$(uptime -p 2>/dev/null | sed 's/up //' || echo "Unknown")
    
    if [[ "$Show_Model" == "true" ]]; then
        if [[ -f /sys/devices/virtual/dmi/id/product_name ]]; then
            host_info=$(cat /sys/devices/virtual/dmi/id/product_name 2>/dev/null || echo "Unknown")
            host_version=$(cat /sys/devices/virtual/dmi/id/product_version 2>/dev/null || echo "")
            [[ "$host_version" != "Unknown" ]] && [[ -n "$host_version" ]] && host_info="$host_info $host_version"
        else
            host_info="Unknown"
        fi
    fi
    
    [[ "$Show_Memory" == "true" ]] && memory_info=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}' || echo "Unknown")
    [[ "$Show_Disk" == "true" ]] && disk_info=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}' || echo "Unknown")
    
    [[ "$Show_Theme" == "true" ]] && theme_info="Orchis-Dark-Compact"
    
    if [[ "$Show_Network_Info" == "true" ]]; then
        private_ip=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $7; exit}' || hostname -I 2>/dev/null | awk '{print $1}' || echo "Unavailable")
        if [[ "$Skip_Public_IP" != "true" ]]; then
            public_ip=$(timeout "$Public_IP_Timeout" curl -s ifconfig.me 2>/dev/null || echo "Unavailable")
        else
            public_ip="Disabled"
        fi
    fi
    
    [[ "$Show_CPU" == "true" ]] && cpu_info=$(grep "model name" /proc/cpuinfo 2>/dev/null | head -1 | cut -d: -f2 | sed 's/^ *//' | sed 's/ CPU.*//' || echo "Unknown")
    [[ "$Show_GPU" == "true" ]] && gpu_info=$(lspci 2>/dev/null | grep -i "vga\|3d\|display" | head -1 | sed 's/.*: //' | sed 's/ Corporation.*//' || echo "Unknown")
    
    if [[ "$Show_Video_Resolution" == "true" ]]; then
        if command -v xrandr >/dev/null 2>&1 && [[ -n "$DISPLAY" ]]; then
            resolution=$(xrandr 2>/dev/null | grep '\*' | awk '{print $1}' | head -1 || echo "Unknown")
        else
            resolution="Unknown"
        fi
    fi
    
    if [[ "$Show_Package_Count" == "true" ]]; then
        if command -v dpkg >/dev/null 2>&1; then
            packages=$(dpkg -l 2>/dev/null | grep -c "^ii" || echo "Unknown")
        else
            packages="Unknown"
        fi
    fi
}

# Typewriter effect function
typewriter() {
    local text="$1"
    local delay="${2:-$Typewriter_Speed}"
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%b" "${text:$i:1}"
        sleep "$delay"
    done
    printf "\n"
}

# Main display function
main_display() {
    # Load configuration
    load_config
    
    # Check if MOTD is enabled
    [[ "$Enable_System_Motd" != "true" ]] && exit 0
    
    # Initialize colors
    setup_colors
    
    # Clear screen if enabled
    if [[ "$Clear_Screen" == "true" ]] && [[ -t 1 ]]; then
        clear 2>/dev/null || true
    fi
    
    # Get system information
    get_system_info
    
    # Display ASCII art and system info side by side
    if [[ "$Ascii_Art" == "true" && "$System_Info_Header" == "true" ]]; then
        cat << DISPLAY
${ascii_color}               #@@&@=%#&@@               ${bold}${header_color}═══ System Information ═══${reset}
${ascii_color}        @%@%&%&&%##%~@&#&&¤&@#@#         ${info_color}Host:${reset}    ${hostname_info:-Unknown} Bonsai GNU/Linux
${ascii_color}       @@%@✱#%@@|&%#@@%||&#&Y_#%@#@##    ${info_color}Kernel:${reset}  ${kernel_info:-Unknown}
${ascii_color}        &@#%@&@|&@@@%##@#####/#@#%&@#%   ${info_color}Uptime:${reset}  ${uptime_info:-Unknown}
${ascii_color}      &&&@|%%@&@%\\==@@=#@&&#%✱@@#&@%#    ${info_color}Model:${reset}   ${host_info:-Unknown}
${ascii_color}   %%@%&✱✱&#&&✻✻@=#;✻✻✻✻%#%&#@@%@✻✻✻✻    ${info_color}RAM:${reset}     ${memory_info:-Unknown}
${ascii_color}   &@%&@#;%#&✻✻#%#✻%=|/##✻✻###@@%@✻✻✻    ${info_color}Disk:${reset}    ${disk_info:-Unknown}
${ascii_color}  #@&%_=\\@✱✱=@✻/✻~%✱|||✻@✻=✻@#@&%✻✻✻✻✻   ${info_color}Theme:${reset}   ${theme_info:-Unknown}
${ascii_color}@%&%%&%&\\##✱✱✱   \\||:|:/    ✻&#@✻✻✻✻✻#   ${info_color}LAN IP:${reset}  ${private_ip:-Unknown}
${ascii_color}  #####@@||#      \\|||/       #✻#@@@✻    ${info_color}WAN IP:${reset}  ${public_ip:-Unknown}
${ascii_color} @%#@=/&&✱         ||;         @#@#✻     ${info_color}CPU:${reset}     ${cpu_info:-Unknown}
${ascii_color}   @&✱/    \\✻✻✻✻✻✻✻✻✻✻✻✻✻✻✻✻/   \\@✻@     ${info_color}GPU:${reset}     ${gpu_info:-Unknown}
${ascii_color}   ✻#✻      \\ ${c7}Bonsai${ascii_color}~${c7}Linux${ascii_color} /     #@#     ${info_color}Video:${reset}   ${resolution:-Unknown}
${ascii_color}     ✻       \\✻✻✻✻✻✻✻✻✻✻✻✻/      ✻       ${info_color}DPKG:${reset}    ${packages:-Unknown}
${reset}
DISPLAY
    elif [[ "$Ascii_Art" == "true" ]]; then
        # ASCII art only
        echo -e "${ascii_color}"
        cat << 'ASCIIART'
               #@@&@=%#&@@
        @%@%&%&&%##%~@&#&&¤&@#@#
       @@%@✱#%@@|&%#@@%||&#&Y_#%@#@##
        &@#%@&@|&@@@%##@#####/#@#%&@#%
      &&&@|%%@&@%\==@@=#@&&#%✱@@#&@%#
   %%@%&✱✱&#&&✻✻@=#;✻✻✻✻%#%&#@@%@✻✻✻✻
   &@%&@#;%#&✻✻#%#✻%=|/##✻✻###@@%@✻✻✻
  #@&%_=\@✱✱=@✻/✻~%✱|||✻@✻=✻@#@&%✻✻✻✻✻
@%&%%&%&\##✱✱✱   \||:|:/    ✻&#@✻✻✻✻✻#
  #####@@||#      \|||/       #✻#@@@✻
 @%#@=/&&✱         ||;         @#@#✻
   @&✱/    \✻✻✻✻✻✻✻✻✻✻✻✻✻✻✻✻/   \@✻@
   ✻#✻      \ Bonsai~Linux /     #@#
     ✻       \✻✻✻✻✻✻✻✻✻✻✻✻/      ✻
ASCIIART
        echo -e "${reset}"
    elif [[ "$System_Info_Header" == "true" ]]; then
        # System info only
        echo -e "${bold}${header_color}═══ System Information ═══${reset}"
        [[ "$Show_Hostname" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "Host:" "${hostname_info:-Unknown} Bonsai GNU/Linux"
        [[ "$Show_Kernel" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "Kernel:" "${kernel_info:-Unknown}"
        [[ "$Show_Uptime" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "Uptime:" "${uptime_info:-Unknown}"
        [[ "$Show_Model" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "Model:" "${host_info:-Unknown}"
        [[ "$Show_Memory" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "RAM:" "${memory_info:-Unknown}"
        [[ "$Show_Disk" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "Disk:" "${disk_info:-Unknown}"
        [[ "$Show_Theme" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "Theme:" "${theme_info:-Unknown}"
        [[ "$Show_Network_Info" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "LAN IP:" "${private_ip:-Unknown}"
        [[ "$Show_Network_Info" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "WAN IP:" "${public_ip:-Unknown}"
        [[ "$Show_CPU" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "CPU:" "${cpu_info:-Unknown}"
        [[ "$Show_GPU" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "GPU:" "${gpu_info:-Unknown}"
        [[ "$Show_Video_Resolution" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "Video:" "${resolution:-Unknown}"
        [[ "$Show_Package_Count" == "true" ]] && printf "${info_color}%-12s${reset} %s\n" "DPKG:" "${packages:-Unknown}"
        echo ""
    fi
    
    # Display typewriter text
    if [[ "$Typewriter_Text" == "true" ]]; then
        [[ "$Show_Apps_Command" == "true" ]] && typewriter "   ${c7}-> Run: ${c2}apps${c7} to start using CLI toolkit"
        [[ "$Show_Startx_Command" == "true" ]] && typewriter "   ${c7}-> Run: ${c2}startx${c7} to launch JWM GUI Desktop"
        
        # Show SSH connection info if enabled and applicable
        if [[ "$Show_SSH_Info" == "true" ]] && [[ -n "$SSH_CLIENT" || -n "$SSH_TTY" ]]; then
            ssh_ip=$(echo "$SSH_CLIENT" | cut -d' ' -f1 2>/dev/null || echo "Unknown")
            echo ""
            typewriter "   ${c5}SSH connection from: $ssh_ip${reset}" 0.02
        fi
        
        [[ "$Show_Support_Link" == "true" ]] && typewriter "   ${c7}For support, visit: ${c4}https://github.com/GlitchLinux${reset}" 0.02
        
        echo ""
    fi
    
    # Reset colors
    printf "${reset}"
}

# Run only if enabled and in appropriate context
if [[ "$Enable_Login_Display" == "true" ]] && ([[ $- == *i* ]] || [[ -n "$SSH_TTY" ]] || [[ -n "$SSH_CLIENT" ]] || [[ "$USER" != "root" ]]); then
    main_display 2>/dev/null || true
fi
EOF
    
    chmod +x "$MOTD_DIR/01-bonsai-motd"
    print_status "Created main configurable MOTD script: 01-bonsai-motd"
}

# Create enhanced management tool
create_management_tool() {
    print_step "Creating enhanced management tool..."
    
    cat > "/usr/local/bin/bonsai-motd" << 'EOF'
#!/bin/bash
# Bonsai Linux MOTD Management Tool with Configuration Support

MOTD_DIR="/etc/update-motd.d"
CONFIG_FILE="$MOTD_DIR/bonsai-motd.conf"
MOTD_SCRIPT="$MOTD_DIR/01-bonsai-motd"

# Color definitions
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
NC='\033[0m'

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_info() { echo -e "${BLUE}[i]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[!]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }

# Function to update config value
update_config() {
    local key="$1"
    local value="$2"
    
    if [[ -f "$CONFIG_FILE" ]]; then
        if grep -q "^$key=" "$CONFIG_FILE"; then
            sed -i "s/^$key=.*/$key=$value/" "$CONFIG_FILE"
        else
            echo "$key=$value" >> "$CONFIG_FILE"
        fi
        print_status "Updated $key to $value"
    else
        print_error "Configuration file not found: $CONFIG_FILE"
        exit 1
    fi
}

# Function to get config value
get_config() {
    local key="$1"
    if [[ -f "$CONFIG_FILE" ]]; then
        grep "^$key=" "$CONFIG_FILE" 2>/dev/null | cut -d'=' -f2 | head -1
    fi
}

case "$1" in
    "test")
        echo "Testing Bonsai Linux MOTD..."
        echo ""
        [[ -x "$MOTD_SCRIPT" ]] && "$MOTD_SCRIPT" || print_error "MOTD script not found or not executable"
        ;;
    "enable")
        update_config "Enable_System_Motd" "true"
        update_config "Enable_Login_Display" "true"
        chmod +x "$MOTD_SCRIPT" 2>/dev/null
        ;;
    "disable")
        update_config "Enable_System_Motd" "false"
        update_config "Enable_Login_Display" "false"
        ;;
    "enable-ascii")
        update_config "Ascii_Art" "true"
        ;;
    "disable-ascii")
        update_config "Ascii_Art" "false"
        ;;
    "enable-sysinfo")
        update_config "System_Info_Header" "true"
        ;;
    "disable-sysinfo")
        update_config "System_Info_Header" "false"
        ;;
    "enable-typewriter")
        update_config "Typewriter_Text" "true"
        ;;
    "disable-typewriter")
        update_config "Typewriter_Text" "false"
        ;;
    "fast-mode")
        update_config "Fast_Mode" "true"
        update_config "Typewriter_Speed" "0.01"
        update_config "Skip_Public_IP" "true"
        print_status "Enabled fast mode"
        ;;
    "slow-mode")
        update_config "Fast_Mode" "false"
        update_config "Typewriter_Speed" "0.05"
        update_config "Skip_Public_IP" "false"
        print_status "Enabled slow mode"
        ;;
    "no-colors")
        update_config "Use_Colors" "false"
        ;;
    "colors")
        update_config "Use_Colors" "true"
        ;;
    "config")
        if [[ -f "$CONFIG_FILE" ]]; then
            echo -e "${BOLD}${CYAN}Bonsai MOTD Configuration:${NC}"
            echo ""
            cat "$CONFIG_FILE"
        else
            print_error "Configuration file not found"
        fi
        ;;
    "edit-config")
        if [[ -f "$CONFIG_FILE" ]]; then
            ${EDITOR:-nano} "$CONFIG_FILE"
            print_status "Configuration updated. Changes will take effect on next display."
        else
            print_error "Configuration file not found"
        fi
        ;;
    "status")
        echo -e "${BOLD}${CYAN}Bonsai MOTD Status:${NC}"
        echo ""
        printf "%-20s %s\n" "System MOTD:" "$(get_config Enable_System_Motd)"
        printf "%-20s %s\n" "Login Display:" "$(get_config Enable_Login_Display)"
        printf "%-20s %s\n" "ASCII Art:" "$(get_config Ascii_Art)"
        printf "%-20s %s\n" "System Info:" "$(get_config System_Info_Header)"
        printf "%-20s %s\n" "Typewriter:" "$(get_config Typewriter_Text)"
        printf "%-20s %s\n" "Colors:" "$(get_config Use_Colors)"
        printf "%-20s %s\n" "Fast Mode:" "$(get_config Fast_Mode)"
        echo ""
        ;;
    "reset")
        if [[ -f "$CONFIG_FILE" ]]; then
            print_warning "Resetting configuration to defaults..."
            rm -f "$CONFIG_FILE"
            # Recreate default config
            cat > "$CONFIG_FILE" << 'DEFAULTCONF'
# Bonsai Linux MOTD Configuration File
Enable_System_Motd=true
Enable_Login_Display=true
Ascii_Art=true
System_Info_Header=true
Typewriter_Text=true
Show_Hostname=true
Show_Kernel=true
Show_Uptime=true
Show_Model=true
Show_Memory=true
Show_Disk=true
Show_Theme=true
Show_CPU=true
Show_GPU=true
Show_Video_Resolution=true
Show_Package_Count=true
Show_Network_Info=true
Show_SSH_Info=true
Clear_Screen=true
Use_Colors=true
Fast_Mode=false
Typewriter_Speed=0.03
Show_Apps_Command=true
Show_Startx_Command=true
Show_Support_Link=false
Public_IP_Timeout=2
Skip_Public_IP=false
ASCII_Color=cyan
Info_Color=yellow
Header_Color=cyan
Text_Color=white
Debug_Mode=false
Log_Errors=false
DEFAULTCONF
            print_status "Configuration reset to defaults"
        fi
        ;;
    "update")
        if command -v update-motd >/dev/null 2>&1; then
            update-motd
            print_status "MOTD cache updated"
        else
            print_warning "update-motd command not available"
        fi
        ;;
    *)
        echo -e "${BOLD}${CYAN}Bonsai Linux MOTD Management${NC}"
        echo "Usage: $0 {command}"
        echo ""
        echo -e "${BOLD}Testing & Display:${NC}"
        echo "  test              - Show MOTD preview"
        echo "  status            - Show current configuration status"
        echo ""
        echo -e "${BOLD}Enable/Disable Components:${NC}"
        echo "  enable            - Enable MOTD system"
        echo "  disable           - Disable MOTD system"
        echo "  enable-ascii      - Enable ASCII art"
        echo "  disable-ascii     - Disable ASCII art"
        echo "  enable-sysinfo    - Enable system information"
        echo "  disable-sysinfo   - Disable system information"
        echo "  enable-typewriter - Enable typewriter effects"
        echo "  disable-typewriter - Disable typewriter effects"
        echo ""
        echo -e "${BOLD}Display Modes:${NC}"
        echo "  fast-mode         - Enable fast display mode"
        echo "  slow-mode         - Enable slow display mode"
        echo "  colors            - Enable colors"
        echo "  no-colors         - Disable colors"
        echo ""
        echo -e "${BOLD}Configuration:${NC}"
        echo "  config            - Show current configuration"
        echo "  edit-config       - Edit configuration file"
        echo "  reset             - Reset to default configuration"
        echo "  update            - Update MOTD cache"
        echo ""
        echo -e "${BOLD}Examples:${NC}"
        echo "  bonsai-motd test                    # Test current setup"
        echo "  sudo bonsai-motd disable-typewriter # Disable typewriter"
        echo "  sudo bonsai-motd fast-mode          # Enable fast mode"
        echo "  sudo bonsai-motd edit-config        # Edit config file"
        exit 1
        ;;
esac
EOF

    chmod +x "/usr/local/bin/bonsai-motd"
    print_status "Created enhanced management tool: /usr/local/bin/bonsai-motd"
}

# Create bash alias
create_bash_alias() {
    print_step "Creating bash alias..."
    
    # Check if alias already exists
    if ! grep -q "alias bonsai-motd=" /etc/bash.bashrc 2>/dev/null; then
        echo "" >> /etc/bash.bashrc
        echo "# Bonsai Linux MOTD alias" >> /etc/bash.bashrc
        echo "alias bonsai-motd='bonsai-motd test'" >> /etc/bash.bashrc
        print_status "Added bonsai-motd alias to /etc/bash.bashrc"
    else
        print_info "Bonsai MOTD alias already exists in /etc/bash.bashrc"
    fi
}

# Test the complete system
test_motd_system() {
    print_step "Testing configurable MOTD system..."
    
    # Update MOTD cache
    if command -v update-motd >/dev/null 2>&1; then
        update-motd 2>/dev/null || true
        print_status "MOTD cache updated"
    fi
    
    echo ""
    print_info "Configurable MOTD Preview:"
    echo -e "${CYAN}╔════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${CYAN}║                              PREVIEW                                       ║${NC}"
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    
    # Test the system
    if [[ -x "$MOTD_DIR/01-bonsai-motd" ]]; then
        "$MOTD_DIR/01-bonsai-motd" 2>/dev/null || {
            print_warning "MOTD test completed with warnings"
        }
    else
        print_error "MOTD script not found or not executable"
    fi
    
    echo -e "${CYAN}╚════════════════════════════════════════════════════════════════════════════╝${NC}"
    echo ""
}

# Show configuration options
show_config_help() {
    print_step "Configuration file created with these options:"
    echo ""
    echo -e "${BOLD}${CYAN}Configuration Options:${NC}"
    echo ""
    echo -e "${BOLD}Core Settings:${NC}"
    echo "  Enable_System_Motd      - Enable/disable entire MOTD system"
    echo "  Enable_Login_Display    - Show MOTD on login"
    echo ""
    echo -e "${BOLD}Display Components:${NC}"
    echo "  Ascii_Art              - Show ASCII art"
    echo "  System_Info_Header     - Show system information"
    echo "  Typewriter_Text        - Enable typewriter effects"
    echo ""
    echo -e "${BOLD}System Information:${NC}"
    echo "  Show_Hostname          - Display hostname"
    echo "  Show_Kernel            - Display kernel version"
    echo "  Show_Uptime            - Display system uptime"
    echo "  Show_Model             - Display hardware model"
    echo "  Show_Memory            - Display memory usage"
    echo "  Show_Disk              - Display disk usage"
    echo "  Show_Theme             - Display desktop theme"
    echo "  Show_CPU               - Display CPU information"
    echo "  Show_GPU               - Display GPU information"
    echo "  Show_Video_Resolution  - Display screen resolution"
    echo "  Show_Package_Count     - Display package count"
    echo "  Show_Network_Info      - Display IP addresses"
    echo "  Show_SSH_Info          - Display SSH connection info"
    echo ""
    echo -e "${BOLD}Display Preferences:${NC}"
    echo "  Clear_Screen           - Clear screen before display"
    echo "  Use_Colors             - Enable colored output"
    echo "  Fast_Mode              - Fast display mode"
    echo ""
    echo -e "${BOLD}Typewriter Settings:${NC}"
    echo "  Typewriter_Speed       - Speed of typewriter effect (seconds)"
    echo "  Show_Apps_Command      - Show 'apps' command"
    echo "  Show_Startx_Command    - Show 'startx' command"
    echo "  Show_Support_Link      - Show GitHub support link"
    echo ""
    echo -e "${BOLD}Network Settings:${NC}"
    echo "  Public_IP_Timeout      - Timeout for public IP lookup"
    echo "  Skip_Public_IP         - Skip public IP lookup entirely"
    echo ""
    echo -e "${BOLD}Colors:${NC}"
    echo "  ASCII_Color            - Color for ASCII art (red/green/yellow/blue/magenta/cyan/white)"
    echo "  Info_Color             - Color for information labels"
    echo "  Header_Color           - Color for headers"
    echo "  Text_Color             - Color for text"
    echo ""
}

# Main installation function
main() {
    print_banner
    
    check_root
    
    print_info "Starting Bonsai Linux MOTD Master Installation..."
    print_info "This installer will:"
    print_info "  • Download and install update-motd package"
    print_info "  • Create configurable MOTD system"
    print_info "  • Set up management tools and aliases"
    print_info "  • Create comprehensive configuration file"
    print_info "  • Enable fastfetch/neofetch style display"
    
    # Ask for confirmation
    read -p "Continue with installation? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    # Installation steps
    install_dependencies
    clean_existing_motd
    create_config_file
    create_main_motd_script
    create_management_tool
    create_bash_alias
    test_motd_system
    show_config_help
    
    # Final information
    echo ""
    print_status "Bonsai Linux MOTD Master Installation completed successfully!"
    echo ""
    print_info "Installation Summary:"
    echo "  • Main MOTD Script: $MOTD_DIR/01-bonsai-motd"
    echo "  • Configuration File: $CONFIG_FILE"
    echo "  • Management Tool: /usr/local/bin/bonsai-motd"
    echo "  • Bash Alias: Added to /etc/bash.bashrc"
    echo "  • Backup: $BACKUP_DIR"
    echo ""
    print_info "Quick Start Commands:"
    echo "  • Test MOTD: bonsai-motd test"
    echo "  • Check status: bonsai-motd status"
    echo "  • Edit config: sudo bonsai-motd edit-config"
    echo "  • Enable fast mode: sudo bonsai-motd fast-mode"
    echo "  • Disable typewriter: sudo bonsai-motd disable-typewriter"
    echo ""
    print_info "Usage Modes:"
    echo "  • Login MOTD: Automatically displays on login"
    echo "  • Manual fetch: Run 'bonsai-motd' command anytime"
    echo "  • Bashrc integration: Alias available system-wide"
    echo ""
    print_warning "The MOTD will appear on your next login session."
    print_info "To see it now, run: bonsai-motd"
    
    echo ""
    print_info "Configuration file location: $CONFIG_FILE"
    print_info "Edit with: sudo bonsai-motd edit-config"
    
    # Show current alias status
    echo ""
    print_info "Bash alias created: 'bonsai-motd' now runs 'bonsai-motd test'"
    print_info "Reload your shell or run: source /etc/bash.bashrc"
}

# Run the main function
main "$@"
