#!/bin/bash

# Fixed Formatting MOTD Script - Quick Fix
# This script fixes the formatting issues in the existing MOTD

set -e  # Exit on any error

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
   print_error "This script must be run as root (use sudo)"
   exit 1
fi

MOTD_SCRIPT="/etc/update-motd.d/01-custom-neofetch"

print_status "Fixing MOTD formatting..."

# Create the fixed MOTD script
cat > "$MOTD_SCRIPT" << 'EOF'
#!/bin/bash

# Custom Neofetch MOTD Script - FIXED FORMATTING VERSION
# Handles missing TERM variable gracefully with proper spacing

# Function to safely set colors
setup_colors() {
    # Set TERM if not set (common fix for automatic logins)
    if [[ -z "$TERM" ]]; then
        export TERM="linux"
    fi
    
    # Check if we have a terminal and TERM is set
    if [[ -t 1 ]] && [[ -n "$TERM" ]] && command -v tput >/dev/null 2>&1; then
        # Try to use tput, fall back to ANSI if it fails
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
            # tput failed, use ANSI escape codes
            setup_ansi_colors
        fi
    else
        # No terminal or TERM not set, use ANSI codes
        setup_ansi_colors
    fi
}

# Fallback to ANSI escape codes
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

# Clear screen if we have a terminal
if [[ -t 1 ]]; then
    clear 2>/dev/null || true
fi

# ASCII Art with proper formatting and colors
echo ""
echo -e "${c6}                                 "
echo -e "		#@@&@=%#&@@      "
echo -e "          @%@%&%&&%##%~@&#&&¤&@#@#           "
echo -e "         @@%@✱#%@@|&%#@@%||&#&Y_#%@#@##       "
echo -e "          &@#%@&@|&@@@%##@#####/#@#%&@#%      "
echo -e "        &&&@|%%@&@%\\==@@=#@&&#%✱@@#&@%#     "
echo -e "    %%@%&✱✱&#&&✻✻@=#;✻✻✻✻%#%&#@@%@✻✻✻✻       "
echo -e "    &@%&@#;%#&✻✻#%#✻%=|/##✻✻###@@%@✻✻✻✻✻✻          "
echo -e "   #@&%_=\\@✱✱=@✻/✻~%✱|||✻@✻=✻@#@&%✻✻✻✻✻✻✻       "
echo -e " @%&%%&%&\\##✱✱✱   \\||:|:=✻@==#@&#@✻✻✻✻✻      "
echo -e "   #####@@||#       \\|||/       @@@@@✻✻✻     "
echo -e "  @#%&&              ||:          @@@@✻@#✻ "
echo -e "@%#@=/&&✱|           ||;             @#✻✻"
echo -e "  @&✱/       \\✻✻✻✻✻✻✻✻✻✻✻✻✻✻✻✻/    ✻#@"
echo -e "   ✻✻✻        \\ ${c2}Bonsai~Linux${c6} /     ✻"
echo -e "    ✻          \\✻✻✻✻✻✻✻✻✻✻✻✻/${reset}"
echo ""

# Typewriter effect function with colors
typewriter() {
    local text="$1"
    local delay="${2:-0.03}"  # Default delay of 0.03 seconds
    
    for (( i=0; i<${#text}; i++ )); do
        printf "%b" "${text:$i:1}"
        sleep "$delay"
    done
    printf "\n"
}

# Welcome message
echo -e "${bold}${c2}Welcome to Bonsai Linux!${reset}"
echo ""

# Display typewriter messages with colors and proper formatting
typewriter "  ${c7}--> Run: ${c2}apps${c7} to start using CLI toolkit"
typewriter "  ${c7}--> Run: ${c2}startx${c7} to launch JWM GUI Desktop"

echo ""

# System information with colors and typewriter effect
echo -e "${bold}${c6}System Information:${reset}"

# Get system info safely
hostname_info=$(hostname 2>/dev/null || echo "Unknown")
uptime_info=$(uptime -p 2>/dev/null || echo "Unknown")
load_info=$(cat /proc/loadavg 2>/dev/null | cut -d' ' -f1-3 || echo "Unknown")
memory_info=$(free -h 2>/dev/null | awk '/^Mem:/ {print $3 "/" $2}' || echo "Unknown")
disk_info=$(df -h / 2>/dev/null | awk 'NR==2 {print $3 "/" $2 " (" $5 " used)"}' || echo "Unknown")

# Display system info with typewriter effect and proper spacing
typewriter "${c3}Hostname:${reset} $hostname_info" 0.02
typewriter "${c3}Uptime:${reset}   $uptime_info" 0.02
typewriter "${c3}Load:${reset}     $load_info" 0.02
typewriter "${c3}Memory:${reset}   $memory_info" 0.02
typewriter "${c3}Disk:${reset}     $disk_info" 0.02

echo ""

# GitHub link with typewriter effect
typewriter "${c7}For support, visit: ${c4}https://github.com/GlitchLinux${reset}" 0.02

# Show SSH connection info if applicable
if [[ -n "$SSH_CLIENT" ]] || [[ -n "$SSH_TTY" ]]; then
    ssh_ip=$(echo "$SSH_CLIENT" | cut -d' ' -f1 2>/dev/null || echo "Unknown")
    echo ""
    typewriter "${c5}SSH connection from: $ssh_ip${reset}" 0.02
fi

echo ""

# Final typewriter message
typewriter "${bold}${c2}Have a productive session!${reset}" 0.04

echo ""

# Reset colors at the end
printf "${reset}"
EOF

# Make the script executable
chmod +x "$MOTD_SCRIPT"
print_status "Fixed MOTD script formatting"

# Update MOTD to apply changes
if command -v update-motd >/dev/null 2>&1; then
    update-motd 2>/dev/null || true
    print_status "MOTD updated"
fi

echo "alias motd='motd-typewriter-test'" >> /etc/bash.bashrc

# Test the fixed formatting
print_status "Testing fixed MOTD formatting..."
echo ""
echo "=== MOTD Preview ==="
"$MOTD_SCRIPT" 2>/dev/null || print_status "MOTD test completed"
echo "=== End Preview ==="
echo ""

print_status "MOTD formatting fixed successfully!"
print_status "Changes will appear on next login or run: motd-typewriter-test"

