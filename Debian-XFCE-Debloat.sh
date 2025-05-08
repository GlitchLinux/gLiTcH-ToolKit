#!/bin/bash

# --- Configuration ---
BACKUP_USER_HOMES=false # Set to true to back up user home directories. Set to false to skip.
BACKUP_DIR="/opt/user_backups_$(date +%Y%m%d_%H%M%S)"
SKIP_USER_REMOVAL=false # Set to true to skip removing non-root users
COMPRESS_INITRAMFS=true # Set to true to compress initramfs (saves a little space)
REMOVE_IPV6_XTABLES=false # EXTREMELY CAREFUL! Set to true only if you are ABSOLUTELY sure.

# Packages to explicitly KEEP (add any others you need)
# openssh-server is critical for headless access
# cryptsetup is needed if you use encrypted volumes
# Essential networking tools like iproute2 (provides `ip`) or net-tools (provides `ifconfig`) should be kept.
# systemd and essential boot components will be protected by apt's essential/required tags.
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
    "libc6"
    "libgcc-s1" # Or similar depending on arch
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
    "grub-pc" # Or grub-efi-amd64 depending on your boot
    "grub-common"
    "cryptsetup" # User requested
    "cryptsetup-initramfs"
    "iproute2" # Modern networking tools
    "isc-dhcp-client" # Or other DHCP client if needed
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
echo -e "${YELLOW}Remove non-root users: ${GREEN}!${SKIP_USER_REMOVAL}${NC}" # Note: This output might be confusing, better to show the actual effect.
echo

# Corrected user removal display logic
if [ "$SKIP_USER_REMOVAL" = false ]; then
    echo -e "${YELLOW}Non-root user removal: ${GREEN}ENABLED${NC}"
else
    echo -e "${YELLOW}Non-root user removal: ${RED}DISABLED${NC}"
fi


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
                # Decide if you want to exit or continue without backups
                # For now, we'll log error and continue, user was warned about backups.
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
        for user in "${USERS_TO_PROCESS[@]}"; do
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
            if [ "$BACKUP_USER_HOMES" = true ] && [ -f "$BACKUP_DIR/${user}_home_backup.tar.gz" ]; then
                # Backup exists and was requested
                SHOULD_REMOVE_HOME=true
            elif [ "$BACKUP_USER_HOMES" = false ] && [ -n "$USER_HOME_DIR" ] && [ -d "$USER_HOME_DIR" ]; then
                # No backup requested, but home exists - ask user for this specific case if desired, or default to not removing
                log_warning "User $user home directory $USER_HOME_DIR exists, and backups were not enabled. Home will NOT be removed by default."
            elif [ -z "$USER_HOME_DIR" ] || [ ! -d "$USER_HOME_DIR" ]; then
                # Home doesn't exist or not specified
                SHOULD_REMOVE_HOME=false # No home to remove effectively
            fi


            if $SHOULD_REMOVE_HOME ; then
                 log_action "Removing user $user and their group (and home directory $USER_HOME_DIR as backup was made or not needed)."
                 if ! deluser --remove-home "$user"; then # Added error check
                     log_error "Failed to remove user $user with --remove-home. Trying without."
                     deluser "$user" || log_error "Failed to remove user $user even without --remove-home."
                 fi
            else
                 log_warning "Removing user $user WITHOUT removing home directory (home: $USER_HOME_DIR)."
                 deluser "$user" || log_error "Failed to remove user $user."
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
    "libgtk-*" 
    "libgdk-*"
    "libcairo*" 
    "libpango-*" 
    "libatk-*"   
    "libglib2.0-*" 
    
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
    "w3m" 

    # --- Office Suites ---
    "libreoffice*"
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
    "*game*" 

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
    "at" 
    "aspell*" 
    "avahi-daemon*" 
    "bash-completion" 
    "bc" 
    "debian-faq*" 
    "doc-debian"
    "doc-linux-text"
    "eject"
    "fdutils" 
    "finger"
    "gettext-base" 
    "groff" 
    "gnupg" 
    "laptop-detect"
    "libgpmg1" 
    "manpages*" 
    "mtools" 
    "mtr-tiny" 
    "mutt" 
    "ncurses-term" 
    "ppp*" 
    "pppoe*"
    "read-edid" 
    "unzip"
    "usbutils" 
    "vim-common"
    "vim-tiny" 
    "wamerican" 
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
    "plymouth" 
    "plymouth-themes"
    "gnome-desktop3-data"
    "gnome-firmware"
    "gnome-icon-theme*" 
    "xdg-desktop-portal*"
    "xdg-user-dirs*" 
    "xdg-utils" 
    "firebird*" 
    "libfbclient2*"
    "libib-util*"
    "espeak*" 
    "speech-dispatcher*"
    "gnome-logs"
    "gnome-software" 
    "malcontent" 
    "mlterm*" 
    "xiterm+thai"
    "xterm" 
)

