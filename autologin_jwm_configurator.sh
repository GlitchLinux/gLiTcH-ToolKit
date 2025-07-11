#!/bin/bash

# JWM Login Configurator for Debian
# Configures JWM as a login option and sets up user environment

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Global variables
RUNNING_AS_ROOT=false
DISPLAY_MANAGER=""

# All print functions defined first
print_status() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

print_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[SUCCESS]${NC} $1"
}

print_header() {
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN} JWM Login Configurator${NC}"
    echo -e "${CYAN}================================${NC}"
}

# Function to run command as specific user
run_as_user() {
    local username="$1"
    local command="$2"
    
    if [[ $RUNNING_AS_ROOT == true ]]; then
        # When running as root, use su to switch to user
        su - "$username" -c "$command"
    else
        # When not root, use sudo -u
        sudo -u "$username" bash -c "$command"
    fi
}

# Function to create file as user
create_user_file() {
    local username="$1"
    local filepath="$2"
    local content="$3"
    
    # Create directory if it doesn't exist
    local dirname=$(dirname "$filepath")
    run_as_user "$username" "mkdir -p '$dirname'"
    
    # Create file with content
    if [[ $RUNNING_AS_ROOT == true ]]; then
        echo "$content" > "$filepath"
        chown "$username:$username" "$filepath"
    else
        echo "$content" | sudo -u "$username" tee "$filepath" > /dev/null
    fi
}

# Function to check if package is installed
check_package() {
    local package="$1"
    if dpkg -l | grep -q "^ii  $package "; then
        return 0
    else
        return 1
    fi
}

