#!/bin/bash

# Combined ISO Creation Script with Bootfile Download
# Creates BIOS+UEFI bootable ISO from directory structure
# WARNING: This script clones the running host system, which is generally NOT
#          the recommended way to build a clean, portable live ISO. It may
#          include host-specific configurations and sensitive data.
#          Consider using a chroot-based build process (e.g., with debootstrap)
#          for a proper live system build.

# --- Helper Functions ---
detect_pkg_manager() {
    if [ -x "$(command -v apt-get)" ]; then echo "apt";
    elif [ -x "$(command -v dnf)" ]; then echo "dnf";
    elif [ -x "$(command -v yum)" ]; then echo "yum";
    elif [ -x "$(command -v pacman)" ]; then echo "pacman";
    else echo "unknown"; fi
}

install_pkg() {
    local pkg_manager=$1
    shift
    local packages=("$@")
    echo "Installing: ${packages[*]}"
    case "$pkg_manager" in
        apt) sudo apt-get update && sudo apt-get install -y "${packages[@]}" ;;
        dnf) sudo dnf install -y "${packages[@]}" ;;
        yum) sudo yum install -y "${packages[@]}" ;;
        pacman) sudo pacman -S --noconfirm "${packages[@]}" ;;
        *) echo "ERROR: Unsupported package manager for installing $package"; return 1 ;;
    esac
}

# --- Script Functions ---

install_dependencies() {
    echo "Detecting package manager and installing dependencies..."
    local pm
    pm=$(detect_pkg_manager)

    local core_pkgs=(xorriso isolinux syslinux-utils mtools wget squashfs-tools)
    local grub_efi_pkg=""
    local live_pkgs=() # Packages needed for the initramfs to boot live

    case "$pm" in
        apt)
            grub_efi_pkg="grub-efi-amd64-bin"
            # live-boot is common for Debian/Ubuntu derivatives
            live_pkgs=(live-boot live-config) # Add others if needed (e.g., live-tools)
            core_pkgs+=(syslinux) # syslinux-utils might not pull syslinux itself
            ;;
        dnf | yum)
            grub_efi_pkg="grub2-efi-x64"
             # Dracut is common for Fedora/RHEL derivatives. Needs configuration.
             # Installation alone might not be enough. Dracut needs to be run.
             live_pkgs=(dracut-live)
             core_pkgs+=(syslinux)
            ;;
        pacman)
            grub_efi_pkg="grub"
            # Arch uses mkinitcpio. Hooks need to be added to /etc/mkinitcpio.conf
            # e.g., add 'archiso' to HOOKS=(...) and install 'archiso' package
            live_pkgs=(archiso) # Or just ensure mkinitcpio hooks are correct
            core_pkgs+=(syslinux)
            ;;
        *)
            echo "ERROR: Could not detect package manager to install dependencies."
            exit 1
            ;;
    esac

    # Combine all packages
    local all_pkgs=("${core_pkgs[@]}" "$grub_efi_pkg" "${live_pkgs[@]}")
    # Remove empty elements just in case
    all_pkgs=(${all_pkgs[@]})

    if ! install_pkg "$pm" "${all_pkgs[@]}"; then
        echo "ERROR: Failed to install dependencies."
        exit 1
    fi
    echo "Dependencies installed."
}

# NEW function to attempt regeneration of host initramfs
# WARNING: Modifies your host system's boot configuration!
regenerate_host_initramfs() {
    echo "Attempting to regenerate host initramfs to include live-boot capabilities..."
    echo "WARNING: This modifies your current system's initramfs!"
    local pm
    pm=$(detect_pkg_manager)

    case "$pm" in
        apt)
            echo "Running update-initramfs..."
            sudo update-initramfs -u -k all
            ;;
        dnf | yum)
            echo "Running dracut..."
            # Ensure /etc/dracut.conf or /etc/dracut.conf.d/ includes needed modules
            # e.g., add_dracut_modules+=" dmsquash-live "
            sudo dracut --force --regenerate-all
            ;;
        pacman)
            echo "Running mkinitcpio..."
            # Ensure /etc/mkinitcpio.conf HOOKS line includes 'archiso' or similar
            sudo mkinitcpio -P
            ;;
        *)
            echo "WARNING: Cannot automatically regenerate initramfs for this system."
            echo "Please ensure your initramfs includes live boot support manually."
            read -p "Press Enter to continue anyway, or Ctrl+C to abort."
            ;;
    esac
    local result=$?
    if [ $result -ne 0 ]; then
         echo "ERROR: Failed to regenerate initramfs. The ISO might not boot correctly."
         # Decide whether to exit or continue
         read -p "Press Enter to continue despite the error, or Ctrl+C to abort."
    fi
    echo "Initramfs regeneration attempted."
}


