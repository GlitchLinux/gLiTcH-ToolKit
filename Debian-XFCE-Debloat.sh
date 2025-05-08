#!/bin/bash

# --- Configuration ---
BACKUP_USER_HOMES=false # Set to true to attempt to backup user home directories to /opt/user_backups
BACKUP_DIR="/opt/user_backups"
LOG_FILE="/var/log/debloat_script.log"
KEEP_USERS=("root" "your_admin_user_if_any") # Add any other users you explicitly want to keep

# --- Script Setup ---
start_time=$SECONDS
now=$(date +"%Y-%m-%d_%A_%H:%M:%S")
script_pid=$$

# Colors
red=$(tput setaf 1)
green=$(tput setaf 2)
yellow=$(tput setaf 11)
blue=$(tput setaf 12)
reset=$(tput sgr0)

# Ensure running as root
if [ "$(id -u)" -ne 0 ]; then
  echo "${red}This script must be run as root. Please use sudo.${reset}" >&2
  exit 1
fi

# Logging function
log_action() {
  echo "$(date +"%Y-%m-%d %H:%M:%S") - $1" | tee -a "$LOG_FILE"
}

# Section header function
print_section() {
  echo
  log_action "-------------------------===== $1 =====-------------------------"
  echo
}

# --- Initial Display and Warning ---
clear
printf '\033[8;40;120t' # Resize window

echo "${yellow}================================================================================"
echo "                DEBIAN XFCE TO MINIMAL HEADLESS DEBLOATER"
echo "================================================================================"
echo "${red}                           *** EXTREME CAUTION ***"
echo "${yellow}This script will:"
echo "  - Remove XFCE, LightDM, X.Org, and all associated GUI components."
echo "  - Purge games, browsers, office suites, media players, and many other apps."
echo "  - Potentially remove all non-root users and their home directories."
echo "  - Aggressively clean up system files and configurations."
echo ""
echo "  ${red}MAKE ABSOLUTELY SURE YOU ARE RUNNING THIS ON THE CORRECT SYSTEM"
echo "  ${red}AND HAVE BACKUPS OF ANY IMPORTANT DATA."
echo ""
echo "  ${blue}Packages to be explicitly kept (if present):"
echo "    openssh-server, git, wget, bash, nano, grub, networking components,"
echo "    cryptsetup, sudo, apt, dpkg, core system utilities, kernel."
echo ""
echo "  Log file will be: $LOG_FILE"
echo "${yellow}================================================================================"${reset}
echo
read -p "${yellow}Type 'PROCEED' to continue, or anything else to abort: ${reset}" confirmation

if [ "$confirmation" != "PROCEED" ]; then
  log_action "User aborted script."
  echo "${red}Aborted by user.${reset}"
  exit 1
fi

log_action "Debloat script started by UID $(id -u) at $now. PID: $script_pid"
log_action "WARNING: This script is highly destructive and configured to make significant changes."

# --- Variables from User Scripts ---
part=0
primeerror=0
error=0
automatic=0
debug=0
noquit=0 # Will be set to 1 at the end for final message if preferred

# --- User Management ---
print_section "User Management"

