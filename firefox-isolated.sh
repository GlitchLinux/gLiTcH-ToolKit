#!/bin/bash

# Firefox Isolated Instance Script (Using Borderize)
# Downloads and runs Firefox AppImage in non-persistent mode

set -e  # Exit on any error

# Configuration
APPIMAGE_URL="https://glitchlinux.wtf/FILES/APPIMAGES/firefox-esr-128.13.r20250714124554-x86_64.AppImage"
APPIMAGE_NAME="firefox-esr-128.13.r20250714124554-x86_64.AppImage"
WORK_DIR="/tmp/firefox-isolated"
APPIMAGE_PATH="$WORK_DIR/$APPIMAGE_NAME"

# Check if borderize is available
if ! command -v borderize >/dev/null 2>&1; then
    echo "Error: borderize utility not found!"
    echo "Please install borderize first:"
    echo "  sudo curl -L https://raw.githubusercontent.com/GlitchLinux/BORDERIZE/refs/heads/main/borderize -o /usr/local/bin/borderize"
    echo "  sudo chmod +x /usr/local/bin/borderize"
    exit 1
fi

# Helper functions using borderize
print_status() {
    echo "[INFO] $1" | borderize -00FFFF -FFFFFF
}

print_success() {
    echo "[SUCCESS] $1" | borderize -00FF00 -FFFFFF
}

print_warning() {
    echo "[WARNING] $1" | borderize -FFA500 -FFFF00
}

print_error() {
    echo "[ERROR] $1" | borderize -FF0000 -FFFFFF
}

print_info_box() {
    printf "%s\n" "$@" | borderize -00CED1 -FFFFFF
}

print_menu() {
    printf "%s\n" "$@" | borderize -FFD700 -FFFFFF
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    if ! command_exists curl && ! command_exists wget; then
        missing_deps+=("curl or wget")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        echo ""
        echo -e "Install missing dependencies:\n 1 sudo apt install curl\n 2 sudo apt install wget" | borderize -FF1493 -FFFFFF
        echo ""
        exit 1
    fi
}

# Function to download Firefox AppImage
download_firefox() {
    if [[ -f "$APPIMAGE_PATH" ]]; then
        print_status "Firefox AppImage already exists"
        return 0
    fi

    print_status "Downloading Firefox AppImage..."
    
    # Show URL with borderize for long paths
    printf "URL: %s\nDestination: %s" "$APPIMAGE_URL" "$APPIMAGE_PATH" | borderize -800080 -FFD700
    echo ""
    
    if command_exists curl; then
        curl -L --progress-bar "$APPIMAGE_URL" -o "$APPIMAGE_PATH"
        download_result=$?
    elif command_exists wget; then
        wget --progress=bar:force "$APPIMAGE_URL" -O "$APPIMAGE_PATH"
        download_result=$?
    else
        print_error "Neither curl nor wget found"
        exit 1
    fi
    
    if [[ $download_result -eq 0 ]]; then
        local size=$(du -h "$APPIMAGE_PATH" | cut -f1)
        echo "Firefox AppImage downloaded! Size: $size" | borderize -32CD32 -000000
    else
        print_error "Failed to download Firefox AppImage"
        exit 1
    fi
}

# Function to make AppImage executable
make_executable() {
    print_status "Making AppImage executable..."
    sudo chmod +x "$APPIMAGE_PATH"
    
    if [[ $? -eq 0 ]]; then
        print_success "AppImage made executable"
    else
        print_error "Failed to make AppImage executable"
        exit 1
    fi
}

# Function to create temporary profile
create_temp_profile() {
    local temp_profile="$WORK_DIR/profile"
    mkdir -p "$temp_profile"
    echo "$temp_profile"
}

# Function to initialize temporary profile
initialize_profile() {
    local temp_profile="$1"
    
    print_status "Initializing temporary profile..."
    
    mkdir -p "$temp_profile"
    
    # Create a minimal prefs.js
    cat > "$temp_profile/prefs.js" << 'EOF'
// Firefox preferences for isolated instance
user_pref("browser.rights.3.shown", true);
user_pref("browser.startup.homepage_override.mstone", "ignore");
user_pref("startup.homepage_welcome_url", "");
user_pref("startup.homepage_welcome_url.additional", "");
user_pref("browser.migration.version", 1);
user_pref("browser.newtabpage.introShown", true);
user_pref("privacy.sanitize.sanitizeOnShutdown", true);
user_pref("privacy.clearOnShutdown.cache", true);
user_pref("privacy.clearOnShutdown.cookies", true);
user_pref("privacy.clearOnShutdown.downloads", true);
user_pref("privacy.clearOnShutdown.formdata", true);
user_pref("privacy.clearOnShutdown.history", true);
user_pref("privacy.clearOnShutdown.sessions", true);
EOF
    
    # Create times.json
    cat > "$temp_profile/times.json" << EOF
{
  "created": $(date +%s)000,
  "firstUse": null
}
EOF
    
    print_success "Temporary profile initialized"
}