create_squashfs() {
    local iso_name="$1"
    local iso_dir="/home/$iso_name" # Consider using /tmp or a build specific dir
    echo "Creating filesystem.squashfs..."

    # Create target directory if it doesn't exist
    mkdir -p "$iso_dir/live"

    # --- Improved Exclusions ---
    # Add more host-specific things and potentially large/unneeded data
    local exclusions=(
        /dev/*
        /proc/*
        /sys/*
        /tmp/*
        /run/*
        /mnt/*
        /media/*
        /lost+found
        /var/tmp/*
        /var/log/* # Logs are usually not needed/wanted
        /var/cache/apt/archives/*.deb # Cleaned by apt clean usually, but good to exclude
        /var/lib/apt/lists/* # Regenerated on target
        /var/lib/pacman/sync/* # Pacman sync DBs
        /var/lib/dnf/* # DNF cache/history
        /var/lib/systemd/coredump/* # Coredumps
        /home/*/.bash_history
        /root/.bash_history
        /home/*/.cache/*
        /root/.cache/*
        /home/*/.local/share/Trash/*
        /root/.local/share/Trash/*
        "$iso_dir"             # Exclude the build directory itself!
        /home/*.iso            # Exclude any existing ISOs
        /usr/src/* # Kernel sources/headers often large
        /boot/*rescue*
        /boot/System.map*
        /boot/vmlinuz.old
        /swapfile              # Swap files/partitions
        /swap.img
        /etc/fstab             # Should be specific to live env or handled by initrd
        /etc/crypttab          # Specific to host encryption
        /etc/machine-id        # Should be generated on first boot of live system
        /etc/hostname          # Should be set for live system (e.g., 'ubuntu')
        /etc/hosts             # Often minimal in live system
        /etc/ssh/ssh_host_* # Host SSH keys should NOT be cloned
        /etc/NetworkManager/system-connections/* # Saved Wi-Fi passwords etc.
        # Add more exclusions as needed based on your host system
    )

    # Build the exclusion arguments for mksquashfs
    local mksquashfs_opts=()
    for item in "${exclusions[@]}"; do
        mksquashfs_opts+=(-e "$item")
    done

    echo "Creating filesystem.squashfs from / (this may take a while)..."
    echo "Excluding: ${exclusions[*]}"

    sudo mksquashfs / "$iso_dir/live/filesystem.squashfs" \
        -comp xz \
        -b 1048576 \
        -noappend \
        "${mksquashfs_opts[@]}"

    local squashfs_result=$?
    if [ $squashfs_result -ne 0 ]; then
        echo "Error creating squashfs filesystem"
        # Consider cleaning up $iso_dir here
        exit 1
    fi

    # Verify the squashfs file
    echo "Verifying squashfs file..."
    if ! unsquashfs -s "$iso_dir/live/filesystem.squashfs" > /dev/null; then
        echo "Error: Created squashfs file appears invalid"
        # Consider cleaning up $iso_dir here
        exit 1
    fi

    echo "filesystem.squashfs created successfully at $iso_dir/live/"
}

copy_kernel_initrd() {
    local iso_name="$1"
    local iso_dir="/home/$iso_name"

    echo "Copying kernel and initrd files from host /boot..."
    echo "Ensure the initramfs contains live-boot support!" # Added reminder

    mkdir -p "$iso_dir/live" # Ensure target exists

    # Find and copy vmlinuz (prefer non-generic)
    local vmlinuz_file
    vmlinuz_file=$(find /boot -maxdepth 1 -name 'vmlinuz-[0-9]*' -not -name '*-rescue-*' | sort -V | tail -n 1)
     if [ -z "$vmlinuz_file" ]; then
         # Fallback to generic name if specific version not found
         vmlinuz_file=$(find /boot -maxdepth 1 -name 'vmlinuz' | head -n 1)
         if [ -z "$vmlinuz_file" ]; then
            echo "Error: Could not find vmlinuz file in /boot"
            exit 1
         fi
     fi

    echo "Using Kernel: $vmlinuz_file"
    cp "$vmlinuz_file" "$iso_dir/live/vmlinuz"

    # Find and copy initrd (prefer non-generic)
    local initrd_file
    initrd_file=$(find /boot -maxdepth 1 -name 'initrd.img-[0-9]*' -not -name '*-rescue-*' | sort -V | tail -n 1)
    if [ -z "$initrd_file" ]; then
        # Try initramfs naming convention
        initrd_file=$(find /boot -maxdepth 1 -name 'initramfs-[0-9]*.img' -not -name '*-rescue-*' | sort -V | tail -n 1)
        if [ -z "$initrd_file" ]; then
             # Fallback to generic names
             initrd_file=$(find /boot -maxdepth 1 \( -name 'initrd.img' -o -name 'initrd' -o -name 'initramfs-linux.img' \) | head -n 1)
            if [ -z "$initrd_file" ]; then
                echo "Error: Could not find initrd/initramfs file in /boot"
                exit 1
            fi
        fi
    fi

    echo "Using Initrd: $initrd_file"
    cp "$initrd_file" "$iso_dir/live/initrd.img"

    chmod 644 "$iso_dir/live/vmlinuz" "$iso_dir/live/initrd.img"

    echo "Kernel and initrd files copied successfully:"
    echo " - $iso_dir/live/vmlinuz"
    echo " - $iso_dir/live/initrd.img"
}

download_bootfiles() {
    local iso_dir="$1"
    # Ensure this URL is still valid and provides compatible boot files
    local bootfiles_url="https://github.com/GlitchLinux/gLiTcH-ISO-Creator/blob/main/BOOTFILES.tar.gz?raw=true"
    local temp_dir
    temp_dir=$(mktemp -d /tmp/bootfiles_XXXXXX) # Use mktemp for safety

    echo "Downloading bootfiles from $bootfiles_url..."

    if ! wget --progress=bar:force:noscroll "$bootfiles_url" -O "$temp_dir/BOOTFILES.tar.gz"; then
        echo "Error: Failed to download bootfiles"
        rm -rf "$temp_dir"
        exit 1
    fi

    echo "Extracting bootfiles to $iso_dir..."
    if ! tar -xzf "$temp_dir/BOOTFILES.tar.gz" -C "$iso_dir/"; then
       echo "Error: Failed to extract bootfiles into $iso_dir"
       # Check if files were partially extracted and clean up if necessary
       rm -rf "$temp_dir"
       exit 1
    fi

    # Clean up downloaded tarball and temp dir
    # Note: Tar extraction might place files directly in $iso_dir, check tar contents
    # Assuming extraction places files in $iso_dir, not a subdirectory
    # rm -f "$iso_dir/BOOTFILES.tar.gz" # Might not be needed if extracted directly
    rm -rf "$temp_dir"

    # Verify essential boot files exist now
    if [ ! -d "$iso_dir/isolinux" ] || [ ! -d "$iso_dir/boot/grub" ]; then
        echo "Warning: Expected boot directories (isolinux, boot/grub) not found after extracting BOOTFILES.tar.gz"
    fi

    echo "Bootfiles processed."
}


configure_efi_boot() {
    local iso_dir="$1"
    local iso_name="$2" # iso_name is unused here, consider removing param
    echo "Configuring EFI boot..."

    # Ensure base directories exist from downloaded bootfiles or create them
    mkdir -p "$iso_dir/EFI/boot"
    mkdir -p "$iso_dir/boot/grub" # Needed for grub.cfg later

    local grub_efi_source=""
    local grub_efi_target="$iso_dir/EFI/boot/bootx64.efi"

    # Try standard locations first
    if [ -f /usr/lib/grub/x86_64-efi/grubx64.efi ]; then # Often named grubx64.efi
        grub_efi_source="/usr/lib/grub/x86_64-efi/grubx64.efi"
    elif [ -f /usr/lib/grub/x86_64-efi/core.efi ]; then
         grub_efi_source="/usr/lib/grub/x86_64-efi/core.efi"
    elif [ -f /boot/efi/EFI/debian/grubx64.efi ]; then # Common location on installed Debian/Ubuntu
        grub_efi_source="/boot/efi/EFI/debian/grubx64.efi"
    elif [ -f /boot/efi/EFI/fedora/grubx64.efi ]; then # Common location on installed Fedora
         grub_efi_source="/boot/efi/EFI/fedora/grubx64.efi"
    fi
    # Add more paths if needed for other distros

    if [ -n "$grub_efi_source" ]; then
        echo "Copying existing GRUB EFI binary from $grub_efi_source..."
        cp "$grub_efi_source" "$grub_efi_target"
    else
        echo "GRUB EFI binary not found in common locations, attempting to generate one..."
        if command -v grub-mkimage &>/dev/null; then
            # Ensure required grub modules are installed (e.g., grub-efi-amd64-bin on Debian)
            # Modules needed depend heavily on what grub.cfg does (filesystem support, gfx, etc.)
            grub-mkimage \
                -o "$grub_efi_target" \
                -O x86_64-efi \
                -p "/boot/grub" \
                # Add necessary modules. This list is a guess and might need adjustment.
                part_gpt part_msdos fat iso9660 \
                ntfs ext2 linuxefi chain boot \
                configfile normal search search_fs_uuid search_fs_file search_label \
                gfxterm gfxterm_background png jpeg gettext \
                echo videotest videoinfo ls keystatus \
                all_video # Usually safe bet for video

            if [ $? -ne 0 ]; then
                echo "ERROR: grub-mkimage failed. EFI boot might not work."
                # Don't exit, maybe user wants BIOS only or will fix manually
            else
                 echo "GRUB EFI binary generated."
            fi
        else
            echo "ERROR: Cannot find existing GRUB EFI binary and grub-mkimage command is not found."
            echo "EFI boot will likely fail. Please install GRUB EFI tools (e.g., grub-efi-amd64-bin, grub2-efi-x64-modules)."
             # Decide whether to exit or just warn
             # exit 1
        fi
    fi

    # --- EFI Boot Image (El Torito Boot Catalog Entry) ---
    # This 'efi.img' is used for the El Torito specification.
    # It doesn't necessarily contain the kernel/initrd itself for GRUB's default config,
    # but it *must* contain the EFI bootloader that GRUB will load.
    # The approach here creates a small FAT image just for the bootloader.
    # GRUB then uses its config file (on the main ISO filesystem) to find kernel/initrd.

    local efi_img_path="$iso_dir/EFI/boot/efi.img"
    local efi_img_size=64 # Size in MiB, adjust if needed (e.g., if storing more files)
    local efi_mount_point
    efi_mount_point=$(mktemp -d /tmp/efi_mount_XXXXXX)

    echo "Creating EFI boot image ($efi_img_size MiB)..."
    rm -f "$efi_img_path" # Remove previous if exists
    dd if=/dev/zero of="$efi_img_path" bs=1M count=$efi_img_size status=progress
    mkfs.vfat -F 32 -n "EFI_BOOT" "$efi_img_path"

    echo "Mounting EFI image and copying bootloader..."
    if ! sudo mount -o loop "$efi_img_path" "$efi_mount_point"; then
        echo "ERROR: Failed to mount EFI image loop device."
        rm -rf "$efi_mount_point"
        # Consider removing $efi_img_path
        exit 1
    fi

    sudo mkdir -p "$efi_mount_point/EFI/BOOT"

    # Copy the GRUB EFI binary INTO the EFI image
    if [ -f "$grub_efi_target" ]; then
        sudo cp "$grub_efi_target" "$efi_mount_point/EFI/BOOT/BOOTX64.EFI" # Standard path UEFI looks for
        echo "Copied $grub_efi_target to EFI image."
    else
        echo "WARNING: GRUB EFI binary ($grub_efi_target) not found to copy into EFI image. EFI boot will fail."
    fi

    # Optionally copy grub.cfg here too if GRUB is configured to look inside the ESP first
    # sudo mkdir -p "$efi_mount_point/boot/grub"
    # sudo cp "$iso_dir/boot/grub/grub.cfg" "$efi_mount_point/boot/grub/grub.cfg"

    sudo umount "$efi_mount_point"
    rm -rf "$efi_mount_point"

    echo "EFI boot image created and configured."
}

# Create the ISO
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local iso_label="$3"

    # --- Pre-checks ---
    echo "Verifying required files for ISO creation..."
    local missing_files=0
    if [ ! -f "$source_dir/isolinux/isolinux.bin" ]; then
        echo "ERROR: Required BIOS boot file isolinux/isolinux.bin not found in $source_dir"
        missing_files=1
    fi
     # isohdpfx.bin is used for MBR boot on USB sticks (isohybrid)
    if [ ! -f "$source_dir/isolinux/isohdpfx.bin" ]; then
        echo "WARNING: isohybrid MBR file isolinux/isohdpfx.bin not found. USB boot might be affected."
        # Depending on the source of BOOTFILES.tar.gz, this might be elsewhere or included in syslinux package
        # Try to find it from the system if missing
        local syslinux_mbr_path=$(find /usr/lib/syslinux/mbr /usr/share/syslinux -name 'isohdpfx.bin' -print -quit)
        if [ -n "$syslinux_mbr_path" ] && [ -f "$syslinux_mbr_path" ]; then
             echo "Found isohdpfx.bin at $syslinux_mbr_path, copying..."
             cp "$syslinux_mbr_path" "$source_dir/isolinux/isohdpfx.bin"
         else
             echo "Could not find isohdpfx.bin on the system either."
             # Decide whether to stop or continue with warning
        fi
    fi
    if [ ! -f "$source_dir/EFI/boot/efi.img" ]; then
        echo "ERROR: Required EFI boot image EFI/boot/efi.img not found in $source_dir"
         missing_files=1
    fi
    if [ ! -f "$source_dir/live/vmlinuz" ]; then
        echo "ERROR: Kernel file live/vmlinuz not found in $source_dir"
        missing_files=1
    fi
     if [ ! -f "$source_dir/live/initrd.img" ]; then
        echo "ERROR: Initrd file live/initrd.img not found in $source_dir"
         missing_files=1
    fi
     if [ ! -f "$source_dir/live/filesystem.squashfs" ]; then
        echo "ERROR: Root filesystem live/filesystem.squashfs not found in $source_dir"
         missing_files=1
    fi
     if [ ! -f "$source_dir/isolinux/isolinux.cfg" ]; then
        echo "ERROR: ISOLINUX config file isolinux/isolinux.cfg not found in $source_dir"
         missing_files=1
    fi
      if [ ! -f "$source_dir/boot/grub/grub.cfg" ]; then
        echo "ERROR: GRUB config file boot/grub/grub.cfg not found in $source_dir"
         missing_files=1
    fi

    if [ "$missing_files" -eq 1 ]; then
        echo "Aborting ISO creation due to missing essential files."
        return 1
    fi
    echo "All essential files found."

    echo "Creating hybrid ISO image ($output_file)..."

    # Ensure isohdpfx.bin path is correct for the -isohybrid-mbr option
    local isohybrid_mbr_path="$source_dir/isolinux/isohdpfx.bin"
    if [ ! -f "$isohybrid_mbr_path" ]; then
         # Fallback if warning was ignored or copy failed
         echo "ERROR: isohdpfx.bin still missing. Cannot create isohybrid MBR."
         return 1
    fi

    xorriso -as mkisofs \
        -iso-level 3 \
        -full-iso9660-filenames \
        -joliet \
        -rock \
        -volid "$iso_label" \
        -appid "GlitchLinux Live" \
        -publisher "GlitchLinux" \
        -preparer "$(whoami) via GlitchLinux ISO Creator script" \
        \
        `# BIOS Boot settings` \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -isohybrid-mbr "$isohybrid_mbr_path" \
        \
        `# UEFI Boot settings` \
        -eltorito-alt-boot \
        -e EFI/boot/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        \
        `# Output` \
        -o "$output_file" \
        \
        `# Source Directory` \
        "$source_dir"

    local iso_result=$?
    if [ $iso_result -ne 0 ]; then
        echo "Error creating ISO image (xorriso exit code: $iso_result)"
        return 1
    fi

    # Optional: Add checksum
    echo "Generating MD5 checksum..."
    md5sum "$output_file" > "$output_file.md5"

    echo "-------------------------------------"
    echo "ISO created successfully!"
    echo "Output: $output_file"
    echo "MD5   : $output_file.md5"
    echo "-------------------------------------"
    return 0
}

# Generate boot configurations
generate_boot_configs() {
    local ISO_DIR="$1"
    local NAME="$2"
    # These filenames are now fixed based on copy_kernel_initrd
    local VMLINUZ_NAME="vmlinuz"
    local INITRD_NAME="initrd.img"
    # SQUASHFS_NAME="filesystem.squashfs" # This wasn't actually used in the configs

    echo "Generating bootloader configuration files..."

    # Create directories if they don't exist (might be redundant if BOOTFILES worked)
    mkdir -p "$ISO_DIR/boot/grub"
    mkdir -p "$ISO_DIR/isolinux"

    # --- Generate grub.cfg ---
    # Note: The 'search' command might be slow on large ISOs.
    # Consider using UUID or LABEL if the filesystem label is reliably set.
    # Ensure the theme/font paths are correct relative to the extracted BOOTFILES.
    cat > "$ISO_DIR/boot/grub/grub.cfg" <<EOF
# GRUB configuration for $NAME Live ISO

set default="0"
set timeout=10
# set timeout_style=menu # or hidden

# Try to set root based on finding the kernel - adjust if unreliable
# search --set=root --file /live/$VMLINUZ_NAME

# Load graphical modules (ensure these are included in grub-mkimage if generated)
insmod all_video
insmod gfxterm
insmod png

# Set theme/font (adjust paths based on BOOTFILES.tar.gz content)
# loadfont /boot/grub/fonts/unicode.pf2 # Example path
# if loadfont /boot/grub/fonts/unicode.pf2 ; then
#    set gfxmode=auto # Try auto, or specific like 1024x768,800x600,640x480
#    insmod gfxterm
#    terminal_output gfxterm
#    if [ -f /boot/grub/splash.png ]; then
#      background_image /boot/grub/splash.png
#    fi
# fi

menuentry "$NAME - Live Boot" {
    echo "Loading Linux kernel..."
    linux /live/$VMLINUZ_NAME boot=live quiet splash --- # Add other kernel params if needed
    echo "Loading initial ramdisk..."
    initrd /live/$INITRD_NAME
}

menuentry "$NAME - Live Boot (Debug)" {
    echo "Loading Linux kernel (debug mode)..."
    linux /live/$VMLINUZ_NAME boot=live noprompt noeject # Remove quiet/splash for debug
    echo "Loading initial ramdisk..."
    initrd /live/$INITRD_NAME
}

menuentry "$NAME - Live Boot (Toram)" {
    echo "Loading Linux kernel (copy to RAM)..."
    linux /live/$VMLINUZ_NAME boot=live toram quiet splash ---
    echo "Loading initial ramdisk..."
    initrd /live/$INITRD_NAME
}

# Persistence example - requires setup on USB stick after writing ISO
# menuentry "$NAME - Live with Persistence" {
#     echo "Loading Linux kernel (with persistence)..."
#     linux /live/$VMLINUZ_NAME boot=live persistence quiet splash ---
#     echo "Loading initial ramdisk..."
#     initrd /live/$INITRD_NAME
# }

# Optional: GRUBFM chainloader entry (if included in BOOTFILES.tar.gz)
# if [ -f /EFI/GRUB-FM/E2B-bootx64.efi ]; then
#   menuentry "GRUB File Manager (UEFI)" {
#     chainloader /EFI/GRUB-FM/E2B-bootx64.efi
#   }
# fi

# Optional: Memtest (if included)
# if [ -f /boot/memtest86+.bin ]; then
#    menuentry "Memory Test (memtest86+)" {
#        linux16 /boot/memtest86+.bin
#    }
# fi
EOF

    # --- Generate isolinux.cfg ---
    # Ensure vesamenu.c32 and splash.png are present from BOOTFILES.tar.gz
    cat > "$ISO_DIR/isolinux/isolinux.cfg" <<EOF
# ISOLINUX configuration for $NAME Live ISO
UI vesamenu.c32
DEFAULT live

PROMPT 0
TIMEOUT 100 # 10 seconds

MENU TITLE $NAME Live Boot Menu
# MENU BACKGROUND splash.png # Uncomment if splash.png exists in isolinux dir

LABEL live
    MENU LABEL ^Live Boot $NAME
    KERNEL /live/$VMLINUZ_NAME
    APPEND initrd=/live/$INITRD_NAME boot=live quiet splash ---

LABEL debug
    MENU LABEL Live Boot (Debug Mode)
    KERNEL /live/$VMLINUZ_NAME
    APPEND initrd=/live/$INITRD_NAME boot=live noprompt noeject

LABEL toram
    MENU LABEL Live Boot (Copy to RAM)
    KERNEL /live/$VMLINUZ_NAME
    APPEND initrd=/live/$INITRD_NAME boot=live toram quiet splash ---

# LABEL persistence
#    MENU LABEL Live Boot with ^Persistence
#    KERNEL /live/$VMLINUZ_NAME
#    APPEND initrd=/live/$INITRD_NAME boot=live persistence quiet splash ---

# Optional: Memtest (if included)
# LABEL memtest
#    MENU LABEL ^Memory Test
#    KERNEL /boot/memtest86+.bin # Check path

# Optional: Hardware Detection Tool (if included)
# LABEL hdt
#    MENU LABEL ^Hardware Detection Tool (HDT)
#    COM32 hdt.c32 # Check path

LABEL local
   MENU LABEL ^Boot from first hard disk
   LOCALBOOT 0x80

EOF

    echo "Boot configuration files generated:"
    echo " - $ISO_DIR/boot/grub/grub.cfg"
    echo " - $ISO_DIR/isolinux/isolinux.cfg"
}

# --- Cleanup Function ---
cleanup() {
    local iso_dir=$1
    echo "Cleaning up build directory: $iso_dir"
    # Be careful with sudo rm -rf! Double check the path.
    if [[ -n "$iso_dir" && "$iso_dir" != "/" && "$iso_dir" =~ ^/home/ ]]; then # Safety check
       read -p "Confirm cleanup of $iso_dir? (y/N): " confirm_cleanup
       if [[ "$confirm_cleanup" =~ ^[Yy]$ ]]; then
           sudo rm -rf "$iso_dir"
           echo "Build directory removed."
       else
            echo "Cleanup skipped."
       fi
    else
        echo "Skipping cleanup due to potentially unsafe path: $iso_dir"
    fi
}


# ==============================================================================
# Main script execution
# ==============================================================================
main() {
    echo "=== GlitchLinux Live ISO Creator ==="
    echo "WARNING: This script clones the running host system and modifies it."
    echo "         Use with caution. A chroot-based build is recommended."
    echo "-------------------------------------"

    # Check for root privileges needed for some operations
    if [ "$EUID" -eq 0 ]; then
      echo "ERROR: Please do not run this script as root. It will use sudo where needed."
      exit 1
    fi

    # Check and install dependencies FIRST
    # Check a few key commands before trying full install
     if ! command -v xorriso &>/dev/null || ! command -v mksquashfs &>/dev/null || ! command -v wget &>/dev/null; then
        echo "Core dependencies might be missing."
        install_dependencies
    else
        echo "Basic dependencies seem present. Skipping initial check/install."
        # Optionally, still run install_dependencies to ensure *all* are there
        # install_dependencies
    fi

    # Regenerate host initramfs (WARNING!)
    read -p "Regenerate host initramfs to include live-boot? (Highly Recommended, but modifies host system!) (y/N): " confirm_initrd
    if [[ "$confirm_initrd" =~ ^[Yy]$ ]]; then
       regenerate_host_initramfs
    else
       echo "Skipping host initramfs regeneration. ISO might not boot correctly."
    fi

    # Get ISO name
    read -p "Enter a name for your ISO (e.g., MyCustomLive): " iso_name
    if [ -z "$iso_name" ]; then
        echo "Error: ISO name cannot be empty."
        exit 1
    fi
    # Sanitize name slightly (replace spaces, limit chars if needed)
    iso_name=$(echo "$iso_name" | tr -s ' ' '_')

    # Define directories and files based on name
    local iso_build_dir="/home/$iso_name" # Build directory
    local output_iso_file="/home/${iso_name}.iso" # Final ISO path
    # Create a sanitized volume label (uppercase, alphanumeric/underscore/hyphen, max 32 chars)
    local iso_vol_label=$(echo "$iso_name" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    if [ -z "$iso_vol_label" ]; then
        iso_vol_label="LINUX_LIVE" # Fallback label
    fi


    echo "--- Configuration ---"
    echo "ISO Build Directory: $iso_build_dir"
    echo "Output ISO File    : $output_iso_file"
    echo "ISO Volume ID      : $iso_vol_label"
    echo "---------------------"


    # --- Build Steps ---

    # 1. Create SquashFS (from host root '/')
    create_squashfs "$iso_name" # Uses $iso_name to determine $iso_build_dir inside

    # 2. Copy Kernel and Initrd (from host /boot)
    copy_kernel_initrd "$iso_name" # Uses $iso_name to determine $iso_build_dir inside

    # 3. Download and Extract Boot Files (ISOLINUX, GRUB base, etc.)
    download_bootfiles "$iso_build_dir"

    # 4. Configure EFI Boot specifics (bootloader binary, EFI ESP image)
    configure_efi_boot "$iso_build_dir" "$iso_name" # iso_name currently unused here

    # 5. Generate Bootloader Config Files (grub.cfg, isolinux.cfg)
    # Uses fixed names 'vmlinuz' and 'initrd.img' as copied earlier
    generate_boot_configs "$iso_build_dir" "$iso_name"


    # --- Final ISO Creation ---
    echo -e "\n=== Ready to Create ISO ==="
    read -p "Review the steps above. Proceed with ISO creation? (y/N): " confirm_create
    if [[ "$confirm_create" =~ ^[Yy]$ ]]; then
        create_iso "$iso_build_dir" "$output_iso_file" "$iso_vol_label"
        local create_status=$?
        if [ $create_status -eq 0 ]; then
             # Optional: Ask to clean up build directory
             read -p "ISO created successfully. Clean up the build directory ($iso_build_dir)? (y/N): " confirm_final_cleanup
             if [[ "$confirm_final_cleanup" =~ ^[Yy]$ ]]; then
                 cleanup "$iso_build_dir"
             else
                 echo "Build directory preserved at $iso_build_dir"
             fi
        else
             echo "ISO creation failed."
             echo "Build directory preserved at $iso_build_dir for inspection."
             exit 1
        fi
    else
        echo "ISO creation cancelled."
        # Optionally ask to clean up here too
         read -p "Clean up the build directory ($iso_build_dir) anyway? (y/N): " confirm_cancel_cleanup
         if [[ "$confirm_cancel_cleanup" =~ ^[Yy]$ ]]; then
             cleanup "$iso_build_dir"
         else
             echo "Build directory preserved at $iso_build_dir"
         fi
        exit 0
    fi

    echo "Script finished."
}

# --- Run Main Function ---
main "$@"