if $BACKUP_USER_HOMES; then
  log_action "Attempting to backup user home directories to $BACKUP_DIR"
  mkdir -p "$BACKUP_DIR"
  if [ $? -ne 0 ]; then
    log_action "${red}Error creating backup directory $BACKUP_DIR. Skipping backups.${reset}"
    echo "${red}Error creating backup directory $BACKUP_DIR. Skipping backups.${reset}"
  else
    for user_home in /home/*; do
      if [ -d "$user_home" ]; then
        username=$(basename "$user_home")
        keep_this_user=false
        for kept_user in "${KEEP_USERS[@]}"; do
          if [ "$username" == "$kept_user" ]; then
            keep_this_user=true
            break
          fi
        done

        if ! $keep_this_user; then
          log_action "Backing up /home/$username to $BACKUP_DIR/$username-$(date +%F_%H%M%S).tar.gz"
          tar -czf "$BACKUP_DIR/$username-$(date +%F_%H%M%S).tar.gz" -C /home "$username"
          if [ $? -eq 0 ]; then
            log_action "Backup of $username successful."
          else
            log_action "${yellow}Warning: Backup of $username failed.${reset}"
          fi
        else
          log_action "Skipping backup for explicitly kept user: $username"
        fi
      fi
    done
  fi
fi

log_action "Removing non-essential users..."
getent passwd | awk -F: '$3 >= 1000 && $3 != 65534 {print $1}' | while read -r username; do
  keep_this_user=false
  for kept_user in "${KEEP_USERS[@]}"; do
    if [ "$username" == "$kept_user" ]; then
      keep_this_user=true
      break
    fi
  done

  if ! $keep_this_user; then
    log_action "Removing user: $username and their home directory."
    # Kill processes by this user first
    # pkill -u "$username" # More gentle
    killall -KILL -u "$username" # More forceful
    sleep 1
    deluser --remove-home "$username"
    if [ $? -eq 0 ]; then
      log_action "Successfully removed user $username and their home directory."
    else
      log_action "${yellow}Warning: Could not remove user $username or their home directory fully.${reset}"
    fi
    # Remove user from any groups they might be primary in (deluser should handle this)
    # groupdel "$username" 2>/dev/null
  else
    log_action "Keeping user: $username"
  fi
done
log_action "User cleanup finished."

# --- Stop GUI Services ---
print_section "Stopping GUI and Related Services"
log_action "Stopping LightDM, Xorg, and other potential display managers..."
systemctl stop lightdm.service || log_action "LightDM was not running or failed to stop."
systemctl disable lightdm.service || log_action "Failed to disable LightDM."

# Add other display managers if they might exist
systemctl stop gdm.service gdm3.service sddm.service 2>/dev/null
systemctl disable gdm.service gdm3.service sddm.service 2>/dev/null

# Stop other potentially problematic services before removal
log_action "Stopping other services that might interfere..."
systemctl stop bluetooth.service || log_action "Bluetooth service not running or failed to stop."
systemctl stop cups.service || log_action "CUPS service not running or failed to stop."
systemctl stop avahi-daemon.service || log_action "Avahi service not running or failed to stop."
systemctl stop ModemManager.service || log_action "ModemManager service not running or failed to stop."
systemctl stop speech-dispatcherd.service || log_action "Speech Dispatcher not running or failed to stop."

systemctl disable bluetooth.service || log_action "Failed to disable Bluetooth."
systemctl disable cups.service || log_action "Failed to disable CUPS."
systemctl disable avahi-daemon.service || log_action "Failed to disable Avahi."
systemctl disable ModemManager.service || log_action "Failed to disable ModemManager."
systemctl disable speech-dispatcherd.service || log_action "Failed to disable Speech Dispatcher."


# --- Package Removal ---
# Define packages to remove. Wildcards are used.
# This is a very extensive list. Be careful.

PACKAGES_TO_PURGE=(
    # --- XFCE Desktop Environment and Core GUI ---
    "task-xfce-desktop"
    "xfce4*" "libxfce4*" "xfwm4*" "libxfce4ui*" "libxfce4util*"
    "thunar*" "mousepad*" "parole*" "ristretto*" "xfburn*" "xfce4-appfinder*"
    "xfce4-notifyd*" "xfce4-panel*" "xfce4-session*" "xfce4-settings*"
    "xfce4-terminal" # Removing this, assuming console/SSH access is primary
    "catfish*" "engrampa*" "orage*" "xfdesktop4*"
    "gtk2-engines*" "gtk3-engines*" "gtk+*-*" "libgtk-*" "libgtk2.0-*" "libgtk-3-*" "libgtk-4-*"
    "libqt5*" "libqt6*" "qt5-*" "qt6-*" # Careful with Qt if any desired CLI tools depend on it
    "lightdm*" "xserver-xorg-core*" "xserver-xorg" "xorg" "x11-common" "x11-apps" "x11-session-utils"
    "x11-utils" "x11-xkb-utils" "x11-xserver-utils" "xinit" "xinput" "xfonts-*"
    "gnome-icon-theme" "tango-icon-theme" "elementary-xfce-icon-theme" "adwaita-icon-theme"
    "desktop-file-utils" # For .desktop files
    "xdg-user-dirs" "xdg-utils" # XDG utilities often for GUI context
    "libglib2.0-data" # often with GUI
    "shared-mime-info" # Mime types, mostly for GUI

    # --- Games (Comprehensive List) ---
    "aisleriot" "five-or-more" "four-in-a-row" "gnome-2048" "gnome-chess"
    "gnome-klotski" "gnome-mahjongg" "gnome-mines" "gnome-nibbles" "gnome-robots"
    "gnome-sudoku" "gnome-taquin" "gnome-tetravex" "hitori" "iagno" "lightsoff"
    "quadrapassel" "swell-foop" "tali" "*game*" # Generic wildcard, be cautious

    # --- Browsers ---
    "firefox*" "firefox-esr*" "chromium*" "epiphany-browser*" "surf" "netsurf-*"

    # --- Office Suites ---
    "libreoffice*" "libobasis*" "gnumeric*" "abiword*" "calligra-*"

    # --- Multimedia ---
    "brasero*" "cheese*" "gnome-sound-recorder*" "sound-juicer*" "totem*" "vlc*"
    "rhythmbox*" "pavucontrol*" "pulseaudio*" "alsa-utils*" "alsa-tools*" # alsa-utils contains alsamixer which can be useful even headless
    "mpv" "mplayer" "smplayer" "lxmusic*" "audacious*" "exaile*" "pitivi*" "kdenlive*" "openshot*"
    "pipewire*" # Modern audio/video server, might replace pulseaudio

    # --- Graphics Applications ---
    "gimp*" "eog*" "shotwell*" "simple-scan*" "inkscape*" "krita*" "darktable*"
    "ristretto" # Already in XFCE list, but ensure it's caught

    # --- Internet & Communication (Non-Browser) ---
    "deluge*" "hexchat*" "pidgin*" "remmina*" "thunderbird*" "transmission-gtk*" "transmission-cli" "evolution*"
    "filezilla*" "xchat*"

    # --- PDF/Document Viewers (GUI) ---
    "evince*" "atril*" "okular*" "xpdf*" "zathura*" # Zathura can be CLI but often with GUI deps

    # --- Input Methods ---
    "anthy*" "kasumi*" "mozc-*" "uim-*" "fcitx*" "ibus*" "im-config"

    # --- Other Accessories & System Tools (GUI or non-essential for headless) ---
    "deja-dup*" "gnote*" "goldendict*" "yelp*" "debian-reference-*" "eject" "id3*"
    "mdadm" # Remove if NOT using software RAID
    "vino*" # VNC server
    "gnome-logs*" "gnome-software*" "malcontent*" "mlterm*" "xiterm*" "xterm" # xterm is a fallback, but for minimal headless, not strictly needed
    "synaptic*" # GUI package manager
    "gnome-disk-utility" "gparted" # GUI disk managers
    "baobab" # Disk usage analyzer (GUI)
    "seahorse" # Passwords and keys (GUI)
    "system-config-printer*" "cups*" # Printing system
    "bluetooth" "bluez*" "blueman*" # Bluetooth
    "modemmanager"
    "network-manager" "network-manager-gnome" # Using systemd-networkd or ifupdown for headless
    "plymouth*" # Bootsplash
    "xsane*" # Scanning
    "speech-dispatcher*" "espeak*" # Text-to-speech
    "gnome-firmware" "gnome-desktop3-data"
    "sound-theme-freedesktop"
    "dconf-gsettings-backend" "dconf-service" # often GUI config related
    "gvfs-*" # GNOME Virtual File System, mostly for GUI integration
    "policykit-1-gnome" # Polkit GUI agent
    "zeitgeist-*" # Activity logging, often desktop related
    "tracker-*" # File indexing, desktop related
    "colord*" # Color management, mostly for GUI

    # --- From user-provided "non-critical" list (selectively chosen) ---
    "aptitude" # CLI alternative to apt, can go
    "acpi" "acpid" # Can be useful for power events, but optional for bare server
    "at" # Job scheduler, cron is usually sufficient
    "aspell*" "ispell*" "hunspell-*" "mythes-*" "hyphen-*" # Spell checking and dictionaries
    "console-setup*" "console-data" "console-tools" # If default console is fine
    "dc" "bc" # CLI calculators
    "debian-faq*" "doc-debian" "doc-linux-text" "manpages-dev" # Docs
    "dictionaries-common"
    # "eject" # Already listed
    "fdutils" # Floppy utils
    # "file" # 'file' command is quite useful, consider keeping
    "finger"
    "foomatic-filters" "hplip" # Printing
    "gettext" # Often useful for i18n in CLI tools too, but -base is usually enough
    "groff" "groff-base" # For man pages, if removing man-db
    # "info" # GNU info reader
    "laptop-detect"
    "libgpm2" "gpm" # Console mouse support
    # "man-db" "manpages" # Removing man pages saves space, but makes troubleshooting harder. Consider keeping.
    "mtools" # DOS FS utils
    "mtr-tiny" # Network diagnostic, consider keeping if 'traceroute' is removed
    "mutt" # CLI email
    "ncurses-term" # Additional terminal definitions
    "pidentd" # IDENT server
    "ppp*" # Dial-up
    "read-edid" # Monitor info
    "reportbug" # Debian bug reporter
    # "tasksel" # Initial installer tool, safe to remove
    "tcsh" # C-shell
    "traceroute" # Consider keeping for network diagnostics
    # "usbutils" # lsusb is useful. Keep?
    "wamerican*" "wbritish*" "wbritish*" "wcatalan*" "wdanish*" # etc. wordlists
    "w3m" # Text browser
    "whois"
    "zeroinstall-injector"
    "lsof" # Can be useful, but often not essential for basic server
    "psmisc" # Provides pstree, fuser, killall. 'killall' is used by this script. Ensure an alternative or handle its absence if removed.
    "sudo" # Explicitly KEEPING
    "vim" "vim-tiny" "vim-common" # User wants nano

    # --- Font packages (many will be caught by xfonts-*) ---
    "fonts-*" "ttf-*" "otf-*" "fontconfig" "fontconfig-config" # Fontconfig can be a deep dependency

    # --- From "Gnome but maybe valid" list ---
    "grub-firmware-qemu" # Only if you know you don't need it for QEMU/virtualization
    "xdg-desktop-portal*" "xdg-desktop-portal-gtk"

    # --- Cleanup libraries that might be left ---
    # Be very careful with these, only if they are truly orphaned. Autoremove should get most.
    # "libxft2" "libxrender1" "libxfixes3" "libxcursor1" "libxdamage1" "libxinerama1"
    # "libxrandr2" "libxcomposite1" "libxi6" "libxkbcommon0" "libwayland-client0" "libdrm2"
    # "libpango-1.0-0" "libpangocairo-1.0-0" "libpangoft2-1.0-0" "libcairo2" "libgdk-pixbuf-2.0-0" "libgdk-pixbuf2.0-common"
    # "libatk1.0-0" "libatk-bridge2.0-0"
)

print_section "Purging Identified Packages"
log_action "Starting main package purge operation. This may take a long time."

# Convert array to space-separated string for apt
packages_to_purge_string="${PACKAGES_TO_PURGE[*]}"

# It's safer to remove in chunks or let apt handle complex dependencies.
# Using one large command can sometimes be problematic for apt's resolver.
# However, for a full purge, it's often effective.
sudo apt-get purge -y $packages_to_purge_string
if [ $? -ne 0 ]; then
    log_action "${yellow}Warning: Some packages in the main list could not be purged. Check apt logs.${reset}"
    # Attempt to remove problematic packages individually or in smaller groups if needed (more complex logic)
else
    log_action "Main package purge command completed."
fi

# --- Autoremove and Clean ---
print_section "Autoremoving Orphaned Packages and Cleaning Up"
log_action "Running apt-get autoremove --purge -y"
sudo apt-get autoremove --purge -y
if [ $? -ne 0 ]; then
    log_action "${yellow}Warning: Autoremove encountered issues.${reset}"
else
    log_action "Autoremove completed."
fi

log_action "Running apt-get clean -y and autoclean -y"
sudo apt-get clean -y
sudo apt-get autoclean -y
log_action "Apt cache cleaned."

# --- Further System Configuration Cleanup ---
print_section "System Configuration Cleanup"

# Remove residual X11 configuration (if any and if safe)
if [ -d "/etc/X11" ] && [ ! -L "/etc/X11" ]; then # Check if it's a directory and not a symlink
    # Check if it's empty or only contains symlinks before removing
    if [ -z "$(find /etc/X11 -mindepth 1 -not -type l -print -quit)" ]; then
        log_action "Removing /etc/X11 as it seems to contain only symlinks or is empty post-purge."
        rm -rf /etc/X11
    else
        log_action "/etc/X11 still contains files/directories. Not removing automatically. Please review."
    fi
else
    log_action "/etc/X11 not found or is a symlink."
fi


# Clean user-specific GUI configs for any remaining users (including root)
log_action "Cleaning user-specific GUI configuration files..."
for user_home_dir in /root /home/*; do
  if [ -d "$user_home_dir" ]; then
    log_action "Cleaning configs in $user_home_dir"
    rm -rf "$user_home_dir/.config/xfce4"
    rm -rf "$user_home_dir/.config/gtk-*"
    rm -rf "$user_home_dir/.config/qt5ct"
    rm -rf "$user_home_dir/.config/Trolltech.conf"
    rm -rf "$user_home_dir/.config/pulse" # PulseAudio client config
    rm -rf "$user_home_dir/.local/share/xfce4"
    rm -rf "$user_home_dir/.local/share/gvfs-metadata"
    rm -rf "$user_home_dir/.local/share/zeitgeist"
    rm -rf "$user_home_dir/.local/share/tracker"
    rm -rf "$user_home_dir/.cache/xfce4"
    rm -rf "$user_home_dir/.cache/thumbnails"
    rm -rf "$user_home_dir/.cache/fontconfig"
    # LibreOffice specific (from user script, good to have here too)
    rm -rf "$user_home_dir/.config/libreoffice"
    rm -rf "$user_home_dir/.local/share/libreoffice"
  fi
done

# LibreOffice system-wide (from user script)
log_action "Removing LibreOffice system-wide configuration files..."
rm -rf /etc/libreoffice
# rm -rf /usr/lib/libreoffice # Should be handled by purge
# rm -rf /usr/share/libreoffice # Should be handled by purge

# Clean temporary files (LibreOffice specific and general)
log_action "Removing temporary files..."
rm -rf /tmp/libreoffice*
rm -rf /var/tmp/libreoffice*
rm -rf /tmp/*
rm -rf /var/tmp/*

# --- Initramfs Reduction (from user notes) ---
print_section "Optimizing Initramfs"
log_action "Setting initramfs compression to xz."
echo "COMPRESS=xz" | sudo tee /etc/initramfs-tools/conf.d/compress_xz.conf > /dev/null
log_action "Setting initramfs modules to 'dep'."
if grep -q "MODULES=most" /etc/initramfs-tools/initramfs.conf; then
    sudo sed -i 's/MODULES=most/MODULES=dep/g' /etc/initramfs-tools/initramfs.conf
    log_action "Changed MODULES=most to MODULES=dep."
else
    log_action "MODULES=most not found, attempting to ensure MODULES=dep."
    if ! grep -q "MODULES=dep" /etc/initramfs-tools/initramfs.conf; then
        echo "MODULES=dep" | sudo tee -a /etc/initramfs-tools/initramfs.conf > /dev/null
    fi
fi
log_action "Updating initramfs. This may take some time..."
sudo update-initramfs -u -k all
if [ $? -ne 0 ]; then
    log_action "${yellow}Warning: update-initramfs failed. Check for errors.${reset}"
else
    log_action "Initramfs update completed."
fi

# --- Remove Unnecessary IPv6 Files (from user notes) - VERY AGGRESSIVE ---
# This is generally not recommended. Disabling IPv6 via sysctl or GRUB is safer.
# Proceed with extreme caution. This might break things if not fully understood.
REMOVE_IPV6_XTABLES=false # Set to true to enable this dangerous section

if $REMOVE_IPV6_XTABLES; then
  print_section "Removing IPv6 xtables Files (Aggressive)"
  log_action "${yellow}WARNING: Attempting to remove IPv6 xtables files. This is risky.${reset}"
  IPV6_XTABLES_FILES=(
    "/lib/xtables/libip6t_ah.so" "/lib/xtables/libip6t_dst.so" "/lib/xtables/libip6t_eui64.so"
    "/lib/xtables/libip6t_frag.so" "/lib/xtables/libip6t_hbh.so" "/lib/xtables/libip6t_hl.so"
    "/lib/xtables/libip6t_HL.so" "/lib/xtables/libip6t_icmp6.so" "/lib/xtables/libip6t_ipv6header.so"
    "/lib/xtables/libip6t_LOG.so" "/lib/xtables/libip6t_mh.so" "/lib/xtables/libip6t_REJECT.so"
    "/lib/xtables/libip6t_rt.so" "/lib/xtables/libip6t_DNAT.so" "/lib/xtables/libip6t_DNPT.so"
    "/lib/xtables/libip6t_MASQUERADE.so" "/lib/xtables/libip6t_NETMAP.so"
    "/lib/xtables/libip6t_REDIRECT.so" "/lib/xtables/libip6t_SNAT.so" "/lib/xtables/libip6t_SNPT.so"
  )
  for xt_file in "${IPV6_XTABLES_FILES[@]}"; do
    if [ -f "$xt_file" ]; then
      log_action "Removing $xt_file"
      rm -f "$xt_file"
    else
      log_action "$xt_file not found, skipping."
    fi
  done
else
  log_action "Skipping IPv6 xtables file removal (REMOVE_IPV6_XTABLES is false)."
  log_action "Consider disabling IPv6 via GRUB: GRUB_CMDLINE_LINUX_DEFAULT=\"ipv6.disable=1\" in /etc/default/grub then update-grub."
fi

# --- Final System State Check & Journal Cleanup ---
print_section "Final System State"
log_action "Listing installed packages (first 50)..."
dpkg -l | head -n 50 | tee -a "$LOG_FILE"

log_action "Disk space usage:"
df -h | tee -a "$LOG_FILE"

log_action "Memory usage:"
free -h | tee -a "$LOG_FILE"

log_action "Cleaning journal logs older than 3 days..."
sudo journalctl --vacuum-time=3d | tee -a "$LOG_FILE"

# --- Completion ---
end_time=$SECONDS
duration=$((end_time - start_time))
date_duration=$(date -d@$duration -u +%H:%M:%S)

print_section "Debloat Script Finished"
log_action "Script finished."
log_action "Total execution time: $date_duration ($duration seconds)."

echo "${green}================================================================================"
echo "                  DEBLOAT SCRIPT COMPLETED"
echo "================================================================================"${reset}
echo "Execution time: ${blue}$date_duration${reset}"
echo "Log file: ${blue}$LOG_FILE${reset}"
echo ""
echo "${yellow}The system has been significantly altered."
echo "It is highly recommended to REBOOT now to ensure all changes take effect"
echo "and that the system boots correctly into a headless state."${reset}
echo ""
echo "${red}Ensure you have SSH access configured and working before rebooting if this is a remote machine!${reset}"
echo ""

read -p "Press ENTER to exit. Consider rebooting soon."

exit 0