# Function to cleanup problematic directories
cleanup_problematic_dirs() {
    local user_home="$HOME"
    
    print_status "Checking for problematic directories..."
    
    find "$user_home" -maxdepth 1 -type d -name "*INFO*" -o -name "*Created*" -o -name "*temporary*" 2>/dev/null | while IFS= read -r dir; do
        if [[ -d "$dir" && "$dir" != "$user_home" ]]; then
            print_status "Removing problematic directory: $(basename "$dir")"
            rm -rf "$dir"
        fi
    done
    sudo rm -f /tmp/start-firefox.html
    print_success "Cleanup completed"
}

# Function to cleanup all files
cleanup_all_files() {
    if [[ -d "$WORK_DIR" ]]; then
        print_status "Cleaning up all application files..."
        rm -rf "$WORK_DIR"
        print_success "Application directory cleaned up"
    fi
    
    local appimage_dir=$(dirname "$APPIMAGE_PATH")
    local appimage_name=$(basename "$APPIMAGE_PATH")
    local appimage_base="${appimage_name%.*}"
    local portable_home="${appimage_dir}/${appimage_base}.home"
    local portable_config="${appimage_dir}/${appimage_base}.config"
    sudo rm -f /tmp/start-firefox.html
    
    if [[ -d "$portable_home" ]]; then
        print_status "Cleaning portable home directory..."
        rm -rf "$portable_home"
        print_success "Portable home directory cleaned up"
    fi
    
    if [[ -d "$portable_config" ]]; then
        print_status "Cleaning portable config directory..."
        rm -rf "$portable_config"
        print_success "Portable config directory cleaned up"
    fi
    
    cleanup_problematic_dirs
}

# Function to show cleanup dialog
show_cleanup_dialog() {
    print_info_box "Firefox session has ended." "Delete Firefox AppImage and all files?"
    echo ""
    
    print_menu "1 Keep Files (faster next time)" "2 Delete All (free disk space)"
    echo ""
    
    read -p " -> " cleanup_choice
    echo ""
    
    case "$cleanup_choice" in
        1)
            echo "Files kept in $WORK_DIR" | borderize -567645 -FFFFFF
            ;;
        2)
            cleanup_all_files
            echo "All Firefox AppImage files deleted." | borderize -FF6347 -FFFFFF
            ;;
        *)
            echo "Invalid choice. Files kept by default." | borderize -FFFF00 -000000
            ;;
    esac
}

# Function to show startup notification
show_startup_notification() {
    print_info_box "🦊 Starting Firefox in isolated mode..." "⚠️  Important Notes:" "• This session will NOT save any data" "• Cookies, history, downloads temporary" "• All data deleted when Firefox closes"
    echo ""
    
    echo "Firefox will launch in a few seconds..."
    sleep 3
}

# Function to launch Firefox
launch_firefox() {
    local temp_profile="$1"
    
    print_status "Launching Firefox in isolated mode..."
    print_warning "No data will be saved (cookies, history)"
    
    show_startup_notification
    
    local original_home="$HOME"
    local temp_home="$WORK_DIR/isolated_home"
    mkdir -p "$temp_home"
    
    export HOME="$temp_home"
    export XDG_CONFIG_HOME="$temp_home/.config"
    export XDG_CACHE_HOME="$temp_home/.cache"
    export XDG_DATA_HOME="$temp_home/.local/share"
    
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
    
    "$APPIMAGE_PATH" --profile "$temp_profile" --new-instance /tmp/start-firefox.html
    
    export HOME="$original_home"
    unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME
    
    print_success "Firefox session ended."
}

# Function to show welcome dialog
show_welcome_dialog() {
    print_info_box "🦊 Welcome to Firefox Isolated Instance!" "This script will:" "• Download Firefox AppImage (if needed)" "• Create a temporary, isolated profile" "• Launch Firefox with no data persist" "• Clean up when you're done"
    echo ""
    
    echo "Press Enter to continue..."
    read
}

# Main execution
main() {
    print_status "Starting Firefox Isolated Instance Script"
    
    show_welcome_dialog
    check_dependencies
    
    mkdir -p "$WORK_DIR"
    
    download_firefox
    make_executable
    
    print_status "Creating temporary profile directory"
    TEMP_PROFILE=$(create_temp_profile)
    initialize_profile "$TEMP_PROFILE"
    
    launch_firefox "$TEMP_PROFILE"
    
    show_cleanup_dialog
}

