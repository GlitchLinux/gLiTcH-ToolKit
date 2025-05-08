#!/bin/bash

# --- Configuration ---
BACKUP_USER_HOMES=false # Set to true to back up user home directories. Set to false to skip.
BACKUP_DIR="/opt/user_backups_$(date +%Y%m%d_%H%M%S)"
SKIP_USER_REMOVAL=false # Set to true to skip removing non-root users
COMPRESS_INITRAMFS=true # Set to true to compress initramfs (saves a little space)
REMOVE_IPV6_XTABLES=false # EXTREMELY CAREFUL! Set to true only if you are ABSOLUTELY sure.

# Packages to explicitly KEEP (add any others you need)
PACKAGES_TO_KEEP=(
    "bash"
    "coreutils"
    "debian-archive-keyring"
    "gpgv"
    "init"
    "systemd"
    "systemd-sysv"
    "sysvinit-utils"
    "mount"
    "util-linux"
    "passwd"
    "dpkg"
    "apt"
    "libc6" # Essential C library
    # libgcc-s1 is usually a dependency of libc6 or other essential packages, apt handles it.
    "login"
    "grep"
    "sed"
    "awk"
    "tar"
    "gzip"
    "bzip2"
    "xz-utils"
    "nano" # User requested
    "git" # User requested
    "wget" # User requested
    "openssh-server" # User requested - CRITICAL for headless
    "grub-pc" # Or grub-efi-amd64 depending on your boot. grub-common will be a dep.
    "grub-common"
    "cryptsetup" # User requested
    "cryptsetup-initramfs" # For unlocking encrypted root during boot
    "iproute2" # Modern networking tools (ip command)
    "isc-dhcp-client" # Or other DHCP client like dhcpcd5 if used
    "ca-certificates" # For HTTPS
    "ssh" # SSH client often useful even on servers
    "man-db" # If you want man pages
    "less" # For viewing files
    "procps" # For ps, top etc.
    "netbase" # For /etc/services, /etc/protocols
    "kmod" # For kernel module management
    "udev" # For device management
    # Add your kernel package(s) here if you want to be super explicit, though apt should protect it
    # e.g. "linux-image-amd64" or the specific version like "linux-image-6.1.0-18-amd64"
)

# --- Script Initialization ---
export DEBIAN_FRONTEND=noninteractive # Suppress interactive prompts from apt
SECONDS=0 # Start timer

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Window resize (mostly for interactive feel, less relevant for true headless prep)
printf '\033[8;40;120t'

echo -e "${BLUE}-------------------------===== Start of Ultimate Debian Debloater ====-------------------------${NC}"
echo -e "${YELLOW}Current Time: $(date +"%Y-%m-%d_%A_%H:%M:%S")${NC}"
echo -e "${YELLOW}Running as: $(whoami)${NC}"
echo -e "${YELLOW}Script PID: $$${NC}"
echo

# --- WARNING AND CONFIRMATION ---
echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! WARNING !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
echo -e "${RED}This script will attempt to remove a significant number of packages,${NC}"
echo -e "${RED}including the XFCE desktop environment, all GUI applications, display managers,${NC}"
echo -e "${RED}and potentially non-root user accounts and their data.${NC}"
echo -e "${RED}This is intended to create a MINIMAL HEADLESS system.${NC}"
echo -e "${RED}Ensure you have SSH access configured and working if this is a remote machine.${NC}"
echo -e "${RED}ALL XFCE, GUI applications, browsers, office suites, games will be PURGED.${NC}"
echo -e "${YELLOW}It is STRONGLY recommended to run this in a VM or test environment first.${NC}"
echo -e "${YELLOW}MAKE SURE YOU HAVE BACKUPS OF ALL IMPORTANT DATA.${NC}"
echo -e "${RED}!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!${NC}"
echo
echo -e "${YELLOW}Packages explicitly marked to KEEP:${NC}"
for pkg_keep in "${PACKAGES_TO_KEEP[@]}"; do
    echo -e "${GREEN}  - $pkg_keep${NC}"