PACKAGES_TO_ACTUALLY_PURGE=()
for pkg_candidate_raw in "${PACKAGES_TO_PURGE[@]}"; do
    # Remove any trailing wildcards for essential/kept checks if the base name is what matters
    pkg_candidate_base="${pkg_candidate_raw//\*}"
    pkg_candidate_for_dpkg_check="$pkg_candidate_raw" # Use raw for dpkg check to handle wildcards

    is_essential_or_kept=false
    for kept_pkg in "${PACKAGES_TO_KEEP[@]}"; do
        if [[ "$pkg_candidate_base" == "$kept_pkg" ]] || [[ "$pkg_candidate_raw" == "$kept_pkg" ]]; then
            is_essential_or_kept=true
            log_warning "Skipping '$pkg_candidate_raw' from purge: explicitly in PACKAGES_TO_KEEP."
            break
        fi
    done

    if $is_essential_or_kept; then
        continue
    fi

    # Check essential/required status for the base package if it's a wildcard, 
    # or the full package name if not.
    # This is a heuristic; a non-essential wildcard pattern can still match essential sub-packages.
    # `apt` itself is the final arbiter of what can be removed.
    check_pkg_for_essential="$pkg_candidate_base"
    if [[ "$pkg_candidate_raw" != *"*"* ]]; then # Not a wildcard
        check_pkg_for_essential="$pkg_candidate_raw"
    fi
    
    status_output=$(dpkg-query -W -f='${Package}\t${Essential}\t${Priority}\n' "$check_pkg_for_essential" 2>/dev/null | head -n 1)
    if echo "$status_output" | grep -q -E "\s(yes|required)$"; then # essential=yes or priority=required
         # If the base of a wildcard is essential (e.g. "libc6" for "libc6*"), we are more careful.
         # However, patterns like "xserver-xorg-*" are intended to be purged even if some sub-packages are important (but not essential).
         # This check primarily protects exact matches that are essential/required.
        if [[ "$pkg_candidate_raw" != *"*"* ]]; then # Only skip if it's an exact match and essential/required
            log_warning "Skipping '$pkg_candidate_raw' from purge: marked essential/required by dpkg."
            continue
        fi
    fi
    
    # Check if package or wildcard matches any installed package
    if dpkg-query -W -f='${Status}' "${pkg_candidate_for_dpkg_check}" 2>/dev/null | grep -q "ok installed"; then
        PACKAGES_TO_ACTUALLY_PURGE+=("$pkg_candidate_raw")
    else
        # This is where the corrected log_action call is
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
        for pkg_to_purge in "${PACKAGES_TO_ACTUALLY_PURGE[@]}"; do
            log_action "Attempting to purge: $pkg_to_purge"
            apt-get purge -y "$pkg_to_purge"
            if [ $? -ne 0 ]; then
                log_warning "Issues encountered purging '$pkg_to_purge'. It might have already been removed, be part of a metapackage, or protected. Apt handles this."
            fi
        done
        log_action "Finished initial purge attempt."
    else
        log_warning "Package purge aborted by user."
    fi
else
    log_action "No packages identified for purging after filtering, or all matched patterns are not installed."
fi

# --- System Cleanup ---
log_section "System Cleanup"

log_action "Removing orphaned dependencies..."
apt-get autoremove --purge -y
if [ $? -ne 0 ]; then log_warning "Autoremove encountered issues. This is sometimes normal if packages were already removed."; fi

log_action "Cleaning up apt cache..."
apt-get clean -y
if [ $? -ne 0 ]; then log_warning "Apt clean encountered issues."; fi

log_action "Removing residual configuration files (apt purge should handle most)..."
if [ -d "/etc/libreoffice" ]; then
    log_action "Removing /etc/libreoffice..."
    rm -rf /etc/libreoffice
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
            log_action "MODULES setting not 'most', not changing to 'dep'. Current config preserved or MODULES=dep already set."
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
        IPV6_XTABLES_FILES=(
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_ah.so" # Paths can vary, check your system
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_dst.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_eui64.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_frag.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_hbh.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_hl.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_HL.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_icmp6.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_ipv6header.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_LOG.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_mh.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_REJECT.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_rt.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_DNAT.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_DNPT.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_MASQUERADE.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_NETMAP.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_REDIRECT.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_SNAT.so"
            "/usr/lib/x86_64-linux-gnu/xtables/libip6t_SNPT.so"
            # Add paths for /lib/xtables if they exist on your system version
            "/lib/xtables/libip6t_ah.so"
            "/lib/xtables/libip6t_dst.so"
            # ... (repeat for all files in /lib/xtables if needed)
        )
        log_action "Removing specified IPv6 xtables files..."
        REMOVED_COUNT=0
        for xt_file in "${IPV6_XTABLES_FILES[@]}"; do
            if [ -f "$xt_file" ]; then
                if rm -f "$xt_file"; then
                    echo "Removed $xt_file"
                    ((REMOVED_COUNT++))
                else
                    log_warning "Could not remove $xt_file (permission issue?)"
                fi
            else
                 : # File not found, silently ignore for this specific cleanup
            fi
        done
        log_action "Removed $REMOVED_COUNT IPv6 xtables files."
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
