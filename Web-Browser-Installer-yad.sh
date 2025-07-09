#!/bin/bash

# Web Browser Installer Utility using YAD
# Installs popular web browsers on Debian/Ubuntu systems

# Check if running as root
if [[ $EUID -eq 0 ]]; then
   echo "This script should not be run as root for security reasons."
   echo "It will use sudo when needed."
   exit 1
fi

# Check dependencies
check_dependencies() {
    local deps=("yad" "wget" "curl")
    local missing=()
    
    for dep in "${deps[@]}"; do
        if ! command -v "$dep" &> /dev/null; then
            missing+=("$dep")
        fi
    done
    
    if [ ${#missing[@]} -ne 0 ]; then
        yad --error --width=400 --height=150 \
            --title="Missing Dependencies" \
            --text="The following dependencies are missing:\n\n${missing[*]}\n\nPlease install them first:\nsudo apt update && sudo apt install yad wget curl"
        exit 1
    fi
}

# Browser definitions
declare -A BROWSERS=(
    ["Thorium (Chromium-based, optimized)"]="https://github.com/Alex313031/thorium/releases/download/M130.0.6723.174/thorium-browser_130.0.6723.174_AVX.deb"
    ["Brave Browser (Privacy-focused)"]="https://github.com/brave/brave-browser/releases/download/v1.80.115/brave-browser_1.80.115_amd64.deb"
    ["Tor Browser Launcher (Anonymity)"]="http://ftp.us.debian.org/debian/pool/contrib/t/torbrowser-launcher/torbrowser-launcher_0.3.7-3_amd64.deb"
)

# Create temp directory
TEMP_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_DIR"' EXIT

# Function to download and install browser
install_browser() {
    local browser_name="$1"
    local download_url="$2"
    local filename=$(basename "$download_url")
    local filepath="$TEMP_DIR/$filename"
    
    # Download progress dialog
    (
        echo "10"
        echo "# Downloading $browser_name..."
        
        if wget -O "$filepath" "$download_url" 2>&1 | \
           stdbuf -o0 awk '/[0-9]+%/ { print substr($0,match($0,/[0-9]+%/),4) }' | \
           while read percentage; do
               echo "$percentage"
               echo "# Downloading $browser_name... $percentage"
           done
        then
            echo "90"
            echo "# Download completed. Installing..."
            
            # Install the package
            if sudo dpkg -i "$filepath" 2>&1; then
                echo "95"
                echo "# Fixing dependencies..."
                sudo apt-get install -f -y
                echo "100"
                echo "# Installation completed!"
            else
                echo "# Installation failed!"
                exit 1
            fi
        else
            echo "# Download failed!"
            exit 1
        fi
    ) | yad --progress --width=500 --height=150 \
           --title="Installing $browser_name" \
           --text="Please wait while $browser_name is being installed..." \
           --auto-close --auto-kill
    
    return ${PIPESTATUS[0]}
}

# Function to show browser selection dialog
show_browser_selection() {
    local browser_list=""
    
    for browser in "${!BROWSERS[@]}"; do
        browser_list+="FALSE\n$browser\n"
    done
    
    # Remove last newline
    browser_list=${browser_list%\\n}
    
    local selected_browsers
    selected_browsers=$(echo -e "$browser_list" | yad --list \
        --radiolist \
        --width=600 \
        --height=400 \
        --title="gLiTcH Linux - Web Browser Installer" \
        --text="Select a web browser to install:" \
        --column="Install" \
        --column="Browser" \
        --separator="|" \
        --button="Install:0" \
        --button="Cancel:1")
    
    if [ $? -eq 0 ] && [ -n "$selected_browsers" ]; then
        echo "$selected_browsers"
    else
        return 1
    fi
}

# Function to show installation confirmation
show_confirmation() {
    local browser_name="$1"
    local browser_url="${BROWSERS[$browser_name]}"
    
    yad --question \
        --width=500 \
        --height=200 \
        --title="Confirm Installation" \
        --text="You are about to install:\n\n<b>$browser_name</b>\n\nDownload URL:\n$browser_url\n\nThis will:\n• Download the .deb package\n• Install using dpkg\n• Fix dependencies with apt\n\nProceed with installation?" \
        --button="Install:0" \
        --button="Cancel:1"
}

# Function to show installation result
show_result() {
    local success=$1
    local browser_name="$2"
    
    if [ $success -eq 0 ]; then
        yad --info \
            --width=400 \
            --height=150 \
            --title="Installation Complete" \
            --text="<b>$browser_name</b> has been successfully installed!\n\nYou can now find it in your applications menu." \
            --button="OK:0"
    else
        yad --error \
            --width=400 \
            --height=150 \
            --title="Installation Failed" \
            --text="Failed to install <b>$browser_name</b>.\n\nPlease check your internet connection and try again." \
            --button="OK:0"
    fi
}

# Function to show about dialog
show_about() {
    yad --info \
        --width=500 \
        --height=300 \
        --title="About Browser Installer" \
        --text="<b>gLiTcH Linux - Web Browser Installer</b>\n\nVersion: 1.0\n\nA utility to easily install popular web browsers on Debian/Ubuntu systems.\n\n<b>Supported Browsers:</b>\n• Thorium - Optimized Chromium fork\n• Brave - Privacy-focused browser\n• Tor Browser Launcher - Anonymity tool\n\n<b>Features:</b>\n• Automatic dependency resolution\n• Progress indicators\n• Error handling\n• Clean temporary file management\n\nDeveloped for gLiTcH Linux" \
        --button="OK:0"
}

# Main function
main() {
    check_dependencies
    
    while true; do
        # Show main menu
        local action
        action=$(yad --form \
            --width=500 \
            --height=300 \
            --title="gLiTcH Linux - Browser Installer" \
            --text="<b>Web Browser Installer Utility</b>\n\nSelect an action:" \
            --field="":LBL "" \
            --field="Install Browser":BTN "bash -c 'echo install'" \
            --field="About":BTN "bash -c 'echo about'" \
            --field="Exit":BTN "bash -c 'echo exit'" \
            --separator="|" \
            --buttons-layout=spread)
        
        case "$action" in
            *"install"*)
                selected_browser=$(show_browser_selection)
                if [ $? -eq 0 ] && [ -n "$selected_browser" ]; then
                    browser_name=$(echo "$selected_browser" | cut -d'|' -f2)
                    
                    if show_confirmation "$browser_name"; then
                        install_browser "$browser_name" "${BROWSERS[$browser_name]}"
                        show_result $? "$browser_name"
                    fi
                fi
                ;;
            *"about"*)
                show_about
                ;;
            *"exit"*|"")
                break
                ;;
        esac
    done
}

# Run main function
main