done
echo
echo -e "${YELLOW}User home directory backup: ${GREEN}${BACKUP_USER_HOMES}${NC}"
if [ "$BACKUP_USER_HOMES" = true ]; then
    echo -e "${YELLOW}Backup location: ${GREEN}${BACKUP_DIR}${NC}"
fi

if [ "$SKIP_USER_REMOVAL" = false ]; then
    echo -e "${YELLOW}Non-root user removal: ${GREEN}ENABLED${NC}"
else
    echo -e "${YELLOW}Non-root user removal: ${RED}DISABLED${NC}"
fi
echo

read -r -p "$(echo -e ${YELLOW}"Type 'YESIDOACCEPT' to proceed, or anything else to abort: "${NC})" CONFIRMATION

if [ "$CONFIRMATION" != "YESIDOACCEPT" ]; then
    echo -e "${RED}Aborted by user.${NC}"
    exit 1
fi

echo -e "${GREEN}Proceeding with debloating process... You have been warned!${NC}"
sleep 3

# --- Helper Functions ---
log_section() {
    echo
    echo -e "${BLUE}-------------------------===== $1 =====-------------------------${NC}"
    echo
}

log_action() {
    echo -e "${GREEN}>>> $1${NC}"
}

log_warning() {
    echo -e "${YELLOW}!!! $1${NC}"
}

log_error() {
    echo -e "${RED}!!! ERROR: $1${NC}"
}

# --- Check if running as root ---
if [ "$(id -u)" -ne 0 ]; then
    log_error "This script must be run as root. Use 'sudo ./debloater.sh'."
    exit 1
fi