# Create HTML start page
create_start_page() {
    cat > "/tmp/start-firefox.html" << 'EOF'
<!DOCTYPE html>
<html>
<head>
    <title>🦊 Firefox Isolated Session</title>
    <style>
        body { 
            font-family: 'Segoe UI', Tahoma, Geneva, Verdana, sans-serif; 
            background: linear-gradient(135deg, #667eea 0%, #764ba2 100%); 
            color: #ffffff; 
            text-align: center; 
            padding: 50px;
            margin: 0;
            min-height: 100vh;
            display: flex;
            flex-direction: column;
            justify-content: center;
        }
        .container {
            background: rgba(255, 255, 255, 0.1);
            backdrop-filter: blur(10px);
            border-radius: 20px;
            padding: 40px;
            max-width: 600px;
            margin: 0 auto;
            box-shadow: 0 8px 32px rgba(0, 0, 0, 0.3);
        }
        h1 { 
            color: #ffffff; 
            font-size: 2.5em;
            margin-bottom: 20px;
            text-shadow: 2px 2px 4px rgba(0, 0, 0, 0.3);
        }
        p { 
            font-size: 1.2em; 
            line-height: 1.6;
            margin: 15px 0;
        }
        .warning {
            background: rgba(255, 152, 0, 0.2);
            border: 2px solid rgba(255, 152, 0, 0.5);
            border-radius: 10px;
            padding: 20px;
            margin: 20px 0;
        }
        .feature-list {
            text-align: left;
            margin: 20px 0;
        }
        .feature-list li {
            margin: 10px 0;
            padding-left: 10px;
        }
    </style>
</head>
<body>
    <div class="container">
        <h1>🦊 Firefox Isolated Session</h1>
        <p>Welcome to your temporary, isolated browsing session!</p>
        
        <div class="warning">
            <p><strong>⚠️ Important:</strong> This is a completely isolated session.</p>
        </div>
        
        <div class="feature-list">
            <p><strong>What this means:</strong></p>
            <ul>
                <li>🚫 No browsing history will be saved</li>
                <li>🍪 No cookies will persist</li>
                <li>📁 No downloads will be kept</li>
                <li>🔑 No passwords will be remembered</li>
                <li>🧹 Everything is cleaned up when you close Firefox</li>
            </ul>
        </div>
        
        <p>Perfect for private browsing, testing, or temporary tasks!</p>
        <p><em>You can now navigate to any website you want.</em></p>
    </div>
</body>
</html>
EOF
    
    chmod 644 /tmp/start-firefox.html
}

# Help function
show_help() {
    print_info_box "Firefox Isolated Instance Script" "(Terminal Version with Borderize)"
    echo ""
    
    print_menu "Usage: $0 [OPTIONS]"
    echo ""
    
    print_menu "OPTIONS:" " -h, --help     Show this help" " -c, --clean    Remove AppImage" " -v, --version  Show version"
    echo ""
    
    echo "DESCRIPTION:"
    echo "  Downloads and runs Firefox AppImage in non-persistent mode"
    echo ""
    echo "FEATURES:"
    echo "  • Downloads Firefox AppImage automatically"
    echo "  • Creates temporary profile for each session"
    echo "  • Beautiful terminal interface using borderize"
    echo "  • Complete environment isolation"
    echo "  • No interference with system Firefox"
    echo ""
    echo "REQUIREMENTS:"
    echo "  • curl or wget (for downloading)"
    echo "  • borderize utility (for beautiful output)"
    echo ""
}

# Function to clean up downloaded AppImage
clean_appimage() {
    print_info_box "Are you sure you want to remove all" "Firefox AppImage files?"
    echo ""
    
    print_menu "1 Cancel" "2 Delete All"
    echo ""
    
    read -p " -> " clean_choice
    echo ""
    
    case "$clean_choice" in
        2)
            if [[ -d "$WORK_DIR" ]]; then
                print_status "Removing all application files..."
                rm -rf "$WORK_DIR"
                print_success "All application files removed"
                
                local appimage_base="${APPIMAGE_PATH%.*}"
                local portable_home="${appimage_base}.home"
                local portable_config="${appimage_base}.config"
                
                [[ -d "$portable_home" ]] && rm -rf "$portable_home" && print_success "Removed portable home directory"
                [[ -d "$portable_config" ]] && rm -rf "$portable_config" && print_success "Removed portable config directory"
                
                cleanup_problematic_dirs
                
                echo "✅ All Firefox files successfully deleted!" | borderize -00FF7F -000000
            else
                print_warning "No application files found to remove"
            fi
            ;;
        1|*)
            echo "Cleanup cancelled by user" | borderize -87CEEB -000000
            ;;
    esac
}

# Create start page before main execution
create_start_page

# Parse command line arguments
case "${1:-}" in
    -h|--help)
        show_help
        exit 0
        ;;
    -c|--clean)
        clean_appimage
        exit 0
        ;;
    -v|--version)
        print_info_box "Firefox Isolated Instance Script" "(Terminal Version with Borderize)" "Version: 2.2" "Interface: Terminal + Borderize" "Firefox Version: ESR 128.13"
        exit 0
        ;;
    "")
        main
        ;;
    *)
        print_error "Unknown option: $1"
        show_help
        exit 1
        ;;
esac
