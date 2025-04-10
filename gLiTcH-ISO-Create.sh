#!/bin/bash
# Exit immediately if a command exits with a non-zero status.
set -e

# --- Configuration ---
# Set the base URL for bootfiles (ensure this remains valid)
BOOTFILES_URL="https://github.com/GlitchLinux/gLiTcH-ISO-Creator/blob/main/BOOTFILES.tar.gz?raw=true"

# --- Helper Functions ---
detect_pkg_manager() {
    if [ -x "$(command -v apt-get)" ]; then echo "apt";
    elif [ -x "$(command -v dnf)" ]; then echo "dnf";
    elif [ -x "$(command -v yum)" ]; then echo "yum";
    elif [ -x "$(command -v pacman)" ]; then echo "pacman";
    else echo "unknown"; fi
}

# Helper function to execute commands with sudo IF NOT already root
run_privileged() {
    if [ "$EUID" -ne 0 ]; then
        sudo "$@"
    else
        # Already root, just run the command
        "$@"
    fi
}


install_pkg() {
    local pkg_manager=$1
    shift
    local packages=("$@")
    echo "--> Attempting to install required packages: ${packages[*]}"
    # Use run_privileged helper for package installation
    case "$pkg_manager" in
        apt) run_privileged apt-get update && run_privileged apt-get install -y "${packages[@]}" ;;
        dnf) run_privileged dnf install -y "${packages[@]}" ;;
        yum) run_privileged yum install -y "${packages[@]}" ;;
        pacman) run_privileged pacman -S --noconfirm "${packages[@]}" ;;
        *) echo "[ERROR] Unsupported package manager '$pkg_manager'. Cannot install packages." ; return 1 ;;
    esac
    echo "--> Package installation attempt finished."
}

# --- Script Functions ---

step_marker() {
    echo "" # Blank line for separation
    echo "=============================================================================="
    echo "=== $1"
    echo "=============================================================================="
}