# --- User Removal ---
if [ "$SKIP_USER_REMOVAL" = false ]; then
    log_section "User Account Removal"
    log_action "Identifying non-root, non-system users (UID >= 1000)..."
    
    SUDO_USER_REAL=""
    if [ -n "$SUDO_USER" ]; then
        SUDO_USER_REAL=$(getent passwd "$SUDO_USER" | awk -F: '{print $1}')
    fi

    mapfile -t USERS_TO_PROCESS < <(getent passwd | awk -F: -v sudo_user="$SUDO_USER_REAL" '
        $3 >= 1000 && $1 != "root" && $1 != sudo_user {print $1}')

    if [ ${#USERS_TO_PROCESS[@]} -eq 0 ]; then
        log_action "No non-root users (UID >= 1000) found to remove (excluding current sudo user if any)."
    else
        log_action "Found users to potentially remove:"
        for user in "${USERS_TO_PROCESS[@]}"; do
            echo "  - $user (Home: $(getent passwd "$user" | cut -d: -f6))"
        done
        echo

        if [ "$BACKUP_USER_HOMES" = true ]; then
            log_action "Backing up home directories to $BACKUP_DIR..."
            mkdir -p "$BACKUP_DIR"
            if [ $? -ne 0 ]; then
                log_error "Could not create backup directory $BACKUP_DIR. User home directories may not be backed up."
            else
                for user in "${USERS_TO_PROCESS[@]}"; do
                    USER_HOME=$(getent passwd "$user" | cut -d: -f6)
                    if [ -d "$USER_HOME" ]; then
                        log_action "Backing up $USER_HOME for user $user..."
                        if tar czf "$BACKUP_DIR/${user}_home_backup.tar.gz" -C "$(dirname "$USER_HOME")" "$(basename "$USER_HOME")"; then
                            log_action "Backup for $user successful."
                        else
                            log_warning "Backup for $user FAILED. Home directory for $user may not be removed safely."
                        fi
                    else
                        log_warning "Home directory $USER_HOME for user $user not found. Skipping backup."
                    fi
                done
            fi
        fi

        log_action "Proceeding with user removal..."
        for user in "${USERS_TO_PROCESS[@]}";
        do
            log_action "Attempting to remove user $user..."
            if pgrep -u "$user" > /dev/null; then
                log_warning "User $user has running processes. Attempting to kill them."
                killall -KILL -u "$user"
                sleep 2 
                if pgrep -u "$user" > /dev/null; then
                     log_warning "Could not kill all processes for $user. Manual intervention might be needed. User removal might fail or be incomplete."
                fi
            fi
            
            USER_HOME_DIR=$(getent passwd "$user" | cut -d: -f6)
            SHOULD_REMOVE_HOME=false
            # Determine if home directory should be removed
            if [ -n "$USER_HOME_DIR" ] && [ -d "$USER_HOME_DIR" ]; then # Home exists
                if [ "$BACKUP_USER_HOMES" = true ] && [ -f "$BACKUP_DIR/${user}_home_backup.tar.gz" ]; then
                    # Backup was requested and successful
                    SHOULD_REMOVE_HOME=true
                elif [ "$BACKUP_USER_HOMES" = false ]; then
                    # Backup not requested, but home exists. For aggressive debloat, we can choose to remove it.
                    # Or, to be safer, prompt or default to not remove.
                    # Current script's goal is aggressive. Let's make it an option or remove if no backup.
                    log_warning "User $user home directory $USER_HOME_DIR exists, and backups were NOT enabled. Removing home as part of debloat."
                    SHOULD_REMOVE_HOME=true # Aggressive removal
                else
                    # Backup was requested but failed, or other conditions
                    log_warning "User $user home directory $USER_HOME_DIR will NOT be removed (backup might have failed or other reason)."
                    SHOULD_REMOVE_HOME=false
                fi
            fi # else: no home dir or not a directory, so no explicit removal needed with deluser

            if $SHOULD_REMOVE_HOME ; then
                 log_action "Removing user $user and their group (and home directory $USER_HOME_DIR)."
                 if ! deluser --remove-home "$user"; then 
                     log_error "Failed to remove user $user with --remove-home. Trying without --remove-home."
                     if ! deluser "$user"; then
                        log_error "Failed to remove user $user even without --remove-home."
                     fi
                 else
                    log_action "User $user and home directory removed."
                 fi
            else
                 log_action "Removing user $user WITHOUT removing home directory (home: $USER_HOME_DIR)."
                 if ! deluser "$user"; then
                    log_error "Failed to remove user $user."
                 else
                    log_action "User $user removed (without home dir)."
                 fi
            fi
        done
    fi
else
    log_action "Skipping non-root user removal as per configuration."
fi


# --- Stop Display Manager and Desktop Services ---
log_section "Stopping GUI Services"
log_action "Attempting to stop display manager and related services..."
SYSTEMD_SERVICES_TO_STOP=(
    "lightdm"
    "gdm3"
    "sddm"
    "lxdm"
    "xfce4-session" 
)
for service in "${SYSTEMD_SERVICES_TO_STOP[@]}"; do
    if systemctl is-active --quiet "$service"; then
        log_action "Stopping $service..."
        systemctl stop "$service" || log_warning "Failed to stop $service (it might not be running or exist)."
    else
        log_action "Service $service is not active. Skipping stop."
    fi
done
log_action "Attempting to kill any remaining X server processes..."
pkill -9 Xorg || true 
pkill -9 Xwayland || true


# --- Package Removal ---
log_section "Package Removal"

PACKAGES_TO_PURGE=(
    # --- XFCE Desktop Environment & Core Components ---
    "xfce4*"
    "xfwm4*"
    "thunar*"
    "xfdesktop4*"
    "xfce4-panel*"
    "xfce4-session*"
    "xfce4-settings*"
    "xfce4-terminal*" 
    "mousepad"
    "ristretto"
    "parole"
    "xfburn"
    "xfce4-appfinder"
    "xfce4-notifyd"
    "xfce4-power-manager*"
    "xfce4-pulseaudio-plugin" 
    "xfce4-screenshooter"
    "xfce4-taskmanager"
    "libxfce4util*"
    "libxfce4ui*"
    "libxfconf*"
    "tumbler*" 

    # --- Display Managers & Greeters ---
    "lightdm*"
    "gdm3*"
    "sddm*"
    "lxdm*"
    "slick-greeter*"
    "gtk-greeter" 

    # --- X.Org Server and common X11 Libraries (BE VERY CAREFUL HERE) ---
    "xserver-xorg-core"
    "xserver-xorg"
    "xorg"
    "xserver-xorg-input-*"
    "xserver-xorg-video-*"
    "xwayland"
    "x11-common"
    "x11-utils"
    "x11-xserver-utils"
    "xauth"
    "xinit"
    "libx11-*"
    "libgtk-*" # GTK libraries (many versions like libgtk2.0-*, libgtk-3-*, libgtk-4-*)
    "libgdk-*"
    "libcairo*" 
    "libpango-*" 
    "libatk-*"   
    "libglib2.0-*" # Core library for GTK and GNOME (libglib2.0-bin, libglib2.0-data etc.)
    
    # --- GNOME specific libraries (often pulled in by XFCE or other apps) ---
    "libgnome-*"
    "libgnomeui-*"
    "libbonobo*"
    "libbonoboui*"
    
    # --- Sound & Multimedia ---
    "pulseaudio*"
    "pipewire*" 
    "alsa-utils" 
    "libcanberra*" 
    "brasero*"
    "cheese*"
    "gnome-sound-recorder"
    "sound-juicer"
    "totem*"
    "rhythmbox*"
    "vlc*"
    "smplayer*"
    "lxmusic*"
    "audacious*"
    "pavucontrol" 

    # --- Browsers ---
    "firefox*"
    "firefox-esr*" 
    "chromium*"
    "google-chrome-stable" 
    "epiphany-browser*"
    "konqueror*"
    "w3m" # Terminal browser, removing for "ultimate". Can be kept if desired.

    # --- Office Suites ---
    "libreoffice*" # libreoffice-core, libreoffice-common, etc.
    "libobasis*" 
    "calligra*"
    "gnumeric*"
    "abiword*"
    "evince*" 
    "okular*"
    "atril*" 

    # --- Games ---
    "aisleriot"
    "five-or-more"
    "four-in-a-row"
    "gnome-2048"
    "gnome-chess"
    "gnome-klotski"
    "gnome-mahjongg"
    "gnome-mines"
    "gnome-nibbles"
    "gnome-robots"
    "gnome-sudoku"
    "gnome-taquin"
    "gnome-tetravex"
    "hitori"
    "iagno"
    "lightsoff"
    "quadrapassel"
    "swell-foop"
    "tali"
    "gnome-games" 
    "*game*" # Risky wildcard, but for "ultimate". Review carefully.

    # --- Graphics & Image Editors/Viewers ---
    "gimp*"
    "inkscape*"
    "eog" 
    "shotwell*" 
    "simple-scan*"
    "xsane*"
    "kolourpaint*"
    "krita*"

    # --- Internet & Communication (excluding ssh/wget which are kept) ---
    "deluge*"
    "hexchat*"
    "pidgin*"
    "remmina*"
    "thunderbird*"
    "evolution*"
    "transmission-gtk*"
    "transmission-common" 
    "filezilla*"
    "exim4*" # <<< Added to fix boot issue
    "mutt" # Text-based email client (can be kept if desired)

    # --- Editors (keeping nano as per request) ---
    "vim*" # <<< Added as nano is preferred

    # --- Input Method Editors (IME) & Language specific ---
    "anthy*"
    "kasumi*"
    "im-config"
    "mozc-*"
    "uim*"
    "fcitx*"
    "ibus*"
    "scim*"
    "debian-reference-common"
    "debian-reference-es"
    "debian-reference-it"
    "yelp*" 
    "yelp-xsl"

    # --- Other Accessories & Utilities often part of desktop installs ---
    "deja-dup*" 
    "gnote*"
    "goldendict*"
    "baobab" 
    "gnome-disk-utility"
    "gnome-system-monitor"
    "gnome-calculator"
    "file-roller" 
    "seahorse" 
    "lxtask"
    "tasksel" 
    "reportbug"
    "popularity-contest" 

    # --- "Non-critical" packages from user's list (reviewing and selecting) ---
    "acpi" 
    "acpid" 
    "at" # Job scheduler, cron is usually preferred or systemd timers
    "aspell*" 
    "avahi-daemon*" 
    "bash-completion" # Can be large, optional for minimal
    "bc" # CLI calculator
    "debian-faq*" 
    "doc-debian"
    "doc-linux-text"
    "eject"
    "fdutils" # Floppy disk utils
    "finger"
    "gettext-base" # Internationalization utilities
    "groff" # Typesetting
    "gnupg" # GNU Privacy Guard - often useful, but if space is ultra-critical and not used
    "laptop-detect"
    "libgpmg1" # General Purpose Mouse interface - for console mouse
    "manpages*" # Manual pages (can be removed if space is tight, but often useful - keeping man-db)
    "mtools" # Utilities for MS-DOS disks
    "mtr-tiny" # Traceroute tool
    "ncurses-term" # Additional terminal definitions
    "ppp*" # Point-to-Point Protocol (dial-up, some VPNs)
    "pppoe*"
    "read-edid" # Monitor information
    "unzip"
    "usbutils" # lsusb etc. (can be useful for debugging)
    "wamerican" # Word lists & other languages
    "wbrazilian"
    "witalian"
    "wfrench"
    "wspanish"
    "wswedish"
    "wcatalan"
    "wbulgarian"
    "wdanish"
    "wngerman"
    "wpolish"
    "wportuguese"
    "whois"
    "zeroinstall-injector"
    "zip"
    "plymouth" # Boot splash screen
    "plymouth-themes"
    "gnome-desktop3-data"
    "gnome-firmware"
    "gnome-icon-theme*" 
    "xdg-desktop-portal*"
    "xdg-user-dirs*" 
    "xdg-utils" # Utilities for desktop integration
    "firebird*" # Database, if not explicitly used
    "libfbclient2*"
    "libib-util*"
    "espeak*" # Speech synthesizer
    "speech-dispatcher*"
    "gnome-logs"
    "gnome-software" # Software center
    "malcontent" # Parental controls
    "mlterm*" # Terminal emulator
    "xiterm+thai"
    "xterm" # Basic X terminal
)

PACKAGES_TO_ACTUALLY_PURGE=()
for pkg_candidate_raw in "${PACKAGES_TO_PURGE[@]}"; do
    pkg_candidate_base="${pkg_candidate_raw//\*}" 
    pkg_candidate_for_dpkg_check="$pkg_candidate_raw"

    is_essential_or_kept=false
    for kept_pkg in "${PACKAGES_TO_KEEP[@]}"; do
        # If the candidate (or its base) is an exact match for a kept package
        if [[ "$pkg_candidate_base" == "$kept_pkg" ]] || [[ "$pkg_candidate_raw" == "$kept_pkg" ]]; then
            # Additional check: if kept_pkg is nano, and candidate is nano*, don't expand nano* to purge nano.
            # This logic is tricky with wildcards. The primary goal is to protect exact matches in PACKAGES_TO_KEEP.
            if [[ "$pkg_candidate_raw" == "$kept_pkg"* && "$pkg_candidate_raw" != "$kept_pkg" ]]; then
                # e.g. kept_pkg="nano", candidate="nano*", allow "nano*" to proceed if other nano packages exist
                # but if candidate is exactly "nano", it's skipped.
                : # Let it pass for further checks if it's a wildcard expanding beyond the kept package
            else
                is_essential_or_kept=true
                log_warning "Skipping '$pkg_candidate_raw' from purge: explicitly in PACKAGES_TO_KEEP."
                break
            fi
        fi
    done

    if $is_essential_or_kept; then
        continue
    fi
    
    check_pkg_for_essential="$pkg_candidate_base"
    if [[ "$pkg_candidate_raw" != *"*"* ]]; then 
        check_pkg_for_essential="$pkg_candidate_raw"
    fi
    
    status_output=$(dpkg-query -W -f='${Package}\t${Essential}\t${Priority}\n' "$check_pkg_for_essential" 2>/dev/null | head -n 1)
    if echo "$status_output" | grep -q -E "\s(yes|required)$"; then 
        if [[ "$pkg_candidate_raw" != *"*"* ]]; then 
            log_warning "Skipping '$pkg_candidate_raw' from purge: marked essential/required by dpkg."
            continue
        # else: it's a wildcard, let apt decide if sub-packages are truly essential and unremovable.
        fi
    fi
    
    if dpkg-query -W -f='${Status}' "${pkg_candidate_for_dpkg_check}" 2>/dev/null | grep -q "ok installed"; then
        PACKAGES_TO_ACTUALLY_PURGE+=("$pkg_candidate_raw")
    else
        log_action "Pattern '$pkg_candidate_raw' does not match any installed packages or is already removed. Skipping."
    fi
done


if [ ${#PACKAGES_TO_ACTUALLY_PURGE[@]} -gt 0 ]; then
    log_action "The following packages/patterns and their configurations will be attempted for PURGE:"
    for pkg in "${PACKAGES_TO_ACTUALLY_PURGE[@]}"; do
        echo "  - $pkg"
    done
    echo
    read -r -p "$(echo -e ${YELLOW}"Confirm purging these packages/patterns? (yes/NO): "${NC})" CONFIRM_PURGE
    if [[ "$CONFIRM_PURGE" =~ ^([yY][eE][sS])$ ]]; then
        log_action "Purging packages..."
        # It's often better to pass all packages to a single apt-get call if possible,
        # but wildcards can behave differently. Looping ensures each pattern is processed.
        for pkg_to_purge in "${PACKAGES_TO_ACTUALLY_PURGE[@]}"; do
            log_action "Attempting to purge: $pkg_to_purge"
            # Using "|| true" to prevent script exit if a single purge fails (apt might have already removed it as a dependency)
            apt-get purge -y "$pkg_to_purge" || log_warning "Purge command for '$pkg_to_purge' had a non-zero exit. This might be okay if already removed."
        done
        log_action "Finished initial purge attempt. Running autoremove again."
        apt-get autoremove --purge -y # Run autoremove again after manual purges
    else
        log_warning "Package purge aborted by user."
    fi
else
    log_action "No packages identified for purging after filtering, or all matched patterns are not installed."
fi

# --- System Cleanup ---
log_section "System Cleanup"

log_action "Removing orphaned dependencies (final pass)..."
apt-get autoremove --purge -y
if [ $? -ne 0 ]; then log_warning "Autoremove encountered issues. This is sometimes normal if packages were already removed."; fi

log_action "Cleaning up apt cache..."
apt-get clean -y
if [ $? -ne 0 ]; then log_warning "Apt clean encountered issues."; fi

log_action "Removing residual configuration files (apt purge should handle most)..."
if [ -d "/etc/libreoffice" ]; then # Example, apt purge should get this
    log_action "Removing /etc/libreoffice..."
    rm -rf /etc/libreoffice
fi
if [ -d "/etc/exim4" ]; then # Ensure exim4 configs are gone if purge missed anything
    log_action "Removing /etc/exim4..."
    rm -rf /etc/exim4
fi


log_action "Removing temporary files..."
rm -rf /tmp/*
rm -rf /var/tmp/*


# --- Initramfs Reduction (Optional) ---
if [ "$COMPRESS_INITRAMFS" = true ]; then
    log_section "Initramfs Reduction"
    log_action "Setting initramfs compression to xz..."
    echo "COMPRESS=xz" > /etc/initramfs-tools/conf.d/compress.conf

    log_action "Setting MODULES=dep in initramfs.conf..."
    if [ -f /etc/initramfs-tools/initramfs.conf ]; then
        if grep -q "MODULES=most" /etc/initramfs-tools/initramfs.conf; then
            sed -i 's/MODULES=most/MODULES=dep/g' /etc/initramfs-tools/initramfs.conf
            log_action "Changed MODULES=most to MODULES=dep."
        elif ! grep -q "MODULES=dep" /etc/initramfs-tools/initramfs.conf; then
            # If MODULES is not 'most' and not 'dep', it might be 'netboot' or custom.
            # Only change if it's 'most'.
            log_action "MODULES setting not 'most', not changing to 'dep'. Current config preserved."
        else
             log_action "MODULES=dep already set or 'most' not found."
        fi
    else
        log_warning "/etc/initramfs-tools/initramfs.conf not found. Skipping MODULES=dep."
    fi

    log_action "Updating initramfs (this may take a moment)..."
    if update-initramfs -u -k all; then
        log_action "Initramfs updated successfully."
    else
        log_error "Failed to update initramfs. The system might not boot correctly if kernel modules were removed without this."
    fi
fi

# --- Remove unnecessary IPv6 xtables files (EXTREME CAUTION) ---
if [ "$REMOVE_IPV6_XTABLES" = true ]; then
    log_section "IPv6 xtables Removal (Optional - CAUTION)"
    log_warning "This step removes IPv6 netfilter/iptables library files."
    log_warning "DO NOT DO THIS if you use IPv6 or plan to use it."
    read -r -p "$(echo -e ${RED}"Confirm removing IPv6 xtables files? (yes/NO): "${NC})" CONFIRM_IPV6_REMOVE
    if [[ "$CONFIRM_IPV6_REMOVE" =~ ^([yY][eE][sS])$ ]]; then
        # Common paths for xtables. Adjust if your system uses different locations.
        XTABLES_BASE_PATHS=("/usr/lib/x86_64-linux-gnu/xtables" "/usr/lib/xtables" "/lib/xtables")
        IPV6_XTABLES_LIBS=(
            "libip6t_ah.so" "libip6t_dst.so" "libip6t_eui64.so" "libip6t_frag.so"
            "libip6t_hbh.so" "libip6t_hl.so" "libip6t_HL.so" "libip6t_icmp6.so"
            "libip6t_ipv6header.so" "libip6t_LOG.so" "libip6t_mh.so" "libip6t_REJECT.so"
            "libip6t_rt.so" "libip6t_DNAT.so" "libip6t_DNPT.so" "libip6t_MASQUERADE.so"
            "libip6t_NETMAP.so" "libip6t_REDIRECT.so" "libip6t_SNAT.so" "libip6t_SNPT.so"
        )
        REMOVED_COUNT=0
        log_action "Removing specified IPv6 xtables files..."
        for base_path in "${XTABLES_BASE_PATHS[@]}"; do
            if [ -d "$base_path" ]; then
                for lib_name in "${IPV6_XTABLES_LIBS[@]}"; do
                    xt_file="$base_path/$lib_name"
                    if [ -f "$xt_file" ]; then
                        if rm -f "$xt_file"; then
                            echo "Removed $xt_file"
                            ((REMOVED_COUNT++))
                        else
                            log_warning "Could not remove $xt_file (permission issue?)"
                        fi
                    fi
                done
            fi
        done
        log_action "Removed $REMOVED_COUNT IPv6 xtables files."
        if [ "$REMOVED_COUNT" -eq 0 ]; then
            log_warning "No IPv6 xtables files were found/removed. Check paths if expected."
        fi
    else
        log_action "Skipping IPv6 xtables file removal."
    fi
fi

# --- Final Messages ---
log_section "Debloating Process Finished"
echo -e "${GREEN}The debloating script has completed its operations.${NC}"
echo -e "${YELLOW}Please review any error messages or warnings above.${NC}"
echo -e "${YELLOW}It is STRONGLY recommended to REBOOT the system now.${NC}"
echo -e "${RED}Ensure you can access the system via SSH or console after reboot!${NC}"

duration=$SECONDS
echo -e "${GREEN}Total script execution time: $(($duration / 60)) minutes and $(($duration % 60)) seconds.${NC}"

read -r -p "$(echo -e ${YELLOW}"Reboot now? (yes/NO): "${NC})" REBOOT_CONFIRM
if [[ "$REBOOT_CONFIRM" =~ ^([yY][eE][sS])$ ]]; then
    log_action "Rebooting system in 5 seconds..."
    sleep 5
    reboot
else
    log_action "Please reboot the system manually when ready."
fi

exit 0
