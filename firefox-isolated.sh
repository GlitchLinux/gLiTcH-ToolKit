#!/bin/bash

# Firefox Isolated Instance Script (YAD Version)
# Downloads and runs Firefox AppImage in non-persistent mode

export GTK_THEME=Orchis:dark

set -e  # Exit on any error

# Configuration
APPIMAGE_URL="https://glitchlinux.wtf/FILES/APPIMAGES/firefox-esr-128.13.r20250714124554-x86_64.AppImage"
APPIMAGE_NAME="firefox-esr-128.13.r20250714124554-x86_64.AppImage"
WORK_DIR="/tmp/firefox-isolated"
APPIMAGE_PATH="$WORK_DIR/$APPIMAGE_NAME"

# Function to print output
print_status() {
    echo "[INFO] $1"
}

print_success() {
    echo "[SUCCESS] $1"
}

print_warning() {
    echo "[WARNING] $1"
}

print_error() {
    echo "[ERROR] $1"
}

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Function to check dependencies
check_dependencies() {
    local missing_deps=()
    
    # Check for required commands
    if ! command_exists yad; then
        missing_deps+=("yad")
    fi
    
    if ! command_exists curl && ! command_exists wget; then
        missing_deps+=("curl or wget")
    fi
    
    if [[ ${#missing_deps[@]} -gt 0 ]]; then
        print_error "Missing required dependencies: ${missing_deps[*]}"
        print_status "Install missing dependencies:"
        for dep in "${missing_deps[@]}"; do
            if [[ "$dep" == "yad" ]]; then
                print_status "  sudo apt install yad"
            elif [[ "$dep" == "curl or wget" ]]; then
                print_status "  sudo apt install curl (or wget)"
            fi
        done
        exit 1
    fi
}

# Function to download Firefox AppImage with YAD progress
download_firefox() {
    if [[ -f "$APPIMAGE_PATH" ]]; then
        print_status "Firefox AppImage already exists at $APPIMAGE_PATH"
        return 0
    fi

    print_status "Downloading Firefox AppImage with progress dialog..."
    
    # Download with YAD progress
    if command_exists curl; then
        curl -L "$APPIMAGE_URL" -o "$APPIMAGE_PATH" 2>&1 | \
        stdbuf -oL tr '\r' '\n' | \
        grep -oE '[0-9]+\.[0-9]+' | \
        cut -d'.' -f1 | \
        yad --progress \
            --title="Firefox Isolated - Download" \
            --text="Downloading Firefox AppImage...\n\nURL: $APPIMAGE_URL" \
            --width=500 \
            --height=150 \
            --center \
            --auto-close \
            --auto-kill \
            --no-buttons \
            --progress-text="Downloaded: %p%%" \
            --window-icon="firefox"
        
        download_result=${PIPESTATUS[0]}
        
    elif command_exists wget; then
        # For wget, we'll use pulsate mode since wget has different progress output
        yad --progress \
            --title="Firefox Isolated - Download" \
            --text="Downloading Firefox AppImage...\n\nURL: $APPIMAGE_URL\n\nPlease wait while the download completes." \
            --width=500 \
            --height=150 \
            --center \
            --pulsate \
            --auto-close \
            --auto-kill \
            --no-buttons \
            --progress-text="Downloading..." \
            --window-icon="firefox" &
        
        local yad_pid=$!
        
        wget "$APPIMAGE_URL" -O "$APPIMAGE_PATH" 2>/dev/null
        download_result=$?
        
        kill $yad_pid 2>/dev/null || true
        
    else
        print_error "Neither curl nor wget found. Please install one of them."
        yad --error \
            --title="Firefox Isolated - Error" \
            --text="Neither curl nor wget found.\n\nPlease install one of them:\n  sudo apt install curl\n  sudo apt install wget" \
            --width=400 \
            --height=150 \
            --center \
            --window-icon="error"
        exit 1
    fi
    
    if [[ $download_result -eq 0 ]]; then
        print_success "Firefox AppImage downloaded successfully"
        yad --info \
            --title="Firefox Isolated - Success" \
            --text="Firefox AppImage downloaded successfully!\n\nSize: $(du -h "$APPIMAGE_PATH" | cut -f1)" \
            --width=400 \
            --height=120 \
            --center \
            --timeout=3 \
            --window-icon="firefox"
    else
        print_error "Failed to download Firefox AppImage"
        yad --error \
            --title="Firefox Isolated - Error" \
            --text="Failed to download Firefox AppImage!\n\nPlease check your internet connection and try again." \
            --width=400 \
            --height=120 \
            --center \
            --window-icon="error"
        exit 1
    fi
}

# Function to make AppImage executable
make_executable() {
    print_status "Making AppImage executable..."
    chmod +x "/tmp/firefox-isolated/firefox-esr-128.13.r20250714124554-x86_64.AppImage"
    
    if [[ $? -eq 0 ]]; then
        print_success "AppImage made executable"
    else
        print_error "Failed to make AppImage executable"
        yad --error \
            --title="Firefox Isolated - Error" \
            --text="Failed to make AppImage executable!\n\nPath: $APPIMAGE_PATH" \
            --width=400 \
            --height=120 \
            --center \
            --window-icon="error"
        exit 1
    fi
}

# Function to create temporary profile
create_temp_profile() {
    local temp_profile="$WORK_DIR/profile"
    mkdir -p "$temp_profile"
    print_status "Created temporary profile directory: $temp_profile"
    echo "$temp_profile"
}

# Function to initialize temporary profile
initialize_profile() {
    local temp_profile="$1"
    
    print_status "Initializing temporary profile..."
    
    # Create basic profile structure
    mkdir -p "$temp_profile"
    
    # Create a minimal prefs.js to ensure Firefox recognizes the profile
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
    
    # Create times.json to mark profile as initialized
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
    # Clean up any directories created due to previous issues
    local user_home="$HOME"
    
    print_status "Checking for any problematic directories..."
    
    # Look for directories that might have been created with escape sequences
    find "$user_home" -maxdepth 1 -type d -name "*INFO*" -o -name "*Created*" -o -name "*temporary*" 2>/dev/null | while IFS= read -r dir; do
        if [[ -d "$dir" && "$dir" != "$user_home" ]]; then
            print_status "Removing problematic directory: $(basename "$dir")"
            rm -rf "$dir"
        fi
    done
    sudo rm -f /tmp/start-firefox.html
    print_success "Cleanup completed"
}

# Function to cleanup all files and AppImage portable directories
cleanup_all_files() {
    if [[ -d "$WORK_DIR" ]]; then
        print_status "Cleaning up all application files..."
        rm -rf "$WORK_DIR"
        print_success "Application directory cleaned up"
    fi
    
    # Clean up AppImage portable directories that may have been created in original location
    # These would be created alongside the AppImage if our environment override fails
    local appimage_dir=$(dirname "$APPIMAGE_PATH")
    local appimage_name=$(basename "$APPIMAGE_PATH")
    local appimage_base="${appimage_name%.*}"
    local portable_home="${appimage_dir}/${appimage_base}.home"
    local portable_config="${appimage_dir}/${appimage_base}.config"
    sudo rm -f /tmp/start-firefox.html
    if [[ -d "$portable_home" ]]; then
        print_status "Cleaning up AppImage portable home directory..."
        rm -rf "$portable_home"
        print_success "Portable home directory cleaned up"
    fi
    
    if [[ -d "$portable_config" ]]; then
        print_status "Cleaning up AppImage portable config directory..."
        rm -rf "$portable_config"
        print_success "Portable config directory cleaned up"
    fi
    
    # Clean up any problematic directories created due to output issues
    cleanup_problematic_dirs
}

# Function to show cleanup dialog
show_cleanup_dialog() {
    if yad --question \
        --title="Firefox Isolated - Session Ended" \
        --text="Firefox session has ended.\n\nWould you like to delete the Firefox AppImage and all application files?\n\nThis will free up disk space but you'll need to download Firefox again next time." \
        --width=450 \
        --height=150 \
        --center \
        --button="Keep Files:1" \
        --button="Delete All:0" \
        --default-button=0 \
        --window-icon="firefox"; then
        cleanup_all_files
        yad --info \
            --title="Firefox Isolated - Cleanup Complete" \
            --text="All Firefox AppImage files have been deleted.\n\nYour system is now clean." \
            --width=400 \
            --height=120 \
            --center \
            --timeout=3 \
            --window-icon="user-trash-full"
    else
        print_status "Files kept in $WORK_DIR"
        yad --info \
            --title="Firefox Isolated - Files Kept" \
            --text="Firefox AppImage and files have been kept.\n\nLocation: $WORK_DIR\n\nNext launch will be faster!" \
            --width=400 \
            --height=130 \
            --center \
            --timeout=3 \
            --window-icon="folder"
    fi
}

# Function to show startup notification
show_startup_notification() {
    yad --info \
        --title="Firefox Isolated - Starting" \
        --text="🦊 Starting Firefox in isolated mode...\n\n⚠️  Important Notes:\n• This session will NOT save any data\n• Cookies, history, and downloads are temporary\n• All data will be deleted when Firefox closes\n\nFirefox will launch in a few seconds..." \
        --width=450 \
        --height=180 \
        --center \
        --timeout=4 \
        --window-icon="firefox" &
}

# Function to launch Firefox
launch_firefox() {
    local temp_profile="$1"
    
    print_status "Launching Firefox in isolated mode..."
    print_warning "This Firefox instance will not save any data (cookies, history, downloads, etc.)"
    
    # Show startup notification
    show_startup_notification
    
    # Store original HOME to restore later
    local original_home="$HOME"
    
    # Create a temporary home directory within our work directory to isolate AppImage
    local temp_home="$WORK_DIR/isolated_home"
    mkdir -p "$temp_home"
    
    # Set environment variables to redirect AppImage portable directories
    # This prevents the AppImage from creating .home and .config in the original location
    export HOME="$temp_home"
    export XDG_CONFIG_HOME="$temp_home/.config"
    export XDG_CACHE_HOME="$temp_home/.cache"
    export XDG_DATA_HOME="$temp_home/.local/share"
    
    # Ensure the override directories exist
    mkdir -p "$XDG_CONFIG_HOME" "$XDG_CACHE_HOME" "$XDG_DATA_HOME"
    
    # Launch Firefox with the absolute path to the profile (not affected by HOME change)
    # Using --new-instance for better isolation
    "$APPIMAGE_PATH" --profile "$temp_profile" --new-instance /tmp/start-firefox.html
    
    # Restore original environment
    export HOME="$original_home"
    unset XDG_CONFIG_HOME XDG_CACHE_HOME XDG_DATA_HOME
    
    print_success "Firefox session ended."
}

# Function to show welcome dialog
show_welcome_dialog() {
    yad --info \
        --title="Firefox Isolated Instance" \
        --text="🦊 Welcome to Firefox Isolated Instance!\n\nThis script will:\n• Download Firefox AppImage (if needed)\n• Create a temporary, isolated profile\n• Launch Firefox with no data persistence\n• Clean up when you're done\n\nClick OK to continue..." \
        --width=400 \
        --height=180 \
        --center \
        --window-icon="firefox"
}

# Main execution
main() {
    print_status "Starting Firefox Isolated Instance Script"
    
    # Show welcome dialog
    show_welcome_dialog
    
    # Check dependencies
    check_dependencies
    
    # Create work directory
    mkdir -p "$WORK_DIR"
    
    # Download Firefox AppImage
    download_firefox
    
    # Make it executable
    make_executable
    
    # Create temporary profile
    TEMP_PROFILE=$(create_temp_profile)
    
    # Initialize the profile
    initialize_profile "$TEMP_PROFILE"
    
    # Launch Firefox
    launch_firefox "$TEMP_PROFILE"
    
    # Show cleanup dialog after Firefox closes
    show_cleanup_dialog
}

# Create a simple HTML start page to avoid file:// URLs
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
}

# Help function
show_help() {
    cat << EOF
Firefox Isolated Instance Script (YAD Version)

Usage: $0 [OPTIONS]

OPTIONS:
    -h, --help     Show this help message
    -c, --clean    Remove downloaded AppImage and exit
    -v, --version  Show script version

DESCRIPTION:
    This script downloads and runs Firefox AppImage in a non-persistent,
    isolated mode using /tmp/firefox-isolated directory. Features YAD GUI
    for enhanced user experience with better dialogs and progress indicators.

FEATURES:
    - Downloads Firefox AppImage automatically with enhanced progress dialog
    - Creates temporary profile for each session in /tmp
    - Advanced YAD GUI with better styling and user feedback
    - Welcome and notification dialogs for better user experience
    - Prevents AppImage portable directory creation (.home/.config)
    - Complete environment isolation using custom HOME and XDG variables
    - Enhanced cleanup dialogs with detailed options
    - No interference with system Firefox installation
    - Beautiful HTML start page with session information

REQUIREMENTS:
    - yad (for advanced GUI dialogs)
    - curl or wget (for downloading)

INSTALLATION:
    sudo apt update && sudo apt install yad curl

NEW YAD FEATURES:
    - Better progress dialogs with percentage and status text
    - Enhanced question dialogs with custom buttons
    - Informational popups with auto-timeout
    - Improved error dialogs with detailed messages
    - Window centering and proper sizing
    - Icon support for better visual feedback

EOF
}

# Function to clean up downloaded AppImage
clean_appimage() {
    yad --question \
        --title="Firefox Isolated - Clean AppImage" \
        --text="Are you sure you want to remove all Firefox AppImage files?\n\nThis will delete:\n• Downloaded Firefox AppImage\n• All temporary files\n• Any cached data\n\nYou'll need to download Firefox again next time." \
        --width=450 \
        --height=180 \
        --center \
        --button="Cancel:1" \
        --button="Delete All:0" \
        --window-icon="user-trash"
    
    if [[ $? -eq 0 ]]; then
        if [[ -d "$WORK_DIR" ]]; then
            print_status "Removing all application files..."
            rm -rf "$WORK_DIR"
            print_success "All application files removed"
            
            yad --info \
                --title="Firefox Isolated - Cleanup Complete" \
                --text="✅ All Firefox AppImage files have been successfully deleted!\n\nYour system is now clean.\n\nDisk space freed: $(du -sh "$WORK_DIR" 2>/dev/null | cut -f1 || echo "Unknown")" \
                --width=400 \
                --height=150 \
                --center \
                --timeout=4 \
                --window-icon="user-trash-full"
        else
            print_warning "No application files found to remove"
            yad --info \
                --title="Firefox Isolated - Nothing to Clean" \
                --text="No Firefox AppImage files were found.\n\nYour system is already clean!" \
                --width=350 \
                --height=120 \
                --center \
                --timeout=3 \
                --window-icon="dialog-information"
        fi
        
        # Also clean up any AppImage portable directories that might exist
        if [[ -f "$APPIMAGE_PATH" ]]; then
            local appimage_base="${APPIMAGE_PATH%.*}"
            local portable_home="${appimage_base}.home"
            local portable_config="${appimage_base}.config"
            
            [[ -d "$portable_home" ]] && rm -rf "$portable_home" && print_success "Removed portable home directory"
            [[ -d "$portable_config" ]] && rm -rf "$portable_config" && print_success "Removed portable config directory"
        fi
        
        # Clean up problematic directories
        cleanup_problematic_dirs
    else
        print_status "Cleanup cancelled by user"
        yad --info \
            --title="Firefox Isolated - Cancelled" \
            --text="Cleanup operation was cancelled.\n\nNo files were deleted." \
            --width=300 \
            --height=100 \
            --center \
            --timeout=2 \
            --window-icon="dialog-information"
    fi
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
        yad --info \
            --title="Firefox Isolated - Version" \
            --text="Firefox Isolated Instance Script (YAD Version)\n\nVersion: 2.0\nGUI Library: YAD\nFirefox Version: 141.0\n\nCreated for isolated, temporary browsing sessions." \
            --width=400 \
            --height=150 \
            --center \
            --window-icon="firefox"
        exit 0
        ;;
    "")
        # No arguments, run main function
        main
        ;;
    *)
        print_error "Unknown option: $1"
        yad --error \
            --title="Firefox Isolated - Error" \
            --text="Unknown option: $1\n\nUse --help to see available options." \
            --width=300 \
            --height=120 \
            --center \
            --window-icon="error"
        show_help
        exit 1
        ;;
esac