install_dependencies() {
    step_marker "Step 1: Checking and Installing Dependencies"
    echo "Detecting package manager..."
    local pm
    pm=$(detect_pkg_manager)
    echo "Detected package manager: $pm"

    if [[ "$pm" == "unknown" ]]; then
        echo "[ERROR] Could not detect a supported package manager (apt, dnf, yum, pacman)."
        echo "Please install the following dependencies manually: xorriso, isolinux/syslinux, mtools, wget, squashfs-tools, grub-efi binaries"
        exit 1
    fi

    local core_pkgs=(xorriso mtools wget squashfs-tools)
    local grub_efi_pkg=""
    local live_pkgs=() # Packages needed for the initramfs to boot live
    local syslinux_pkgs=()

    # Determine package names based on the detected manager
    case "$pm" in
        apt)
            grub_efi_pkg="grub-efi-amd64-bin" # Provides grub-mkimage, grubx64.efi
            live_pkgs=(live-boot live-config live-tools) # Common for Debian/Ubuntu derivatives
            syslinux_pkgs=(isolinux syslinux syslinux-utils) # Need isolinux.bin, vesamenu.c32, isohdpfx.bin etc.
            ;;
        dnf | yum)
            grub_efi_pkg="grub2-efi-x64" # For Fedora/RHEL
            # dracut-live might be needed, but dracut configuration is key
            live_pkgs=(dracut-live) # Ensure dracut config includes live modules if using dracut
            syslinux_pkgs=(isolinux syslinux)
            ;;
        pacman)
            grub_efi_pkg="grub" # Arch's GRUB package includes EFI tools
            # archiso package includes hooks/tools for live env, relies on mkinitcpio
            live_pkgs=(archiso) # Ensure mkinitcpio.conf has 'archiso' hook
            syslinux_pkgs=(syslinux)
            ;;
    esac

    # Combine all packages
    local all_pkgs=("${core_pkgs[@]}" "$grub_efi_pkg" "${live_pkgs[@]}" "${syslinux_pkgs[@]}")
    # Remove potential empty elements
    all_pkgs=(${all_pkgs[@]})

    echo "Required packages identified: ${all_pkgs[*]}"

    # Check if core tools are already installed to avoid unnecessary installs
    local missing_core=0
    for pkg in xorriso mksquashfs wget mkfs.vfat; do # mkfs.vfat usually in dosfstools/mtools
        if ! command -v $pkg &>/dev/null; then
             echo "--> Core tool '$pkg' seems missing."
             missing_core=1
             break
        fi
    done
    if ! command -v isolinux.bin &>/dev/null && ! find /usr/lib/syslinux /usr/share/syslinux -name isolinux.bin -print -quit &>/dev/null; then
        echo "--> Core component 'isolinux.bin' seems missing."
        missing_core=1
    fi


    if [[ "$missing_core" -eq 1 ]]; then
        echo "Core dependencies appear to be missing. Attempting installation..."
        if ! install_pkg "$pm" "${all_pkgs[@]}"; then
            echo "[ERROR] Failed to install dependencies. Please install them manually and re-run."
            exit 1
        fi
    else
        echo "Basic dependencies seem present. Checking for optional live-boot packages..."
        # Attempt to install only the live packages if core seems okay
        if [[ ${#live_pkgs[@]} -gt 0 ]]; then
             if ! install_pkg "$pm" "${live_pkgs[@]}"; then
                 echo "[WARNING] Failed to install specific live-boot packages (${live_pkgs[*]}). The initramfs might lack live boot support."
                 # Continue, but warn the user
             fi
        else
             echo "No specific live-boot packages identified for auto-install for $pm."
        fi
        # Ensure syslinux is installed even if core tools seem present
        if [[ ${#syslinux_pkgs[@]} -gt 0 ]]; then
             if ! install_pkg "$pm" "${syslinux_pkgs[@]}"; then
                 echo "[WARNING] Failed to install specific syslinux packages (${syslinux_pkgs[*]}). BIOS boot might fail."
             fi
        else
             echo "No specific syslinux packages identified for auto-install for $pm."
        fi
        # Ensure grub EFI is installed
         if [[ -n "$grub_efi_pkg" ]]; then
             if ! install_pkg "$pm" "$grub_efi_pkg"; then
                 echo "[WARNING] Failed to install GRUB EFI package ($grub_efi_pkg). UEFI boot might fail."
             fi
         fi
    fi
    echo "Dependency check/installation finished."
}

regenerate_host_initramfs() {
    step_marker "Step 2: Regenerating Host Initramfs (Optional)"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"
    echo "!!! WARNING: This step attempts to modify your *current* operating system's !!!"
    echo "!!!          initramfs. This is potentially risky and could affect your    !!!"
    echo "!!!          host system's ability to boot if something goes wrong.        !!!"
    echo "!!!          It is crucial that your initramfs contains the necessary      !!!"
    echo "!!!          modules/hooks (e.g., live-boot, archiso) to boot the ISO.     !!!"
    echo "!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!"

    read -p "Do you want to attempt regenerating the host initramfs now? (y/N): " confirm_initrd
    if [[ ! "$confirm_initrd" =~ ^[Yy]$ ]]; then
       echo "Skipping host initramfs regeneration."
       echo "Ensure your *existing* initramfs in /boot already supports live booting!"
       return
    fi

    echo "Attempting to regenerate host initramfs to include live-boot capabilities..."
    local pm
    pm=$(detect_pkg_manager)
    local success=0

    # Use 'run_privileged' helper for these commands
    case "$pm" in
        apt)
            echo "Running 'run_privileged update-initramfs -u -k all'..."
            if run_privileged update-initramfs -u -k all; then success=1; fi
            ;;
        dnf | yum)
            echo "Running 'run_privileged dracut --force --regenerate-all'..."
            echo "(Ensure /etc/dracut.conf or conf.d includes live modules like 'dmsquash-live')"
            if run_privileged dracut --force --regenerate-all; then success=1; fi
            ;;
        pacman)
            echo "Running 'run_privileged mkinitcpio -P'..."
            echo "(Ensure /etc/mkinitcpio.conf HOOKS includes 'archiso' or similar live hooks)"
            if run_privileged mkinitcpio -P; then success=1; fi
            ;;
        *)
            echo "[WARNING] Cannot automatically regenerate initramfs for this system ($pm)."
            echo "Please ensure your initramfs includes live boot support manually."
            read -p "Press Enter to continue despite warning, or Ctrl+C to abort."
            return # Don't mark as success
            ;;
    esac

    if [[ "$success" -eq 1 ]]; then
        echo "Initramfs regeneration command executed. Check output for errors."
    else
        echo "[ERROR] Initramfs regeneration command failed. Check output for details."
        echo "The generated ISO might not boot correctly."
        read -p "Press Enter to continue anyway, or Ctrl+C to abort."
    fi
}

create_squashfs() {
    local iso_build_dir="$1" # Use the full path passed from main
    local squashfs_target="$iso_build_dir/live/filesystem.squashfs"
    step_marker "Step 3: Creating SquashFS Filesystem"

    echo "Build Directory: $iso_build_dir"
    echo "Target SquashFS: $squashfs_target"

    # Ensure target directory exists
    echo "--> Creating live directory: $iso_build_dir/live"
    # No sudo needed if $iso_build_dir is in $HOME or user-writable area
    mkdir -p "$iso_build_dir/live"
    if [ $? -ne 0 ]; then
        echo "[ERROR] Failed to create directory structure: $iso_build_dir/live"
        echo "[ERROR] Check permissions or path. Aborting."
        exit 1
    fi

    # --- Comprehensive Exclusions List ---
    # Exclude pseudo-filesystems, temporary data, caches, logs, host-specific configs,
    # sensitive data, build artifacts, and potentially large/unneeded directories.
    local exclusions=(
        "$iso_build_dir/*"        # Exclude the build directory itself! Crucial.
        /proc/*
        /sys/*
        /dev/*
        /run/*
        /tmp/*
        /mnt/*
        /media/*
        /lost+found
        /swapfile
        /swap.img
        /pagefile.sys

        # User homes - exclude sensitive data, caches, trash etc.
        /root/* # Exclude root's home entirely (can contain sensitive data)
        /home/*/.cache/*
        /home/*/.dbus
        /home/*/.local/share/Trash/*
        /home/*/.gvfs
        /home/*/.ssh/* # Exclude SSH keys/configs
        /home/*/.gnupg/* # Exclude GPG keys/configs
        /home/*/.config/pulse/cookie # PulseAudio cookie
        /home/*/.wget-hsts
        /home/*/.bash_history
        /root/.bash_history
        /root/.ssh/*
        /root/.gnupg/*
        /root/.local/share/Trash/*

        # Var log, tmp, cache, spool - usually not needed or regenerated
        /var/log/*
        /var/tmp/*
        /var/spool/*
        /var/crash/*
        /var/lib/systemd/coredump/*
        /var/cache/* # Generic cache
        # Specific package manager caches/lists
        /var/lib/apt/lists/*
        /var/cache/apt/archives/*.deb
        /var/lib/dnf/* # DNF cache/history
        /var/cache/dnf/*
        /var/lib/pacman/sync/* # Pacman sync DBs
        /var/cache/pacman/pkg/* # Pacman package cache

        # Host-specific configuration files
        /etc/fstab                   # Should be handled by live env
        /etc/crypttab                # Host encryption
        /etc/mtab                    # Should be generated
        /etc/hostname                # Should be set for live system
        /etc/hosts                   # Often minimal/generated in live system
        /etc/resolv.conf             # Often managed dynamically or by live-config
        /etc/machine-id              # Should be generated on first boot
        /etc/ssh/ssh_host_* # Host SSH keys MUST NOT be cloned
        /etc/NetworkManager/system-connections/* # Saved Wi-Fi passwords etc.
        /etc/udev/rules.d/70-persistent-net.rules # Host specific network device naming

        # Build/dev related, often large
        /usr/src/*
        /boot/*rescue*
        /boot/System.map*
        /boot/config-* # Kernel config files usually not needed runtime

        # Other potential exclusions
        "$HOME/*.iso"             # Exclude existing ISOs in user's home
        /var/lib/docker/* # Exclude docker images/volumes if present
        /var/lib/libvirt/images/* # Exclude VM images if present
        # Add more based on your specific host system setup
    )

    # Build the exclusion arguments for mksquashfs
    local mksquashfs_opts=()
    for item in "${exclusions[@]}"; do
        mksquashfs_opts+=(-e "$item")
    done

    echo "Creating filesystem.squashfs from / ..."
    echo "(This will take a significant amount of time and requires root privileges)"
    echo "Excluding numerous paths (like /proc, /sys, /dev, /tmp, /home/*/.ssh, /var/log, etc)..."
    # echo "Full exclusion list:"
    # printf '  %s\n' "${exclusions[@]}" # Uncomment to see all exclusions

    # Run mksquashfs using run_privileged helper. set -e will cause script exit on failure.
    # -comp xz uses more CPU but gives better compression. Use 'gzip' for faster builds.
    # -b 1M sets block size to 1 MiB, good for general use.
    if run_privileged mksquashfs / "$squashfs_target" \
        -comp xz \
        -b 1048576 \
        -noappend \
        "${mksquashfs_opts[@]}" ; then
        echo "--> mksquashfs completed successfully."
        echo "[INFO] mksquashfs might have printed warnings about files it could not read or skipped (e.g., broken symlinks). This is often normal if the main process succeeded."
    else
        echo "[ERROR] mksquashfs failed. Check the output above for details."
        echo "[ERROR] Common causes: Insufficient disk space in target location or /tmp, critical read errors."
        exit 1
    fi

    # Verify the squashfs file (optional, but good practice)
    echo "--> Verifying the created squashfs file (quick check)..."
    # unsquashfs doesn't typically need root unless checking permissions deep inside
    if ! unsquashfs -s "$squashfs_target" > /dev/null; then
        echo "[ERROR] Created squashfs file ($squashfs_target) appears invalid or corrupted!"
        exit 1
    fi

    echo "Filesystem.squashfs created and verified at $squashfs_target"
}

copy_kernel_initrd() {
    local iso_build_dir="$1" # Use the full path passed from main
    step_marker "Step 4: Copying Kernel and Initrd"

    echo "Build Directory: $iso_build_dir"
    echo "--> Searching for latest kernel and initrd in /boot..."
    echo "[INFO] Ensure the selected initramfs contains necessary live-boot support!"

    local live_dir="$iso_build_dir/live"
    mkdir -p "$live_dir" # Ensure target exists

    # --- Find and copy vmlinuz ---
    local vmlinuz_file
    # Prioritize versioned kernels, excluding rescue kernels, sort by version, take latest
    vmlinuz_file=$(find /boot -maxdepth 1 -name 'vmlinuz-[0-9]*' ! -name '*-rescue*' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
     if [ -z "$vmlinuz_file" ]; then
          # Fallback to generic name or first found if specific version not found
          vmlinuz_file=$(find /boot -maxdepth 1 -name 'vmlinuz' -o -name 'vmlinuz-linux' | head -n 1)
          if [ -z "$vmlinuz_file" ]; then
              echo "[ERROR] Could not find a suitable vmlinuz kernel file in /boot."
              exit 1
          fi
          echo "[WARNING] Could not find versioned kernel, using generic: $vmlinuz_file"
       fi

    echo "--> Using Kernel: $vmlinuz_file"
    # Use run_privileged helper for the copy
    if ! run_privileged cp "$vmlinuz_file" "$live_dir/vmlinuz"; then
        echo "[ERROR] Failed to copy kernel file '$vmlinuz_file' to '$live_dir/vmlinuz'."
        exit 1
    fi

    # --- Find and copy initrd ---
    local initrd_file
    # Try initrd.img pattern first
    initrd_file=$(find /boot -maxdepth 1 -name 'initrd.img-[0-9]*' ! -name '*-rescue*' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
    if [ -z "$initrd_file" ]; then
        # Try initramfs pattern
        initrd_file=$(find /boot -maxdepth 1 -name 'initramfs-[0-9]*.img' ! -name '*-rescue*' -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
        if [ -z "$initrd_file" ]; then
             # Fallback to generic names
             initrd_file=$(find /boot -maxdepth 1 \( -name 'initrd.img' -o -name 'initrd' -o -name 'initramfs-linux.img' \) -printf '%T@ %p\n' | sort -nr | head -n 1 | cut -d' ' -f2-)
            if [ -z "$initrd_file" ]; then
                echo "[ERROR] Could not find a suitable initrd/initramfs file in /boot."
                exit 1
            fi
            echo "[WARNING] Could not find versioned initrd/initramfs, using generic: $initrd_file"
        fi
    fi

    echo "--> Using Initrd: $initrd_file"
    # Use run_privileged helper for the copy
    if ! run_privileged cp "$initrd_file" "$live_dir/initrd.img"; then
        echo "[ERROR] Failed to copy initrd file '$initrd_file' to '$live_dir/initrd.img'."
        exit 1
    fi

    # Set permissions (can usually be done by user if files were copied successfully)
    chmod 644 "$live_dir/vmlinuz" "$live_dir/initrd.img"

    echo "Kernel and initrd files copied successfully:"
    ls -lh "$live_dir/vmlinuz" "$live_dir/initrd.img"
}

download_bootfiles() {
    local iso_build_dir="$1" # Use the full path passed from main
    step_marker "Step 5: Downloading and Extracting Boot Files"

    echo "Build Directory: $iso_build_dir"
    local temp_dir
    temp_dir=$(mktemp -d /tmp/bootfiles_dl_XXXXXX) # Use mktemp for safety

    echo "--> Downloading BOOTFILES.tar.gz from $BOOTFILES_URL..."
    # Use wget with progress bar. set -e handles failure.
    if ! wget --progress=bar:force:noscroll "$BOOTFILES_URL" -O "$temp_dir/BOOTFILES.tar.gz"; then
        echo "[ERROR] Failed to download bootfiles from $BOOTFILES_URL"
        rm -rf "$temp_dir" # Clean up temp dir
        exit 1
    fi

    echo "--> Extracting bootfiles to $iso_build_dir..."
    # Use tar. set -e handles failure.
    if ! tar -xzf "$temp_dir/BOOTFILES.tar.gz" -C "$iso_build_dir/"; then
        echo "[ERROR] Failed to extract bootfiles from $temp_dir/BOOTFILES.tar.gz"
        rm -rf "$temp_dir"
        exit 1
    fi

    # Clean up downloaded tarball and temp dir
    echo "--> Cleaning up temporary download files..."
    rm -rf "$temp_dir"

    # Verify essential boot directories exist now
    if [ ! -d "$iso_build_dir/isolinux" ] || [ ! -d "$iso_build_dir/boot/grub" ]; then
        echo "[WARNING] Expected boot directories (isolinux, boot/grub) not found after extracting BOOTFILES.tar.gz."
        echo "Booting might fail if these aren't provided correctly."
    else
        echo "--> Essential boot directories (isolinux, boot/grub) seem present."
    fi
    echo "Bootfiles downloaded and extracted."
}

configure_efi_boot() {
    local iso_build_dir="$1" # Use the full path passed from main
    step_marker "Step 6: Configuring UEFI Boot"

    echo "Build Directory: $iso_build_dir"
    # Ensure base directories exist (might be redundant if download worked)
    mkdir -p "$iso_build_dir/EFI/boot"
    mkdir -p "$iso_build_dir/boot/grub" # Needed for grub.cfg later

    local grub_efi_target="$iso_build_dir/EFI/boot/bootx64.efi"
    local grub_efi_source=""

    echo "--> Searching for a suitable GRUB EFI bootloader (bootx64.efi)..."
    # Define potential locations for the GRUB EFI binary
    local potential_grub_paths=(
        "/usr/lib/grub/x86_64-efi/grubx64.efi"           # Common location (sometimes core.efi)
        "/usr/lib/grub/x86_64-efi-signed/grubx64.efi"   # Signed version (Ubuntu)
        "/usr/lib/grub/x86_64-efi/core.efi"             # Alternative name
        "/boot/efi/EFI/debian/grubx64.efi"              # Installed Debian/Ubuntu
        "/boot/efi/EFI/ubuntu/grubx64.efi"              # Installed Ubuntu alternate
        "/boot/efi/EFI/fedora/grubx64.efi"              # Installed Fedora
        "/boot/efi/EFI/BOOT/BOOTX64.EFI"                # Fallback on existing ESP
    )

    for path in "${potential_grub_paths[@]}"; do
        if [ -f "$path" ]; then
            grub_efi_source="$path"
            echo "--> Found GRUB EFI binary at: $grub_efi_source"
            break
        fi
    done

    # Copy or generate the GRUB EFI binary
    if [ -n "$grub_efi_source" ]; then
        echo "--> Copying GRUB EFI binary to $grub_efi_target..."
        # Copy doesn't usually need root if target is user-writable
        cp "$grub_efi_source" "$grub_efi_target"
        if [ $? -ne 0 ]; then
             echo "[ERROR] Failed to copy GRUB EFI binary from $grub_efi_source."
             exit 1
        fi
    else
        echo "[INFO] GRUB EFI binary not found in common locations. Attempting to generate one using grub-mkimage..."
        if command -v grub-mkimage &>/dev/null; then
            echo "--> Running grub-mkimage..."
            # Ensure required grub modules are installed (e.g., grub-efi-amd64-bin on Debian)
            # The modules included here are fairly standard for ISO booting.
            # set -e handles grub-mkimage failure
            # grub-mkimage itself doesn't usually require root, unless accessing restricted module paths
            if ! grub-mkimage \
                -o "$grub_efi_target" \
                -O x86_64-efi \
                -p "/boot/grub" \
                part_gpt part_msdos fat iso9660 \
                ntfs ext2 linuxefi chain boot \
                configfile normal search search_fs_uuid search_fs_file search_label \
                gfxterm gfxterm_background png jpeg gettext \
                echo videotest videoinfo ls keystatus progress \
                all_video test loadenv sleep \
                font terminal true date cat help configfile \
                regexp read cpuid halt reboot; then
                echo "[ERROR] grub-mkimage failed. Cannot create EFI bootloader."
                echo "Ensure GRUB EFI tools and modules are installed (e.g., grub-efi-amd64-bin, grub2-efi-x64-modules)."
                exit 1
            fi
            echo "--> GRUB EFI binary generated successfully."
        else
            echo "[ERROR] Cannot find existing GRUB EFI binary and 'grub-mkimage' command is not found."
            echo "[ERROR] Cannot proceed with UEFI boot configuration."
            echo "Please install GRUB EFI tools (e.g., grub-efi-amd64-bin, grub2-efi-x64-modules)."
            exit 1
        fi
    fi

    # --- EFI Boot Image (El Torito FAT filesystem for UEFI) ---
    local efi_img_path="$iso_build_dir/EFI/boot/efi.img"
    local efi_img_size=64 # Size in MiB (should be sufficient for bootloader)
    local efi_mount_point="" # Define variable scope

    echo "--> Creating EFI boot image ($efi_img_path, ${efi_img_size}MiB)..."
    rm -f "$efi_img_path" # Remove previous if exists
    # Use dd with progress status - doesn't need root if target dir is writable
    if ! dd if=/dev/zero of="$efi_img_path" bs=1M count=$efi_img_size status=progress; then
        echo "[ERROR] Failed to create blank EFI image file using dd."
        exit 1
    fi

    # Format the image as FAT32 - mkfs.vfat might require root depending on implementation/permissions
    # *** THIS IS THE CORRECTED LINE ***
    if ! run_privileged mkfs.vfat -F 32 -n "EFI_BOOT" "$efi_img_path"; then
         echo "[ERROR] Failed to format EFI image file as FAT32 using mkfs.vfat."
         exit 1
    fi

    echo "--> Mounting EFI image and copying bootloader..."
    efi_mount_point=$(mktemp -d /tmp/efi_img_mount_XXXXXX)

    # Use run_privileged helper to mount the loop device
    if ! run_privileged mount -o loop "$efi_img_path" "$efi_mount_point"; then
        echo "[ERROR] Failed to mount EFI image $efi_img_path at $efi_mount_point."
        rm -rf "$efi_mount_point" # Clean up mount point dir
        exit 1
    fi

    # Use run_privileged helper to create directory and copy within the mounted image
    if ! run_privileged mkdir -p "$efi_mount_point/EFI/BOOT"; then
        echo "[ERROR] Failed to create /EFI/BOOT directory inside the mounted EFI image."
        run_privileged umount "$efi_mount_point" # Attempt unmount
        rm -rf "$efi_mount_point"
        exit 1
    fi

    if [ -f "$grub_efi_target" ]; then
        # UEFI standard path is /EFI/BOOT/BOOTX64.EFI (case-insensitive on FAT)
        if ! run_privileged cp "$grub_efi_target" "$efi_mount_point/EFI/BOOT/BOOTX64.EFI"; then
            echo "[ERROR] Failed to copy $grub_efi_target into the EFI image."
            run_privileged umount "$efi_mount_point" # Attempt unmount
            rm -rf "$efi_mount_point"
            exit 1
        fi
        echo "--> Copied $grub_efi_target to EFI image as /EFI/BOOT/BOOTX64.EFI."
    else
        # This case should ideally not be reached due to earlier checks/exit
        echo "[ERROR] GRUB EFI binary ($grub_efi_target) is missing. Cannot copy into EFI image."
        run_privileged umount "$efi_mount_point" # Attempt unmount
        rm -rf "$efi_mount_point"
        exit 1
    fi

    echo "--> Unmounting EFI image..."
    # Use run_privileged helper to unmount
    if ! run_privileged umount "$efi_mount_point"; then
         echo "[WARNING] Failed to unmount EFI image cleanly from $efi_mount_point. Continuing, but check for stale mounts."
    fi
    rm -rf "$efi_mount_point" # Clean up mount point directory itself

    echo "EFI boot image created and configured at $efi_img_path"
}

generate_boot_configs() {
    local iso_build_dir="$1" # Use the full path passed from main
    local iso_name_pretty="$2" # Pretty name for menus
    step_marker "Step 7: Generating Bootloader Configuration Files"

    echo "Build Directory: $iso_build_dir"
    # These filenames are now fixed based on copy_kernel_initrd
    local VMLINUZ_PATH="/live/vmlinuz"
    local INITRD_PATH="/live/initrd.img"

    echo "--> Creating directories if they don't exist..."
    mkdir -p "$iso_build_dir/boot/grub"
    mkdir -p "$iso_build_dir/isolinux"

    # --- Generate grub.cfg ---
    local grub_cfg_path="$iso_build_dir/boot/grub/grub.cfg"
    echo "--> Generating $grub_cfg_path (for UEFI boot)..."
    cat > "$grub_cfg_path" <<EOF
# GRUB configuration for $iso_name_pretty Live ISO (UEFI)

set default="0"
set timeout=15
set timeout_style=menu

# Improve presentation if theme files are available
# Make sure theme files are included in BOOTFILES.tar.gz or copied separately
# Example using a potential theme:
# if loadfont /boot/grub/fonts/unicode.pf2 ; then
#   set gfxmode=auto
#   insmod all_video
#   insmod gfxterm
#   terminal_output gfxterm
#   if [ -f /boot/grub/themes/mytheme/theme.txt ]; then
#      set theme=/boot/grub/themes/mytheme/theme.txt
#      echo "Theme set"
#   elif [ -f /boot/grub/splash.png ]; then
#      background_image /boot/grub/splash.png
#      echo "Background image set"
#   fi
# fi

menuentry "$iso_name_pretty - Live Boot" --class gnu-linux --class gnu --class os {
    echo "Loading Linux kernel: $VMLINUZ_PATH ..."
    # 'boot=live' is common for Debian/Ubuntu live-boot. Arch uses 'archiso'.
    # Adjust 'boot=' parameter if using a different live system framework (e.g., dracut might not need it explicitly if configured).
    # 'quiet splash' hides boot messages and shows splash screen (if configured).
    # '---' is sometimes used as a separator for init arguments, can often be omitted.
    linux $VMLINUZ_PATH boot=live quiet splash ---
    echo "Loading initial ramdisk: $INITRD_PATH ..."
    initrd $INITRD_PATH
}

menuentry "$iso_name_pretty - Live Boot (Debug)" --class gnu-linux --class gnu --class os {
    echo "Loading Linux kernel: $VMLINUZ_PATH (Debug Mode)..."
    # Remove quiet/splash for verbose output. 'noprompt' 'noeject' are sometimes useful.
    linux $VMLINUZ_PATH boot=live noprompt noeject ---
    echo "Loading initial ramdisk: $INITRD_PATH ..."
    initrd $INITRD_PATH
}

menuentry "$iso_name_pretty - Live Boot (Copy to RAM)" --class gnu-linux --class gnu --class os {
    echo "Loading Linux kernel: $VMLINUZ_PATH (Copy to RAM)..."
    # 'toram' option (if supported by initramfs) copies the squashfs to RAM for potentially faster operation after boot.
    linux $VMLINUZ_PATH boot=live toram quiet splash ---
    echo "Loading initial ramdisk: $INITRD_PATH ..."
    initrd $INITRD_PATH
}

# Persistence example - requires manual setup on the USB drive after writing ISO.
# A partition or file labeled 'persistence' (or as configured in live-config) is needed.
# menuentry "$iso_name_pretty - Live with Persistence" --class gnu-linux --class gnu --class os {
#      echo "Loading Linux kernel: $VMLINUZ_PATH (with Persistence)..."
#      linux $VMLINUZ_PATH boot=live persistence persistence-read-only quiet splash ---
#      echo "Loading initial ramdisk: $INITRD_PATH ..."
#      initrd $INITRD_PATH
# }

# Optional: Memtest (if memtest binary is included, e.g., at /boot/memtest86+.bin)
# if [ -f /boot/memtest86+.bin ]; then
#    menuentry "Memory Test (memtest86+)" --class memory --class test {
#        echo "Loading memtest86+..."
#        linux16 /boot/memtest86+.bin
#    }
# fi

# Optional: Chainload Windows (if detected)
# menuentry "Boot Windows (if installed)" --class windows --class os {
#      search --fs-uuid --no-floppy --set=root XXXX-XXXX # Replace with Windows EFI partition UUID
#      chainloader (\${root})/EFI/Microsoft/Boot/bootmgfw.efi
# }

menuentry "System shutdown" --class shutdown {
	echo "System shutting down..."
	halt
}

menuentry "System restart" --class reboot {
	echo "System rebooting..."
	reboot
}
EOF
    echo "--> $grub_cfg_path generated."

    # --- Generate isolinux.cfg ---
    local isolinux_cfg_path="$iso_build_dir/isolinux/isolinux.cfg"
    echo "--> Generating $isolinux_cfg_path (for BIOS boot)..."
    # Ensure vesamenu.c32, libutil.c32, etc. and splash.png are present from BOOTFILES.tar.gz or syslinux install
    cat > "$isolinux_cfg_path" <<EOF
# ISOLINUX configuration for $iso_name_pretty Live ISO (BIOS)

# Use the vesamenu graphical boot menu
UI vesamenu.c32
# Alternatively, use simple text menu:
# UI menu.c32

# Default boot entry label
DEFAULT live

# Prompt user? (0 = no, 1 = yes)
PROMPT 0
# Timeout in 1/10ths of a second (150 = 15 seconds)
TIMEOUT 150

# Menu Look and Feel (requires vesamenu.c32)
MENU TITLE $iso_name_pretty Live Boot Menu
# MENU BACKGROUND /isolinux/splash.png  # Uncomment and ensure splash.png exists
MENU COLOR screen        37;40    #80ffffff #00000000 std
MENU COLOR border        30;44    #40000000 #00000000 std
MENU COLOR title         1;36;44  #c0ffffff #00000000 std
MENU COLOR unsel         37;44    #90ffffff #00000000 std
MENU COLOR hotkey        1;37;44  #ffffffff #00000000 std
MENU COLOR sel           7;37;40  #e0ffffff #20ffffff all
MENU COLOR hotsel        1;7;37;40 #e0ffffff #20ffffff all
MENU COLOR disabled      1;30;44  #60cccccc #00000000 std
MENU COLOR scrollbar     30;44    #40000000 #00000000 std
MENU TABMSG Press [Tab] to edit options, [F1] for Help Menu

LABEL live
    MENU LABEL ^Live Boot - $iso_name_pretty
    MENU DEFAULT
    KERNEL $VMLINUZ_PATH
    # Adjust APPEND line based on your live system framework
    APPEND initrd=$INITRD_PATH boot=live quiet splash ---

LABEL debug
    MENU LABEL Live Boot (^Debug Mode)
    KERNEL $VMLINUZ_PATH
    APPEND initrd=$INITRD_PATH boot=live noprompt noeject ---

LABEL toram
    MENU LABEL Live Boot (^Copy to RAM)
    KERNEL $VMLINUZ_PATH
    APPEND initrd=$INITRD_PATH boot=live toram quiet splash ---

# LABEL persistence
#    MENU LABEL Live Boot with ^Persistence
#    KERNEL $VMLINUZ_PATH
#    APPEND initrd=$INITRD_PATH boot=live persistence persistence-read-only quiet splash ---

# Optional: Memtest (ensure memtest binary path is correct)
# LABEL memtest
#    MENU LABEL ^Memory Test (memtest86+)
#    KERNEL /boot/memtest86+.bin

# Optional: Hardware Detection Tool (ensure hdt.c32 path is correct)
# LABEL hdt
#    MENU LABEL ^Hardware Detection Tool (HDT)
#    COM32 hdt.c32

LABEL local
   MENU LABEL Boot from first ^hard disk
   # LOCALBOOT 0x80 attempts to boot MBR of first disk
   # LOCALBOOT -1 might sometimes work better depending on BIOS
   LOCALBOOT 0x80

# You can add F1 help screen links here if you create help files (e.g., F1 help.txt)

EOF
    echo "--> $isolinux_cfg_path generated."
    echo "Boot configuration files generated."
}

create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"
    step_marker "Step 8: Creating the Final ISO Image"

    echo "Source Directory : $source_dir"
    echo "Output ISO File  : $output_file"
    echo "ISO Volume ID    : $iso_label"

    # --- Pre-creation Checks ---
    echo "--> Verifying required files and directories for ISO creation..."
    local check_failed=0
    local required_items=(
        "$source_dir/live/filesystem.squashfs" # Must exist
        "$source_dir/live/vmlinuz"             # Must exist
        "$source_dir/live/initrd.img"          # Must exist
        "$source_dir/isolinux/isolinux.bin"    # BIOS bootloader
        "$source_dir/isolinux/isolinux.cfg"    # BIOS menu config
        "$source_dir/isolinux/vesamenu.c32"    # BIOS graphical menu (if used in cfg)
        "$source_dir/boot/grub/grub.cfg"       # UEFI menu config
        "$source_dir/EFI/boot/efi.img"         # UEFI FAT ESP image
        "$source_dir/EFI/boot/bootx64.efi"     # UEFI bootloader (inside source_dir, copied into efi.img earlier)
    )
    for item in "${required_items[@]}"; do
        if [ ! -e "$item" ]; then # Use -e to check for file or directory
            echo "[ERROR] Required file/directory not found: $item"
            check_failed=1
        fi
    done

    # Check for isohybrid MBR file separately, try to copy if missing
    local isohybrid_mbr_path="$source_dir/isolinux/isohdpfx.bin"
    if [ ! -f "$isohybrid_mbr_path" ]; then
        echo "[WARNING] isohybrid MBR file not found at $isohybrid_mbr_path."
        # Try to find it from syslinux installation
        local syslinux_mbr_found=$(find /usr/lib/syslinux/mbr /usr/share/syslinux /usr/lib/ISOLINUX -name 'isohdpfx.bin' -print -quit)
        if [ -n "$syslinux_mbr_found" ] && [ -f "$syslinux_mbr_found" ]; then
             echo "--> Found isohdpfx.bin at $syslinux_mbr_found, copying..."
             mkdir -p "$source_dir/isolinux" # Ensure dir exists
             cp "$syslinux_mbr_found" "$isohybrid_mbr_path"
             if [ ! -f "$isohybrid_mbr_path" ]; then # Verify copy worked
                 echo "[ERROR] Failed to copy isohdpfx.bin. Cannot create hybrid MBR."
                 check_failed=1
             fi
         else
             echo "[ERROR] Could not find isohdpfx.bin on the system either (searched /usr/lib/syslinux, /usr/share/syslinux, /usr/lib/ISOLINUX)."
             echo "[ERROR] Cannot create a hybrid ISO bootable from USB via BIOS MBR."
             check_failed=1
        fi
    fi

    if [ "$check_failed" -eq 1 ]; then
        echo "[ERROR] Aborting ISO creation due to missing essential files/directories."
        echo "Please check the build directory ($source_dir) and previous step outputs."
        exit 1
    fi
    echo "--> All essential files/directories seem present."

    echo "--> Running xorriso to create the hybrid ISO image..."
    # Use xorriso to create the ISO. set -e handles failure.
    # xorriso itself doesn't typically need root unless writing to a restricted path.
    # We assume output_file is in a user-writable location ($HOME or /root).
    if ! xorriso -as mkisofs \
        -iso-level 3 `# Allow long Joliet filenames` \
        -full-iso9660-filenames `# Allow 31 char ISO9660 names` \
        -joliet `# Include Joliet extensions for Windows compatibility` \
        -rock `# Include Rock Ridge extensions for Linux/Unix compatibility` \
        -volid "$iso_label" `# Volume ID (max 32 chars)` \
        -appid "Custom Live ISO" \
        -publisher "User Script" \
        -preparer "Built by $(whoami) on $(hostname) at $(date)" \
        \
        `# BIOS Boot settings (ISOLINUX)` \
        -b isolinux/isolinux.bin `# Boot image file` \
        -c isolinux/boot.cat `# Boot catalog file (generated)` \
        -no-emul-boot `# Boot image is not a floppy/disk emulation` \
        -boot-load-size 4 `# Number of 512-byte sectors to load` \
        -boot-info-table `# Patch isohybrid info into the boot image` \
        -isohybrid-mbr "$isohybrid_mbr_path" `# Use this MBR for USB boot compatibility` \
        \
        `# UEFI Boot settings (El Torito FAT image)` \
        -eltorito-alt-boot \
        -e EFI/boot/efi.img `# Path to the EFI FAT image` \
        -no-emul-boot `# EFI image is not emulated` \
        -isohybrid-gpt-basdat `# Create a Protective MBR + GPT for UEFI boot` \
        \
        `# Output file` \
        -o "$output_file" \
        \
        `# Source Directory (must be the last argument)` \
        "$source_dir"; then
        echo "[ERROR] xorriso failed to create the ISO image."
        echo "Check the xorriso output above for details."
        exit 1
    fi

    echo "--> xorriso completed successfully."

    # Optional: Add checksum
    echo "--> Generating MD5 checksum..."
    if md5sum "$output_file" > "$output_file.md5"; then
        echo "MD5 checksum saved to $output_file.md5"
    else
        echo "[WARNING] Failed to generate MD5 checksum."
    fi

    echo ""
    echo "------------------------------------------------------------------------------"
    echo ">>> ISO Creation Successful! <<<"
    echo "------------------------------------------------------------------------------"
    echo " Output ISO : $output_file"
    echo " Checksum   : $output_file.md5"
    echo " Size       : $(ls -lh "$output_file" | awk '{print $5}')"
    echo "------------------------------------------------------------------------------"
    echo "You can now burn this ISO to a DVD or write it to a USB drive using tools like"
    echo "'dd', 'Rufus', 'Ventoy', 'balenaEtcher', etc."
    echo "(Example using dd: run_privileged dd if=$output_file of=/dev/sdX bs=4M status=progress oflag=sync )"
    echo "** Be EXTREMELY careful when using dd to select the correct output device (/dev/sdX) **"
    echo "------------------------------------------------------------------------------"

    return 0 # Explicitly return 0 on success
}

cleanup() {
    local iso_build_dir=$1
    step_marker "Cleanup Phase"
    echo "The build directory is located at: $iso_build_dir"

    # Safety check: Ensure the path is under $HOME or /tmp or /root (if root) and not root / or critical system path
    local safe_to_clean=0
    if [[ -n "$iso_build_dir" && "$iso_build_dir" != "/" && -d "$iso_build_dir" ]]; then
        # Allow cleaning if it's under HOME, /tmp, or /root (and we are root)
        if [[ "$iso_build_dir" == "$HOME/"* ]] || [[ "$iso_build_dir" == "/tmp/"* ]] || [[ "$EUID" -eq 0 && "$iso_build_dir" == "/root/"* ]]; then
            safe_to_clean=1
        fi
    fi

    if [[ "$safe_to_clean" -eq 1 ]]; then
       read -p "Do you want to remove the build directory ($iso_build_dir)? (y/N): " confirm_cleanup
       if [[ "$confirm_cleanup" =~ ^[Yy]$ ]]; then
           echo "--> Removing build directory: $iso_build_dir ..."
           # rm -rf usually doesn't need root if the user owns the dir (e.g., under $HOME)
           # If run as root, root can remove it anyway.
           rm -rf "$iso_build_dir"
           if [ $? -eq 0 ]; then
               echo "--> Build directory removed successfully."
           else
               echo "[WARNING] Failed to remove the build directory completely. Manual cleanup might be required."
               echo "Check permissions within $iso_build_dir"
           fi
       else
           echo "--> Skipping cleanup. Build directory preserved."
       fi
    else
        echo "[WARNING] Skipping automatic cleanup prompt due to potentially unsafe or non-standard path: $iso_build_dir"
        echo "Please check and clean up manually if needed."
    fi
}


# ==============================================================================
# Main script execution
# ==============================================================================
main() {
    echo "##################################################"
    echo "### Custom Linux Live ISO Creator Script       ###"
    echo "##################################################"
    echo "### WARNING: This script clones the running    ###"
    echo "###          host system, potentially including###"
    echo "###          sensitive data and configuration. ###"
    echo "###          USE CAUTION!                      ###"
    echo "##################################################"
    echo "### MODIFICATION WARNING: The check preventing ###"
    echo "### root execution has been removed. Running   ###"
    echo "### this script as root carries increased risk.###"
    echo "##################################################"
    echo ""

    # ======================================================================== #
    # === ROOT EXECUTION CHECK REMOVED ===
    # The original check preventing root execution has been commented out/removed
    # as per the user request. This is NOT recommended for safety.
    #
    # Original check was:
    # if [ "$EUID" -eq 0 ]; then
    #     echo "[ERROR] Please do not run this script as root."
    #     echo "It will use 'sudo' internally for commands that require elevated privileges."
    #     exit 1
    # fi
    # ======================================================================== #

    # Check if sudo is available (Still useful if script is NOT run as root)
    if [ "$EUID" -ne 0 ] && ! command -v sudo &> /dev/null; then
        echo "[ERROR] 'sudo' command not found. This script requires sudo access if not run as root."
        exit 1
    fi
    # Verify the user has sudo privileges (Only relevant if NOT run as root)
    # We skip the `sudo -v` check here as it might require interaction and is less critical
    # if the user explicitly decided to run as root or non-root. The internal `run_privileged`
    # function will handle sudo prompting if needed and possible.


    # === Phase 1: Setup and Preparation ===
    install_dependencies
    regenerate_host_initramfs # Includes prompt and strong warnings

    # === Phase 2: Configuration ===
    step_marker "Step 2b: ISO Configuration"
    # Get ISO name
    local iso_name=""
    while [ -z "$iso_name" ]; do
        read -p "Enter a base name for your ISO (e.g., MyCustomLive, no spaces): " iso_name
        # Basic sanitization: remove leading/trailing whitespace, replace spaces with underscores
        iso_name=$(echo "$iso_name" | sed 's/^[ \t]*//;s/[ \t]*$//' | tr -s ' ' '_')
        if [ -z "$iso_name" ]; then
            echo "[ERROR] ISO name cannot be empty."
        elif [[ "$iso_name" =~ [^a-zA-Z0-9_.-] ]]; then
             echo "[ERROR] ISO name contains invalid characters. Use only letters, numbers, underscore, dot, hyphen."
             iso_name="" # Reset to re-prompt
        fi
    done

    # Define build directory and output file within user's home directory (or root's home if run as root)
    local build_base="$HOME"
    if [ "$EUID" -eq 0 ]; then
        # If running as root, use /root.
        build_base="/root"
        echo "[INFO] Running as root. Build directory and ISO will be placed under /root."
    fi
    local iso_build_dir="${build_base}/ISO_BUILD_${iso_name}" # Make build dir name distinct
    local output_iso_file="${build_base}/${iso_name}.iso" # Final ISO path

    # Create a sanitized volume label (uppercase, limited chars/length for ISO standard)
    local iso_vol_label=$(echo "$iso_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_' | cut -c1-32)
    if [ -z "$iso_vol_label" ]; then
        iso_vol_label="LINUX_LIVE" # Fallback label
    fi

    echo "--- Configuration Summary ---"
    echo " ISO Base Name     : $iso_name"
    echo " ISO Volume ID     : $iso_vol_label"
    echo " Build Directory   : $iso_build_dir"
    echo " Output ISO File   : $output_iso_file"
    echo "---------------------------"

    # Check for existing build directory or ISO file
    if [ -d "$iso_build_dir" ]; then
        read -p "[WARNING] Build directory '$iso_build_dir' already exists. Overwrite? (y/N): " confirm_overwrite_build
        if [[ "$confirm_overwrite_build" =~ ^[Yy]$ ]]; then
            echo "--> Removing existing build directory..."
            # Root can remove anything, user needs write permission
            rm -rf "$iso_build_dir"
        else
            echo "Aborting."
            exit 1
        fi
    fi
     if [ -f "$output_iso_file" ]; then
        read -p "[WARNING] Output ISO file '$output_iso_file' already exists. Overwrite? (y/N): " confirm_overwrite_iso
        if [[ ! "$confirm_overwrite_iso" =~ ^[Yy]$ ]]; then
            echo "Aborting. Please rename the existing ISO or choose a different name."
            exit 1
        fi
        # No need to remove here, xorriso will overwrite
     fi


    # === Phase 3: Build Steps ===
    # 'set -e' ensures script stops automatically if any step below fails

    # Ensure build dir exists before starting steps that write to it
    mkdir -p "$iso_build_dir"

    create_squashfs "$iso_build_dir"
    copy_kernel_initrd "$iso_build_dir"
    download_bootfiles "$iso_build_dir"
    configure_efi_boot "$iso_build_dir" # Includes creating efi.img
    generate_boot_configs "$iso_build_dir" "$iso_name" # Pass pretty name

    # === Phase 4: Final ISO Creation ===
    echo ""
    read -p "All build steps completed. Proceed with final ISO creation? (y/N): " confirm_create
    if [[ "$confirm_create" =~ ^[Yy]$ ]]; then
        create_iso "$iso_build_dir" "$output_iso_file" "$iso_vol_label"
        local create_status=$? # Capture exit status

        # === Phase 5: Cleanup ===
        if [ $create_status -eq 0 ]; then
             cleanup "$iso_build_dir" # Ask user about cleanup
        else
             echo "[ERROR] ISO creation failed. (Exit code: $create_status)"
             echo "Build directory ($iso_build_dir) has been preserved for inspection."
             exit 1 # Ensure script exits with error status
        fi
    else
        echo "ISO creation cancelled by user."
        # Ask about cleanup even if cancelled
        cleanup "$iso_build_dir"
        exit 0 # Exit cleanly on user cancellation
    fi

    echo ""
    echo "Script finished successfully."
    exit 0
}

# --- Run Main Function ---
# Pass any script arguments (though none are currently used by main)
main "$@"