# Function to install required packages
install_packages() {
    local packages_to_install=()
    
    print_status "Checking required packages..."
    
    # Check JWM
    if ! check_package "jwm"; then
        packages_to_install+=("jwm")
    fi
    
    # Check for a display manager
    local dm_installed=false
    for dm in lightdm gdm3 sddm xdm; do
        if check_package "$dm"; then
            dm_installed=true
            DISPLAY_MANAGER="$dm"
            break
        fi
    done
    
    if ! $dm_installed; then
        print_status "No display manager found. Installing LightDM (recommended for JWM)..."
        packages_to_install+=("lightdm" "lightdm-gtk-greeter")
        DISPLAY_MANAGER="lightdm"
    fi
    
    # Check for essential X11 packages
    for pkg in xorg xinit x11-xserver-utils; do
        if ! check_package "$pkg"; then
            packages_to_install+=("$pkg")
        fi
    done
    
    # Check for useful tools
    for pkg in feh wmctrl xdotool; do
        if ! check_package "$pkg"; then
            packages_to_install+=("$pkg")
        fi
    done
    
    if [ ${#packages_to_install[@]} -gt 0 ]; then
        print_status "Installing packages: ${packages_to_install[*]}"
        sudo apt update
        sudo apt install -y "${packages_to_install[@]}"
        
        if [ $? -ne 0 ]; then
            print_error "Package installation failed!"
            exit 1
        fi
    else
        print_success "All required packages are already installed!"
    fi
}

# Function to create JWM desktop entry
create_jwm_desktop_entry() {
    print_status "Creating JWM desktop entry for display manager..."
    
    local jwm_desktop="/usr/share/xsessions/jwm.desktop"
    
    sudo tee "$jwm_desktop" > /dev/null << 'EOF'
[Desktop Entry]
Name=JWM
Comment=Joe's Window Manager
Exec=jwm
Icon=
Type=Application
DesktopNames=JWM
Keywords=window;manager;
EOF
    
    if [ $? -eq 0 ]; then
        print_success "JWM desktop entry created at $jwm_desktop"
    else
        print_error "Failed to create JWM desktop entry!"
        exit 1
    fi
}

# Function to create basic JWM config
create_basic_jwm_config() {
    local username="$1"
    local user_home="/home/$username"
    
    print_status "Creating basic JWM configuration..."
    
    local jwm_config='<?xml version="1.0"?>
<JWM>

    <!-- The root menu -->
    <RootMenu onroot="1">
        <Program label="Terminal" icon="terminal">xfce4-terminal</Program>
        <Program label="File Manager" icon="folder">thunar</Program>
        <Program label="Web Browser" icon="web-browser">firefox-esr</Program>
        <Separator/>
        <Program label="Text Editor" icon="text-editor">mousepad</Program>
        <Program label="Calculator" icon="calculator">galculator</Program>
        <Separator/>
        <Menu icon="preferences-desktop" label="Preferences">
            <Program label="Display Settings">xrandr-gui</Program>
            <Program label="Network">nm-connection-editor</Program>
        </Menu>
        <Separator/>
        <Restart label="Restart JWM" icon="system-restart"/>
        <Exit label="Exit" confirm="true" icon="system-log-out"/>
    </RootMenu>

    <!-- Tray at the bottom -->
    <Tray x="0" y="-1" height="40" autohide="off">
        <TrayButton label="Menu" icon="applications-accessories">root:1</TrayButton>
        <TrayButton label="Files" icon="folder">exec:thunar</TrayButton>
        <TrayButton label="Terminal" icon="terminal">exec:xfce4-terminal</TrayButton>
        
        <Spacer width="10"/>
        <TaskList maxwidth="200"/>
        <Dock/>
        
        <Clock format="%H:%M %d/%m"><Button mask="123">exec:xclock</Button></Clock>
        <TrayButton label="Logout" icon="system-log-out">exec:jwm -exit</TrayButton>
    </Tray>

    <!-- Visual Styles -->
    <WindowStyle>
        <Font>Sans-12:bold</Font>
        <Width>2</Width>
        <Height>20</Height>
        <Foreground>#FFFFFF</Foreground>
        <Background>#555555</Background>
        <Active>
            <Foreground>#FFFFFF</Foreground>
            <Background>#0078D4</Background>
        </Active>
    </WindowStyle>

    <TrayStyle>
        <Font>Sans-10</Font>
        <Background>#2D2D30</Background>
        <Foreground>#FFFFFF</Foreground>
    </TrayStyle>

    <TaskListStyle>
        <Font>Sans-10</Font>
        <Foreground>#FFFFFF</Foreground>
        <Background>#2D2D30</Background>
        <Active>
            <Foreground>#000000</Foreground>
            <Background>#0078D4</Background>
        </Active>
    </TaskListStyle>

    <MenuStyle>
        <Font>Sans-10</Font>
        <Foreground>#FFFFFF</Foreground>
        <Background>#2D2D30</Background>
        <Active>
            <Foreground>#FFFFFF</Foreground>
            <Background>#0078D4</Background>
        </Active>
    </MenuStyle>

    <!-- Virtual Desktops -->
    <Desktops width="2" height="1">
        <Background type="solid">#1E1E1E</Background>
    </Desktops>

    <!-- Window behavior -->
    <FocusModel>click</FocusModel>
    <SnapMode distance="5">border</SnapMode>
    <MoveMode coordinates="off">opaque</MoveMode>
    <ResizeMode coordinates="off">opaque</ResizeMode>

    <!-- Startup commands -->
    <StartupCommand>feh --bg-fill /usr/share/pixmaps/debian-logo.png 2>/dev/null || xsetroot -solid "#1E1E1E"</StartupCommand>

    <!-- Key bindings -->
    <Key mask="A" key="Tab">nextstacked</Key>
    <Key mask="A" key="F4">close</Key>
    <Key mask="A" key="F2">exec:dmenu_run</Key>
    <Key mask="4" key="Return">exec:xfce4-terminal</Key>
    <Key mask="4" key="e">exec:thunar</Key>

</JWM>'

    create_user_file "$username" "$user_home/.jwmrc" "$jwm_config"
    print_success "Basic JWM configuration created"
}

# Function to create .xsession file
create_xsession_file() {
    local username="$1"
    local user_home="/home/$username"
    
    print_status "Creating .xsession file for $username..."
    
    local xsession_content='#!/bin/bash

# .xsession file for JWM
# This file is executed when logging in via display manager

# Source user environment
if [ -f ~/.profile ]; then
    . ~/.profile
fi

if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Set up environment
export XDG_CURRENT_DESKTOP=JWM
export XDG_SESSION_DESKTOP=JWM

# Start D-Bus if not already running
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
fi

# Start some essential services
/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 &
nm-applet &
pulseaudio --start &

# Set keyboard layout (change to your preference)
setxkbmap us &

# Start JWM
exec jwm'

    create_user_file "$username" "$user_home/.xsession" "$xsession_content"
    
    # Make executable
    run_as_user "$username" "chmod +x '$user_home/.xsession'"
    print_success ".xsession file created"
}

# Function to create .xinitrc file
create_xinitrc_file() {
    local username="$1"
    local user_home="/home/$username"
    
    print_status "Creating .xinitrc file for $username..."
    
    local xinitrc_content='#!/bin/bash

# .xinitrc file for JWM
# This file is executed when starting X with startx

# Source system xinitrc scripts
if [ -d /etc/X11/xinit/xinitrc.d ] ; then
    for f in /etc/X11/xinit/xinitrc.d/?*.sh ; do
        [ -x "$f" ] && . "$f"
    done
    unset f
fi

# Source user environment
if [ -f ~/.profile ]; then
    . ~/.profile
fi

if [ -f ~/.bashrc ]; then
    . ~/.bashrc
fi

# Set up environment
export XDG_CURRENT_DESKTOP=JWM
export XDG_SESSION_DESKTOP=JWM

# Start D-Bus if not already running
if [ -z "$DBUS_SESSION_BUS_ADDRESS" ]; then
    eval $(dbus-launch --sh-syntax --exit-with-session)
fi

# Start some essential services
/usr/lib/policykit-1-gnome/polkit-gnome-authentication-agent-1 &
nm-applet &
pulseaudio --start &

# Set keyboard layout (change to your preference)
setxkbmap us &

# Start JWM
exec jwm'

    create_user_file "$username" "$user_home/.xinitrc" "$xinitrc_content"
    
    # Make executable
    run_as_user "$username" "chmod +x '$user_home/.xinitrc'"
    print_success ".xinitrc file created"
}

# Function to setup user JWM configuration
setup_user_jwm_config() {
    local username="$1"
    local user_home="/home/$username"
    
    print_status "Setting up JWM configuration for user: $username"
    
    # Check if user exists
    if ! id "$username" &>/dev/null; then
        print_error "User '$username' does not exist!"
        return 1
    fi
    
    # Create JWM config directory
    run_as_user "$username" "mkdir -p '$user_home/.config/jwm'"
    
    # Copy system JWM config to user directory if it doesn't exist
    if [ ! -f "$user_home/.jwmrc" ]; then
        if [ -f "/etc/jwm/system.jwmrc" ]; then
            run_as_user "$username" "cp '/etc/jwm/system.jwmrc' '$user_home/.jwmrc'"
            print_status "Copied system JWM config to user directory"
        elif [ -f "/usr/share/jwm/jwmrc" ]; then
            run_as_user "$username" "cp '/usr/share/jwm/jwmrc' '$user_home/.jwmrc'"
            print_status "Copied default JWM config to user directory"
        else
            # Create a basic JWM config
            create_basic_jwm_config "$username"
        fi
    else
        print_warning "User already has .jwmrc file, skipping..."
    fi
    
    # Create .xsession file for manual X start
    create_xsession_file "$username"
    
    # Create .xinitrc file for xinit
    create_xinitrc_file "$username"
    
    # Set proper ownership
    if [[ $RUNNING_AS_ROOT == true ]]; then
        chown -R "$username:$username" "$user_home/.jwmrc" "$user_home/.xsession" "$user_home/.xinitrc" "$user_home/.config" 2>/dev/null
    fi
    
    print_success "JWM configuration setup complete for user: $username"
}

# Function to configure display manager
configure_display_manager() {
    print_status "Configuring display manager: $DISPLAY_MANAGER"
    
    case "$DISPLAY_MANAGER" in
        "lightdm")
            # Enable LightDM service
            sudo systemctl enable lightdm.service
            
            # Configure LightDM to show JWM option
            if [ -f /etc/lightdm/lightdm.conf ]; then
                # Backup original config
                sudo cp /etc/lightdm/lightdm.conf /etc/lightdm/lightdm.conf.backup
                
                # Ensure sessions directory is configured
                if ! grep -q "^sessions-directory=" /etc/lightdm/lightdm.conf; then
                    echo "sessions-directory=/usr/share/xsessions" | sudo tee -a /etc/lightdm/lightdm.conf > /dev/null
                fi
            fi
            print_success "LightDM configured for JWM"
            ;;
        "gdm3")
            sudo systemctl enable gdm3.service
            print_success "GDM3 will automatically detect JWM session"
            ;;
        "sddm")
            sudo systemctl enable sddm.service
            print_success "SDDM will automatically detect JWM session"
            ;;
        "xdm")
            sudo systemctl enable xdm.service
            print_warning "XDM configuration may require manual setup"
            ;;
    esac
}

