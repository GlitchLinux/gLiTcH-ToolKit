#!/bin/bash

# Combined Linux Live Remaster & ISO Creator - Full GUI Workflow
# Combines system squashing and ISO creation into one seamless process
# https://github.com/GlitchLinux/LIVE-ISO-UTILITY.git

[ "`whoami`" != "root" ] && exec gsu ${0}

# Color codes for terminal output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Install minimal dependencies
install_dependencies() {
    local missing_deps=()
    for cmd in xorriso wget lzma tar yad; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${BLUE}Installing required packages: ${missing_deps[*]}${NC}"
        if [ -x "$(command -v apt-get)" ]; then
            sudo apt-get update && sudo apt-get install -y xorriso wget lzma tar yad
        elif [ -x "$(command -v dnf)" ]; then
            sudo dnf install -y xorriso wget lzma tar yad
        elif [ -x "$(command -v pacman)" ]; then
            sudo pacman -S --noconfirm xorriso wget lzma tar yad
        else
            echo -e "${RED}Error: Cannot install dependencies automatically${NC}"
            exit 1
        fi
    fi
}

# Download hybrid bootfiles for ISO creation
download_bootfiles() {
    local target_dir="$1"
    local temp_dir="/tmp/nano_bootfiles"
    
    echo -e "${BLUE}Downloading bootfiles...${NC}"
    mkdir -p "$temp_dir"
    
    if ! wget -q --progress=bar:force \
        "https://github.com/GlitchLinux/gLiTcH-ISO-Creator/raw/refs/heads/main/HYBRID-BASE-grub2-tux-splash.tar.lzma" \
        -O "$temp_dir/bootfiles.tar.lzma"; then
        echo -e "${RED}Error: Failed to download bootfiles${NC}"
        rm -rf "$temp_dir"
        exit 1
    fi
    
    echo -e "${BLUE}Extracting bootfiles to: $target_dir${NC}"
    unlzma "$temp_dir/bootfiles.tar.lzma"
    tar -xf "$temp_dir/bootfiles.tar" -C "$target_dir" --strip-components=1
    rm -rf "$temp_dir"
    
    echo -e "${GREEN}✅ Bootfiles installed in: $target_dir${NC}"
}

# Create GRUB config for live system
create_grub_config() {
    local iso_dir="$1"
    local name="$2"
    
    mkdir -p "$iso_dir/boot/grub"
    
    # Copy splash.png to boot/grub directory
    if [ -f "$iso_dir/isolinux/splash.png" ]; then
        echo -e "${BLUE}Copying splash screen for GRUB...${NC}"
        cp "$iso_dir/isolinux/splash.png" "$iso_dir/boot/grub/splash.png" 2>/dev/null
        cp "$iso_dir/isolinux/splash.png" "$iso_dir/splash.png" 2>/dev/null
    fi
    
    # Create theme configuration
    cat > "$iso_dir/boot/grub/theme.cfg" <<'EOF'
title-color: "white"
title-text: " "
title-font: "Sans Regular 16"
desktop-color: "black"
desktop-image: "/boot/grub/splash.png"
message-color: "white"
message-bg-color: "black"
terminal-font: "Sans Regular 12"

+ boot_menu {
  top = 150
  left = 15%
  width = 75%
  height = 150
  item_font = "Sans Regular 12"
  item_color = "grey"
  selected_item_color = "white"
  item_height = 20
  item_padding = 15
  item_spacing = 5
}

+ vbox {
  top = 100%
  left = 2%
  + label {text = "Press 'E' key to edit" font = "Sans 10" color = "white" align = "left"}
}
EOF
    
    # Create main GRUB configuration for Debian Live system
    cat > "$iso_dir/boot/grub/grub.cfg" <<EOF
# GRUB2 Configuration - Live System

# Font path and graphics setup
if loadfont \$prefix/fonts/font.pf2 ; then
  set gfxmode=800x600
  set gfxpayload=keep
  insmod efi_gop
  insmod efi_uga
  insmod video_bochs
  insmod video_cirrus
  insmod gfxterm
  insmod png
  terminal_output gfxterm
fi

# Background and color setup
if background_image "/boot/grub/splash.png"; then
  set color_normal=light-gray/black
  set color_highlight=white/black
elif background_image "/splash.png"; then
  set color_normal=light-gray/black
  set color_highlight=white/black
else
  set menu_color_normal=cyan/blue
  set menu_color_highlight=white/blue
fi

# Load theme if available
if [ -s \$prefix/theme.cfg ]; then
  set theme=\$prefix/theme.cfg
fi

# Basic settings
set default=0
set timeout=10

# Live System Entries
menuentry "$name - LIVE" {
    linux /live/vmlinuz boot=live config quiet splash
    initrd /live/initrd.img
}

menuentry "$name - Boot to RAM" {
    linux /live/vmlinuz boot=live config quiet splash toram
    initrd /live/initrd.img
}

menuentry "$name - Encrypted Persistence" {
    linux /live/vmlinuz boot=live components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/initrd.img
}

if [ -f /boot/grub/custom.cfg ]; then
    menuentry "Custom Options" {
        configfile /boot/grub/custom.cfg
    }
fi

EOF

    echo -e "${GREEN}Created GRUB configuration${NC}"
}