# Function to test JWM configuration
test_jwm_config() {
    local username="$1"
    local user_home="/home/$username"
    
    print_status "Testing JWM configuration..."
    
    # Test JWM config syntax
    if run_as_user "$username" "jwm -p -f '$user_home/.jwmrc'" >/dev/null 2>&1; then
        print_success "JWM configuration syntax is valid"
    else
        print_error "JWM configuration has syntax errors!"
        print_status "Running syntax check..."
        run_as_user "$username" "jwm -p -f '$user_home/.jwmrc'"
        return 1
    fi
    
    return 0
}

# Function to show final instructions
show_final_instructions() {
    local username="$1"
    
    echo ""
    echo -e "${CYAN}================================${NC}"
    echo -e "${CYAN} Setup Complete!${NC}"
    echo -e "${CYAN}================================${NC}"
    echo ""
    echo -e "${GREEN}JWM has been configured for user: ${BLUE}$username${NC}"
    echo ""
    echo -e "${YELLOW}Next steps:${NC}"
    echo "1. Log out of your current session"
    echo "2. At the login screen, select 'JWM' from the session menu"
    echo "3. Log in with your credentials"
    echo ""
    echo -e "${YELLOW}Alternative manual start methods:${NC}"
    echo "• From TTY: ${BLUE}startx${NC}"
    echo "• From TTY with specific session: ${BLUE}startx ~/.xinitrc${NC}"
    echo ""
    echo -e "${YELLOW}Configuration files created:${NC}"
    echo "• ~/.jwmrc - JWM configuration"
    echo "• ~/.xsession - Display manager session"
    echo "• ~/.xinitrc - Manual X session"
    echo ""
    echo -e "${YELLOW}To customize JWM:${NC}"
    echo "• Edit: ${BLUE}~/.jwmrc${NC}"
    echo "• Test config: ${BLUE}jwm -p${NC}"
    echo "• Restart JWM: ${BLUE}jwm -restart${NC}"
    echo ""
    echo -e "${GREEN}Enjoy your JWM setup!${NC}"
}