# Create auto-chainloading ISOLINUX config
create_isolinux_config() {
    local iso_dir="$1"
    
    cat > "$iso_dir/isolinux/isolinux.cfg" <<'EOF'
default grub2_chainload
timeout 1
prompt 0

label grub2_chainload
  linux /boot/grub/lnxboot.img
  initrd /boot/grub/core.img
EOF
}

# Create autorun.inf
create_autorun() {
    local iso_dir="$1"
    local name="$2"
    
    cat > "$iso_dir/autorun.inf" <<EOF
[Autorun]
icon=glitch.ico
label=$name
EOF
}

# Create ISO file
create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local volume_label="$3"
    
    echo -e "${BLUE}Creating ISO: $output_file${NC}"
    
    # Use isohdpfx.bin from bootfiles if available
    local mbr_file="$source_dir/isolinux/isohdpfx.bin"
    if [ ! -f "$mbr_file" ]; then
        mbr_file="/usr/lib/ISOLINUX/isohdpfx.bin"
    fi
    
    xorriso -as mkisofs \
        -iso-level 3 \
        -volid "$volume_label" \
        -full-iso9660-filenames \
        -R -J -joliet-long \
        -isohybrid-mbr "$mbr_file" \
        -b isolinux/isolinux.bin \
        -c isolinux/boot.cat \
        -no-emul-boot \
        -boot-load-size 4 \
        -boot-info-table \
        -eltorito-alt-boot \
        -e boot/grub/efi.img \
        -no-emul-boot \
        -isohybrid-gpt-basdat \
        -append_partition 2 0xEF "$source_dir/boot/grub/efi.img" \
        -o "$output_file" \
        "$source_dir" 2>/dev/null
    
    if [ $? -eq 0 ]; then
        local size=$(du -h "$output_file" | cut -f1)
        echo -e "${GREEN}✅ ISO created successfully!${NC}"
        echo -e "${YELLOW}📁 Location: $output_file${NC}"
        echo -e "${YELLOW}📏 Size: $size${NC}"
        return 0
    else
        echo -e "${RED}❌ ISO creation failed${NC}"
        return 1
    fi
}