# Initialize global variables
initialize_globals() {
    # Check if running as root or with sudo
    if [[ $EUID -eq 0 ]]; then
        print_warning "Running as root. Will handle user permissions carefully."
        RUNNING_AS_ROOT=true
    else
        print_status "Running as regular user with sudo privileges."
        RUNNING_AS_ROOT=false
    fi
}

# Main script execution
main() {
    clear
    print_header
    echo ""
    
    # Initialize global variables
    initialize_globals
    
    # Check if we have appropriate privileges
    if [[ $RUNNING_AS_ROOT == false ]]; then
        if ! sudo -n true 2>/dev/null; then
            echo "This script requires sudo privileges."
            echo "Please enter your password when prompted."
            sudo -v
            if [ $? -ne 0 ]; then
                print_error "Failed to obtain sudo privileges!"
                exit 1
            fi
        fi
    fi
    
    # Get username from user
    echo -n "Enter the username to configure JWM for: "
    read -r target_user
    
    if [ -z "$target_user" ]; then
        print_error "Username cannot be empty!"
        exit 1
    fi
    
    # Confirm user choice
    echo ""
    echo -e "You are about to configure JWM login for user: ${BLUE}$target_user${NC}"
    echo -n "Continue? (y/N): "
    read -r confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo "Configuration cancelled."
        exit 0
    fi
    
    echo ""
    print_status "Starting JWM login configuration..."
    
    # Execute configuration steps
    install_packages
    create_jwm_desktop_entry
    setup_user_jwm_config "$target_user"
    configure_display_manager
    
    # Test configuration
    if test_jwm_config "$target_user"; then
        show_final_instructions "$target_user"
    else
        print_error "Configuration completed with errors. Please check the JWM config file."
        exit 1
    fi
}

# Run main function
main "$@"