# Phase 1: Create SquashFS from current system
create_squashfs() {
    devs="$(blkid -o list | grep /dev | grep -E -v "swap|ntfs|vfat" | sort | cut -d" " -f1 | grep -E -v "/loop|sr0|swap" | sed 's|/dev/||g')"
    DEVS=`echo $devs | sed 's/ /!/g'`
    
    SETUP=`yad --title="Live System Remaster - Step 1" --center --width=500 --height=300 \
        --text="<b>Create SquashFS from Current System</b>\n\nThis will create a compressed filesystem from your current system state.\nChoose where to create the squashfs file (must be on linux filesystem).\n\n<u>Note:</u> Manually loaded modules will be deactivated." \
        --window-icon="preferences-system" --form  \
        --field="Choose drive to create squashfs on::CB" "$DEVS!/tmp!/" \
        --field="Working directory name:" "remaster-work" \
        --field="SquashFS filename:" "filesystem.squashfs" \
        --button="gtk-quit:1" --button="gtk-ok:0"`
    ret=$?
    [[ $ret -ne 0 ]] && exit 0

    DRV="`echo $SETUP | cut -d "|" -f 1`"
    WRKDIR="`echo $SETUP | cut -d "|" -f 2`"
    SFS="`echo $SETUP | cut -d "|" -f 3`"

    if [ -z "$DRV" ] || [ -z "$WRKDIR" ] || [ -z "$SFS" ]; then
        yad --title="Error" --center --text="Please fill in all fields and try again." --button="gtk-close:0"
        exit 0
    fi

    # Set up paths based on drive selection
    if [ "$DRV" = "/tmp" ]; then
        # RAM size checks for /tmp
        ram_size() {
            [ -r /proc/meminfo ] && \
            grep MemTotal /proc/meminfo | \
            sed -e 's;.*[[:space:]]\([0-9][0-9]*\)[[:space:]]kB.*;\1;' || :
        }

        TOTAL=$(du -cbs --apparent-size / --exclude=/{dev,live,lib/live/mount,cdrom,mnt,proc,sys,media,run,tmp,initrd,var/cache/apt,var/lib/apt} | awk 'END {print $1}' | sed 's/.\{3\}$//')
        SFSSIZE=`echo $TOTAL/3 | bc`
        TEMPSIZE=`df -k /tmp | awk 'END {print $3}'`
        TEMPAVAIL=`df -k /tmp | awk 'END {print $4}'`
        TOTALTEMP=`echo $TOTAL + $SFSSIZE + $TEMPSIZE | bc`
        TOTALTEMPPLUS=`echo $TOTALTEMP/50 | bc`
        TOTSIZE=`echo $TOTALTEMP + $TOTALTEMPPLUS | bc`
        RAM=$(ram_size)

        if [ $TOTSIZE -gt $RAM ]; then
            yad --title="Error" --center --text="Not enough space available in /tmp.\nPlease choose another option." --button="gtk-close:0"
            exec ${0}
        fi
        
        if [ $TEMPAVAIL -le $TOTSIZE ]; then
            result=`echo $((TOTSIZE*1000/$RAM)) | cut -b -2` 
            mount -t tmpfs -o "remount,nosuid,size=${result}%,mode=1777" tmpfs /tmp
        fi
        
        WORK="/tmp/$WRKDIR"
        SQFS="/tmp/$SFS"
    elif [ "$DRV" = "/" ]; then
        WORK="/$WRKDIR"
        SQFS="/$SFS"
    else
        WORK="/mnt/$DRV/$WRKDIR"
        SQFS="/mnt/$DRV/$SFS"
        mkdir "/mnt/$DRV" 2> /dev/null
        mount /dev/$DRV /mnt/$DRV 2> /dev/null
    fi

    # Check for existing directories/files
    if [ -d "$WORK" ]; then
        yad --title="Error" --center --text="Directory '$WORK' already exists.\nPlease use a different name." --button="gtk-close:0"
        exit 0
    fi
    
    if [ -e "$SQFS" ]; then
        yad --title="Error" --center --text="File '$SQFS' already exists.\nPlease use a different name." --button="gtk-close:0"
        exit 0
    fi

    mkdir -p "$WORK"

    # Unload manually loaded squashfs modules
    if [ -f /mnt/live/tmp/modules ]; then
        CHNGS=/mnt/live/memory/images/SFS  # porteus-boot
    else
        CHNGS=/mnt/SFS  # live-boot
    fi

    if [ "$(ls $CHNGS 2> /dev/null)" ]; then
        for BUNDLE in $(ls $CHNGS); do
            FILES=$(find $CHNGS/$BUNDLE ! -type d | sed "s|$CHNGS/$BUNDLE||")
            umount $CHNGS/$BUNDLE && rmdir $CHNGS/$BUNDLE
            if [ $? -eq 0 ]; then
                while read line; do
                    if [ ! -e "$line" ]; then
                        if [ -f "${line}".dpkg-new ]; then
                            mv -f "$line".dpkg-new "${line}"
                            continue
                        fi
                        [ -L "$line" ] && echo "$line" >> /tmp/${BUNDLE}.txt
                    fi
                done <<< "$FILES"
                xargs -d '\n' -a /tmp/${BUNDLE}.txt rm 2>/dev/null
                tac /etc/SFS/${BUNDLE}.txt 2>/dev/null | while read line; do
                    if [ -d "$line" ]; then
                        rmdir "$line" 2> /dev/null 
                    fi
                done
                rm -f /etc/SFS/${BUNDLE}.txt /tmp/${BUNDLE}.txt
                echo "Module $BUNDLE deactivated"
            fi
        done
    fi

    # Start rsync with progress bar
    TOTAL=$(du -cbs --apparent-size /* --exclude=/{dev,live,lib/live/mount,cdrom,mnt,proc,sys,media,run,tmp,initrd,$WRKDIR} | awk 'END {print $1}')
    
    echo "Copying files to $WORK..."
    rsync -a / "$WORK" --exclude=/{dev,live,lib/live/mount,cdrom,mnt,proc,sys,media,run,tmp,initrd,$WRKDIR} 2> /dev/null &

    RSYNCPID=$(ps -eo pid,cmd | grep -v grep | grep "rsync -a / $WORK" | awk '{ print $1 }' | tr '\n' ' ')
    trap "kill $RSYNCPID" 1 2 15

    (
        PERC=0
        while [ $PERC ]; do
            COPY=$(du -cbs --apparent-size "$WORK" 2> /dev/null | awk 'END {print $1}')
            PERC=$((COPY*100/TOTAL))       
            if [ $PERC -lt 100 ]; then
                echo $PERC >> /tmp/remasterdog_progress
                echo $PERC 2> /dev/null
            fi
            sleep 1
            
            RSYNCPID=$(ps -eo pid,cmd | grep -v grep | grep "rsync -a / $WORK" | awk '{ print $1 }' | tr '\n' ' ')
            YADPID=$(ps -eo pid,cmd | grep -v grep | grep "yad --title=.*Copying" | awk '{ print $1 }' | tr '\n' ' ')

            if [ ! "$YADPID" ]; then
                kill $RSYNCPID 2> /dev/null
                sleep 2
                break
            fi
            [ -z "$RSYNCPID" ] && break
        done
        
        sleep 2
        if [ "$YADPID" ]; then
            echo 100 >> /tmp/remasterdog_progress 
            echo 100 2> /dev/null
        fi
    ) | yad --title="Copying System Files" --center --height="100" --width="400" --progress --auto-close --text="Copying files to $WORK..." --button="gtk-cancel"

    # Check if copying was cancelled
    if [ "$(tail -n1 /tmp/remasterdog_progress 2>/dev/null || echo 0)" -lt 100 ]; then
        rm -f /tmp/remasterdog_progress
        yad --title="Cancelled" --center --text="<b>Remastering Cancelled!</b>\n\nThe working directory will be removed." --button="gtk-close"
        [ -d "$WORK" ] && rm -rf "$WORK"
        exit
    else
        rm -f /tmp/remasterdog_progress
    fi

    # Create necessary directories and clean up
    mkdir -p "$WORK"/{dev,live,lib/live/mount,proc,run,mnt,media,sys,tmp}
    cp -a /dev/console "$WORK"/dev 2>/dev/null
    chmod a=rwx,o+t "$WORK"/tmp

    echo "Cleaning up system files..."
    # Cleanup operations
    rm -f "$WORK"/var/lib/alsa/asound.state
    rm -f "$WORK"/root/.bash_history
    rm -f "$WORK"/root/.xsession-errors
    rm -rf "$WORK"/root/.cache
    rm -rf "$WORK"/root/.thumbnails
    rm -f "$WORK"/etc/blkid-cache
    rm -f "$WORK"/etc/resolv.conf
    rm -rf "$WORK"/etc/udev/rules.d/70-persistent*
    rm -f "$WORK"/var/lib/dhcp/dhclient.eth0.leases
    rm -f "$WORK"/var/lib/dhcpcd/*.lease
    rm -f "$WORK"/etc/DISTRO_SPECS
    rm -rf "$WORK"/lib/consolefonts
    rm -rf "$WORK"/lib/keymaps
    rm -fr "$WORK"/var/lib/aptitude/*
    
    # Clean package caches
    ls "$WORK"/var/lib/apt/lists 2>/dev/null | grep -v "lock" | grep -v "partial" | xargs -I {} rm "$WORK"/var/lib/apt/lists/{} 2>/dev/null
    ls "$WORK"/var/cache/apt/archives 2>/dev/null | grep -v "lock" | grep -v "partial" | xargs -I {} rm "$WORK"/var/cache/apt/archives/{} 2>/dev/null
    ls "$WORK"/var/cache/apt 2>/dev/null | grep -v "archives" | xargs -I {} rm "$WORK"/var/cache/apt/{} 2>/dev/null
    rm -f "$WORK"/var/log/* 2> /dev/null

    cd "$WORK"
    find usr/share/doc -type f -exec rm -f {} \; 2>/dev/null
    find usr/share/man -type f -exec rm -f {} \; 2>/dev/null
    chown -R man:root usr/share/man 2>/dev/null

    # Choose compression type
    COMPRESSION=`yad --center --title="Choose Compression Type" --width=450 --height=250 \
        --text="<b>Ready to Create SquashFS</b>\n\nYou may want to do additional cleaning before compression.\nOpen file manager in '$WORK' if needed.\n\n<b>Choose compression algorithm:</b>\n• XZ: Smallest file, slower on low-spec machines\n• GZIP: Balanced size/speed\n• LZ4: Fastest, larger file size" \
        --button="LZ4:2" --button="GZIP:1" --button="XZ:0" --buttons-layout=spread`
    
    ret=$?
    [[ $ret -eq 252 ]] && exit 0  # Window closed

    echo -e "${BLUE}Creating $SQFS...${NC}"

    case $ret in
        0) # XZ
            (echo "# Creating SquashFS with XZ compression..."; mksquashfs "$WORK" "$SQFS" -comp xz -b 512k -Xbcj x86) | \
            yad --title="Creating SquashFS" --center --width=500 --height=200 --progress --pulsate --auto-close \
                --text="Creating compressed filesystem...\nThis may take several minutes." --button="gtk-cancel"
            ;;
        1) # GZIP
            (echo "# Creating SquashFS with GZIP compression..."; mksquashfs "$WORK" "$SQFS") | \
            yad --title="Creating SquashFS" --center --width=500 --height=200 --progress --pulsate --auto-close \
                --text="Creating compressed filesystem...\nThis may take several minutes." --button="gtk-cancel"
            ;;
        2) # LZ4
            (echo "# Creating SquashFS with LZ4 compression..."; mksquashfs "$WORK" "$SQFS" -comp lz4 -Xhc) | \
            yad --title="Creating SquashFS" --center --width=500 --height=200 --progress --pulsate --auto-close \
                --text="Creating compressed filesystem...\nThis may take several minutes." --button="gtk-cancel"
            ;;
    esac

    # Clean up working directory
    if [ -f "$SQFS" ]; then
        CLEANUP=`yad --title="Success" --center --width=400 \
            --text="<b>SquashFS created successfully!</b>\n\nFile: $SQFS\nSize: $(du -h "$SQFS" | cut -f1)\n\nRemove working directory '$WORK'?" \
            --button="Keep:1" --button="Remove:0"`
        ret=$?
        if [[ $ret -eq 0 ]]; then
            rm -rf "$WORK"
            echo "Working directory removed."
        fi
        
        # Return the squashfs path for next phase
        echo "$SQFS"
        return 0
    else
        yad --title="Error" --center --text="Error: SquashFS creation failed!\n\nFile '$SQFS' was not created." --button="gtk-close:0"
        return 1
    fi
}

# Phase 2: Create Live ISO from SquashFS
create_live_iso_from_squashfs() {
    local squashfs_file="$1"
    
    # Prompt user to proceed with ISO creation
    PROCEED=`yad --title="Live System Remaster - Step 2" --center --width=450 --height=200 \
        --text="<b>SquashFS Creation Complete!</b>\n\nFile: $squashfs_file\nSize: $(du -h "$squashfs_file" | cut -f1)\n\n<b>Proceed with creating bootable ISO?</b>" \
        --window-icon="applications-system" \
        --button="No, Exit:1" --button="Yes, Create ISO:0"`
    ret=$?
    [[ $ret -ne 0 ]] && exit 0

    # Get system name from user
    SYSTEM_INFO=`yad --title="ISO Configuration" --center --width=400 --height=250 \
        --text="<b>Configure Live ISO Settings</b>" \
        --form \
        --field="Live System Name:" "MyLiveSystem" \
        --field="ISO Filename:" "MyLiveSystem.iso" \
        --field="Volume Label:" "MYLIVE" \
        --button="gtk-cancel:1" --button="gtk-ok:0"`
    ret=$?
    [[ $ret -ne 0 ]] && exit 0

    live_system="`echo $SYSTEM_INFO | cut -d "|" -f 1`"
    iso_filename="`echo $SYSTEM_INFO | cut -d "|" -f 2`"
    volume_label="`echo $SYSTEM_INFO | cut -d "|" -f 3`"

    # Ensure proper extensions and formatting
    [[ "$iso_filename" != *.iso ]] && iso_filename="${iso_filename}.iso"
    volume_label=$(echo "$volume_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)

    # Create live system structure
    local work_dir="/tmp/$live_system"
    local live_dir="$work_dir/live"
    
    echo -e "${BLUE}Creating live system structure: $work_dir${NC}"
    mkdir -p "$live_dir"

    # Copy squashfs as filesystem.squashfs
    echo -e "${BLUE}Copying SquashFS to live system...${NC}"
    cp "$squashfs_file" "$live_dir/filesystem.squashfs"

    # Find and copy kernel and initrd from current system
    echo -e "${BLUE}Copying kernel and initrd...${NC}"
    local vmlinuz_found=""
    local initrd_found=""

    # Look for kernel in /boot
    for kernel in /boot/vmlinuz-* /boot/vmlinuz; do
        if [ -f "$kernel" ]; then
            vmlinuz_found="$kernel"
            break
        fi
    done

    # Look for initrd in /boot
    for initrd in /boot/initrd.img-* /boot/initrd.img /boot/initramfs-*.img; do
        if [ -f "$initrd" ]; then
            initrd_found="$initrd"
            break
        fi
    done

    if [ -z "$vmlinuz_found" ] || [ -z "$initrd_found" ]; then
        yad --title="Error" --center --text="<b>Cannot find kernel or initrd!</b>\n\nKernel: $vmlinuz_found\nInitrd: $initrd_found\n\nPlease ensure you have a complete system." --button="gtk-close:0"
        rm -rf "$work_dir"
        exit 1
    fi

    # Copy kernel and initrd
    cp "$vmlinuz_found" "$live_dir/vmlinuz"
    cp "$initrd_found" "$live_dir/initrd.img"

    echo -e "${GREEN}Live system structure created:${NC}"
    echo -e "  Kernel: $(basename "$vmlinuz_found")"
    echo -e "  Initrd: $(basename "$initrd_found")"
    echo -e "  SquashFS: $(du -h "$live_dir/filesystem.squashfs" | cut -f1)"

    # Download and setup bootfiles
    download_bootfiles "$work_dir"
    
    # Create configurations
    create_grub_config "$work_dir" "$live_system"
    create_isolinux_config "$work_dir"
    create_autorun "$work_dir" "$live_system"

    # Allow user to add custom files
    yad --title="Custom Files" --center --width=500 --height=250 \
        --text="<b>Add Custom Files (Optional)</b>\n\nYou can now add custom files to your ISO.\nAdd files to: <b>$work_dir</b>\n\nExamples:\n• Custom splash screens\n• Additional software\n• Configuration files\n• Documentation\n\n<b>Click OK when ready to build ISO</b>" \
        --window-icon="folder" \
        --button="Open Directory:2" --button="Skip:1" --button="Continue:0"
    
    custom_ret=$?
    if [[ $custom_ret -eq 2 ]]; then
        # Open file manager
        if command -v nautilus &>/dev/null; then
            nautilus "$work_dir" &
        elif command -v thunar &>/dev/null; then
            thunar "$work_dir" &
        elif command -v pcmanfm &>/dev/null; then
            pcmanfm "$work_dir" &
        elif command -v dolphin &>/dev/null; then
            dolphin "$work_dir" &
        fi
        
        # Wait for user to be ready
        yad --title="Ready?" --center --width=400 \
            --text="<b>Custom files added?</b>\n\nClick OK when you're ready to build the ISO." \
            --button="gtk-ok:0"
    fi

    # Set output path
    local squashfs_dir=$(dirname "$squashfs_file")
    local output_file="$squashfs_dir/$iso_filename"

    # Create final ISO
    echo -e "\n${BLUE}=== Building Final ISO ===${NC}"
    echo -e "System: $live_system"
    echo -e "Output: $output_file"
    echo -e "Volume: $volume_label"
    
    if create_iso "$work_dir" "$output_file" "$volume_label"; then
        # Success
        local iso_size=$(du -h "$output_file" | cut -f1)
        yad --title="Success!" --center --width=500 --height=200 \
            --text="<b>🎉 Live ISO Created Successfully!</b>\n\nFile: $output_file\nSize: $iso_size\n\nYour bootable live ISO is ready!" \
            --window-icon="emblem-default" \
            --button="Open Directory:1" --button="Close:0"
        
        open_ret=$?
        if [[ $open_ret -eq 1 ]]; then
            # Open directory containing ISO
            if command -v nautilus &>/dev/null; then
                nautilus "$squashfs_dir" &
            elif command -v thunar &>/dev/null; then
                thunar "$squashfs_dir" &
            elif command -v pcmanfm &>/dev/null; then
                pcmanfm "$squashfs_dir" &
            elif command -v dolphin &>/dev/null; then
                dolphin "$squashfs_dir" &
            fi
        fi
        
        # Clean up working directory
        CLEANUP_ISO=`yad --title="Cleanup" --center --width=400 \
            --text="<b>Remove temporary files?</b>\n\nWorking directory: $work_dir\n\nThis will free up disk space." \
            --button="Keep:1" --button="Remove:0"`
        cleanup_ret=$?
        if [[ $cleanup_ret -eq 0 ]]; then
            rm -rf "$work_dir"
            echo "Temporary files cleaned up."
        fi
        
        return 0
    else
        # Failure
        yad --title="Error" --center --width=400 \
            --text="<b>❌ ISO Creation Failed!</b>\n\nCheck terminal output for details.\nWorking directory preserved: $work_dir" \
            --button="gtk-close:0"
        return 1
    fi
}

# Main function
main() {
    echo -e "${YELLOW}=== Live System Remaster & ISO Creator ===${NC}"
    echo -e "${BLUE}Complete workflow: System → SquashFS → Bootable ISO${NC}"
    echo -e "${GREEN}Features: GUI interface, hybrid boot, custom file support${NC}\n"
    
    # Check dependencies
    install_dependencies
    
    # Phase 1: Create SquashFS from current system
    echo -e "\n${YELLOW}=== Phase 1: Creating SquashFS from Current System ===${NC}"
    SQUASHFS_FILE=$(create_squashfs)
    
    if [ $? -eq 0 ] && [ -n "$SQUASHFS_FILE" ] && [ -f "$SQUASHFS_FILE" ]; then
        echo -e "${GREEN}✅ SquashFS creation completed: $SQUASHFS_FILE${NC}"
        
        # Phase 2: Create bootable ISO from SquashFS
        echo -e "\n${YELLOW}=== Phase 2: Creating Bootable ISO ===${NC}"
        create_live_iso_from_squashfs "$SQUASHFS_FILE"
        
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}🎉 Complete workflow finished successfully!${NC}"
            echo -e "${YELLOW}Your live system has been remastered and packaged into a bootable ISO.${NC}"
        else
            echo -e "\n${RED}💥 ISO creation failed!${NC}"
        fi
    else
        echo -e "\n${RED}💥 SquashFS creation failed!${NC}"
        exit 1
    fi
}

# Check if running as root
if [ "$(whoami)" != "root" ]; then
    echo -e "${RED}This script must be run as root.${NC}"
    echo -e "${YELLOW}Please run: sudo $0${NC}"
    exit 1
fi

# Run main function
main "$@"