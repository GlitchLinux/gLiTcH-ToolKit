#!/bin/bash

# Combined Linux Live Remaster & ISO Creator - Simple Sequential Workflow
# Original SquashFS script + ISO creation script with YAD GUI
# https://github.com/GlitchLinux/LIVE-ISO-UTILITY.git

[ "`whoami`" != "root" ] && exec gsu ${0}

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Install all required dependencies
install_dependencies() {
    echo -e "${BLUE}Checking and installing dependencies...${NC}"
    
    local missing_deps=()
    local all_deps=(
        "bc"           # Mathematical calculations for SquashFS
        "rsync"        # File copying
        "mksquashfs"   # SquashFS creation
        "xorriso"      # ISO creation
        "wget"         # Download bootfiles
        "lzma"         # Decompress bootfiles
        "tar"          # Extract bootfiles
        "yad"          # GUI dialogs
        "xterm"        # Terminal for mksquashfs progress
        "blkid"        # Device detection
        "df"           # Disk space checking
        "du"           # Directory size calculation
        "find"         # File operations
        "grep"         # Text processing
        "awk"          # Text processing
        "sed"          # Text processing
        "ps"           # Process monitoring
        "mount"        # Filesystem mounting
        "umount"       # Filesystem unmounting
    )
    
    # Check which dependencies are missing
    for cmd in "${all_deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            missing_deps+=("$cmd")
        fi
    done
    
    if [ ${#missing_deps[@]} -gt 0 ]; then
        echo -e "${YELLOW}Missing dependencies: ${missing_deps[*]}${NC}"
        echo -e "${BLUE}Installing required packages...${NC}"
        
        if [ -x "$(command -v apt-get)" ]; then
            # Debian/Ubuntu package mapping
            local packages=""
            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                    "bc") packages="$packages bc" ;;
                    "rsync") packages="$packages rsync" ;;
                    "mksquashfs") packages="$packages squashfs-tools" ;;
                    "xorriso") packages="$packages xorriso" ;;
                    "wget") packages="$packages wget" ;;
                    "lzma") packages="$packages xz-utils" ;;
                    "tar") packages="$packages tar" ;;
                    "yad") packages="$packages yad" ;;
                    "xterm") packages="$packages xterm" ;;
                    "blkid") packages="$packages util-linux" ;;
                    "df"|"du"|"mount"|"umount") packages="$packages coreutils" ;;
                    "find") packages="$packages findutils" ;;
                    "grep") packages="$packages grep" ;;
                    "awk") packages="$packages gawk" ;;
                    "sed") packages="$packages sed" ;;
                    "ps") packages="$packages procps" ;;
                esac
            done
            
            # Remove duplicates and install
            packages=$(echo $packages | tr ' ' '\n' | sort -u | tr '\n' ' ')
            echo -e "${BLUE}Installing: $packages${NC}"
            
            if sudo apt-get update && sudo apt-get install -y $packages; then
                echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
            else
                echo -e "${RED}❌ Failed to install some dependencies${NC}"
                echo -e "${YELLOW}Please install manually: $packages${NC}"
                exit 1
            fi
            
        elif [ -x "$(command -v dnf)" ]; then
            # Fedora/RHEL package mapping
            local packages=""
            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                    "bc") packages="$packages bc" ;;
                    "rsync") packages="$packages rsync" ;;
                    "mksquashfs") packages="$packages squashfs-tools" ;;
                    "xorriso") packages="$packages xorriso" ;;
                    "wget") packages="$packages wget" ;;
                    "lzma") packages="$packages xz" ;;
                    "tar") packages="$packages tar" ;;
                    "yad") packages="$packages yad" ;;
                    "xterm") packages="$packages xterm" ;;
                    *) packages="$packages $dep" ;;
                esac
            done
            
            packages=$(echo $packages | tr ' ' '\n' | sort -u | tr '\n' ' ')
            echo -e "${BLUE}Installing: $packages${NC}"
            
            if sudo dnf install -y $packages; then
                echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
            else
                echo -e "${RED}❌ Failed to install some dependencies${NC}"
                exit 1
            fi
            
        elif [ -x "$(command -v pacman)" ]; then
            # Arch Linux package mapping
            local packages=""
            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                    "bc") packages="$packages bc" ;;
                    "rsync") packages="$packages rsync" ;;
                    "mksquashfs") packages="$packages squashfs-tools" ;;
                    "xorriso") packages="$packages libisoburn" ;;
                    "wget") packages="$packages wget" ;;
                    "lzma") packages="$packages xz" ;;
                    "tar") packages="$packages tar" ;;
                    "yad") packages="$packages yad" ;;
                    "xterm") packages="$packages xterm" ;;
                    *) packages="$packages $dep" ;;
                esac
            done
            
            packages=$(echo $packages | tr ' ' '\n' | sort -u | tr '\n' ' ')
            echo -e "${BLUE}Installing: $packages${NC}"
            
            if sudo pacman -S --noconfirm $packages; then
                echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
            else
                echo -e "${RED}❌ Failed to install some dependencies${NC}"
                exit 1
            fi
            
        elif [ -x "$(command -v zypper)" ]; then
            # openSUSE package mapping
            local packages=""
            for dep in "${missing_deps[@]}"; do
                case "$dep" in
                    "mksquashfs") packages="$packages squashfs" ;;
                    "lzma") packages="$packages xz" ;;
                    *) packages="$packages $dep" ;;
                esac
            done
            
            packages=$(echo $packages | tr ' ' '\n' | sort -u | tr '\n' ' ')
            echo -e "${BLUE}Installing: $packages${NC}"
            
            if sudo zypper install -y $packages; then
                echo -e "${GREEN}✅ Dependencies installed successfully${NC}"
            else
                echo -e "${RED}❌ Failed to install some dependencies${NC}"
                exit 1
            fi
            
        else
            echo -e "${RED}Error: Cannot install dependencies automatically${NC}"
            echo -e "${YELLOW}Unsupported package manager. Please install manually:${NC}"
            echo -e "${YELLOW}Missing commands: ${missing_deps[*]}${NC}"
            echo -e "${BLUE}Package suggestions:${NC}"
            echo -e "  bc rsync squashfs-tools xorriso wget xz-utils tar yad xterm"
            exit 1
        fi
    else
        echo -e "${GREEN}✅ All dependencies are already installed${NC}"
    fi
    
    # Verify critical dependencies after installation
    local critical_deps=("bc" "mksquashfs" "xorriso" "yad" "rsync")
    local still_missing=()
    
    for cmd in "${critical_deps[@]}"; do
        if ! command -v "$cmd" &>/dev/null; then
            still_missing+=("$cmd")
        fi
    done
    
    if [ ${#still_missing[@]} -gt 0 ]; then
        echo -e "${RED}❌ Critical dependencies still missing: ${still_missing[*]}${NC}"
        echo -e "${YELLOW}Please install them manually before running this script${NC}"
        exit 1
    fi
    
    echo -e "${GREEN}✅ All required dependencies are available${NC}\n"
}

# ORIGINAL SQUASHFS CREATION SCRIPT (unchanged)
create_squashfs() {
    devs="$(blkid -o list | grep /dev | grep -E -v "swap|ntfs|vfat" | sort | cut -d" " -f1 | grep -E -v "/loop|sr0|swap" | sed 's|/dev/||g')"
    echo $devs
    DEVS=`echo $devs | sed 's/ /!/g'`
    SETUP=`yad --title="RemasterDog" --center --text=" This script will create a module from the current state of the system (including changes).  \n Advised is to run this script from terminal to watch progress.  \n If multiple modules are loaded from 'live' these will be merged into one.\n <u>Except for manually loaded modules, these will be de-activated.</u>  \n Choose where to create new module, must be on linux filesystem, \n  ntfs or fat filesytems are excluded." \
    --window-icon="preferences-system" --form  \
    --field="  Choose drive to create module on::CB" "$DEVS!/tmp!/" \
    --field="Type custom name of working directory \n  (e.g. remastered):" "" \
    --field="Type name for module with extension \n(e.g. 01-remaster.squashfs or 01-remaster.xzm):" "" \
    --button="gtk-quit:1" --button="gtk-ok:0"`
    ret=$?
    [[ $ret -ne 0 ]] && exit 0

    DRV="`echo $SETUP | cut -d "|" -f 1`"
    WRKDIR="`echo $SETUP | cut -d "|" -f 2`"
    SFS="`echo $SETUP | cut -d "|" -f 3`"

    if [ -z "$DRV" ] || [ -z "$WRKDIR" ] || [ -z "$SFS" ]; then
        yad --title="RemasterDog" --center --text=" You probably did not fill in all fields, \n Please run the script again" --button="gtk-close:0"
        exit 0
    fi

    if [ "$DRV" = "/tmp" ]; then
        ram_size() {
            [ -r /proc/meminfo ] && \
            grep MemTotal /proc/meminfo | \
            sed -e 's;.*[[:space:]]\([0-9][0-9]*\)[[:space:]]kB.*;\1;' || :
        }

        TOTAL=$(du -cbs --apparent-size / --exclude=/{dev,live,lib/live/mount,cdrom,mnt,proc,sys,media,run,tmp,initrd,var/cache/apt,var/lib/apt} | awk 'END {print $1}' | sed 's/.\{3\}$//')
        echo total=$TOTAL
        SFSSIZE=`echo   $TOTAL/3 | bc`
        echo sfssize=$SFSSIZE
        TEMPSIZE=`df -k /tmp | awk 'END {print $3}'`
        TEMPAVAIL=`df -k /tmp | awk 'END {print $4}'`
        TOTALTEMP=`echo $TOTAL + $SFSSIZE + $TEMPSIZE | bc`
        TOTALTEMPPLUS=`echo $TOTALTEMP/50 | bc`
        TOTSIZE=`echo $TOTALTEMP + $TOTALTEMPPLUS | bc`
        echo totsize=$TOTSIZE
        RAM=$(ram_size)

        if [ $TOTSIZE -gt $RAM ]; then
            yad --title="RemasterDog" --center --text=" Not enough space available in /tmp. \n Please choose another option" --button="gtk-close:0" && exec ${0}
            exit 0
        fi
        if [ $TEMPAVAIL -gt $TOTSIZE ]; then
            :
        else
            result=`echo $((TOTSIZE*1000/$RAM)) | cut -b -2` 
            echo $result
            mount -t tmpfs -o "remount,nosuid,size=${result}%,mode=1777" tmpfs /tmp
        fi
        WORK="/tmp/$WRKDIR"
        SQFS="/tmp/$SFS"

    elif [ "$DRV" = "/" ]; then
        chksize() {
            ROOTAVAIL=`df -k / | awk 'END {print $4}'`
            echo rootavail=$ROOTAVAIL
            TOTAL=$(du -cbs --apparent-size / --exclude=/{dev,live,lib/live/mount,cdrom,mnt,proc,sys,media,run,tmp,initrd,var/cache/apt,var/lib/apt} | awk 'END {print $1}' | sed 's/.\{3\}$//')
            SFSSIZE=`echo   $TOTAL/3 | bc`
            echo sfssize=$SFSSIZE
            TOTALROOT=`echo $TOTAL + $SFSSIZE | bc`
            echo totrootsize=$TOTALROOT
            TOTALROOTPLUS=`echo $TOTALROOT/50 | bc`
            TOTSIZE=`echo $TOTALROOT + $TOTALROOTPLUS | bc`
            echo totsize=$TOTSIZE
        }
        chksize
        if [ $TOTSIZE -gt $ROOTAVAIL ]; then
            if [ -f /mnt/live/tmp/changes-exit ]; then
                echo "Increasing ramsize for /mnt/live/memory/changes to 100%"
                echo "After that we will check again if available space is sufficient"
                mount -t tmpfs -o "remount,nosuid,size=100%,rw" tmpfs /mnt/live/memory/changes
                chksize
            fi
        fi

        if [ $TOTSIZE -gt $ROOTAVAIL ]; then
            echo "Sorry, not enough space available in / ."
            yad --width=400 --title="RemasterDog" --center --text="  Sorry, not enough space available in / . \n  The reason could be that: \n  Your save file/partition has not enough space left. \n  Please choose another option." --button="gtk-close:0" && exec ${0}
        fi

        WORK="/$WRKDIR"
        SQFS="/$SFS"

    else
        WORK="/mnt/$DRV/$WRKDIR"
        SQFS="/mnt/$DRV/$SFS"
        mkdir "/mnt/$DRV" 2> /dev/null
        mount /dev/$DRV /mnt/$DRV 2> /dev/null
    fi

    if [ -d "$WORK" ]; then
        yad --title="RemasterDog" --center --text=" Directory "$WORK" already exists, \n Please run the script again and use other name" --button="gtk-close:0"
        exit 0
    fi
    mkdir -p "$WORK"

    if [ -e "$SQFS" ]; then
        yad --title="RemasterDog" --center --text=" File "$SQFS" already exists, \n Please run the script again and use other name" --button="gtk-close:0"
        exit 0
    fi

    #### unload manually loaded squashfs
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
                xargs -d '\n' -a /tmp/${BUNDLE}.txt rm
                tac /etc/SFS/${BUNDLE}.txt | while read line; do
                    if [ -d "$line" ]; then
                        rmdir "$line" 2> /dev/null 
                    fi
                done
                rm -f /etc/SFS/${BUNDLE}.txt
                rm -f /tmp/${BUNDLE}.txt
                echo "Module $BUNDLE deactivated"
            fi
        done
    fi

    ######## Start Progress bar, rsync copying #########
    TOTAL=$(du -cbs --apparent-size /* --exclude=/{dev,live,lib/live/mount,cdrom,mnt,proc,sys,media,run,tmp,initrd,$WRKDIR} | awk 'END {print $1}')
    echo $TOTAL

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
            YADPID=$(ps -eo pid,cmd | grep -v grep | grep "yad --title=RemasterDog" | awk '{ print $1 }' | tr '\n' ' ')

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
    ) | yad --title="RemasterDog" --center --height="100" --width="400" --progress --auto-close --text=" Copying files to "$WORK"... " --button="gtk-cancel"

    if [ "$(tail -n1 /tmp/remasterdog_progress)" -lt 100 ] ; then
        echo cancelled
        rm -f /tmp/remasterdog_progress
        yad --title="RemasterDog" --center --height="100" --width="400" --text " <b>Remastering Cancelled!</b> \n The working directory: \n $WORK \n will be deleted within a minute after closing this window " --button="gtk-close"
        if [ -d "$WORK" ]; then
            echo "Removing $WORK..."
            rm -rf "$WORK"
        fi
        exit
    else
        rm -f /tmp/remasterdog_progress
        sleep 2
        echo "Check now for any left over process ID's from rsync, should not show any below"
        RSYNCPID=$(ps -eo pid,cmd | grep -v grep | grep "rsync -a / $WORK" | awk '{ print $1 }' | tr '\n' ' ')
        echo "$RSYNCPID"
        if [ -z "$RSYNCPID" ]; then
            echo "OK, Continuing..."
        else
            wait
            echo "Continuing..."
        fi
    fi
    ########### End Progress bar, rsync copying ############

    mkdir -p "$WORK"/{dev,live,lib/live/mount,proc,run,mnt,media,sys,tmp}
    cp -a /dev/console "$WORK"/dev
    chmod a=rwx,o+t "$WORK"/tmp

    echo "Cleaning..."
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
    ls "$WORK"/var/lib/apt/lists | grep -v "lock" | grep -v "partial" | xargs -i rm "$WORK"/var/lib/apt/lists/{} ; 
    ls "$WORK"/var/cache/apt/archives | grep -v "lock" | grep -v "partial" | xargs -i rm "$WORK"/var/cache/apt/archives/{} ;
    ls "$WORK"/var/cache/apt | grep -v "archives" | xargs -i rm "$WORK"/var/cache/apt/{} ;
    rm -f "$WORK"/var/log/* 2> /dev/null

    cd "$WORK"

    find usr/share/doc -type f -exec rm -f {} \;
    find usr/share/man -type f -exec rm -f {} \;
    chown -R man:root usr/share/man

    rm -fr "$WORK"/usr/share/doc/elinks
    ln -sf /usr/share/doc/elinks-data "$WORK"/usr/share/doc/elinks

    # Fix live system boot issues
    echo "Preparing live system configuration..."
    
    # Create systemd service override to fix remount-fs errors
    mkdir -p "$WORK"/etc/systemd/system
    cat > "$WORK"/etc/systemd/system/systemd-remount-fs.service <<'EOF'
[Unit]
Description=Remount Root and Kernel File Systems (disabled for live)
Documentation=man:systemd-remount-fs.service(8)
Documentation=https://www.freedesktop.org/wiki/Software/systemd/APIFileSystems
DefaultDependencies=no
Wants=local-fs-pre.target
After=local-fs-pre.target
Before=local-fs.target shutdown.target
Conflicts=shutdown.target

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
TimeoutSec=10s

[Install]
WantedBy=local-fs.target
EOF

    # Create systemd-tmpfiles-setup-dev.service override to fix device setup errors
    cat > "$WORK"/etc/systemd/system/systemd-tmpfiles-setup-dev.service <<'EOF'
[Unit]
Description=Create Static Device Nodes in /dev (disabled for live)
Documentation=man:tmpfiles.d(5)
Documentation=man:systemd-tmpfiles(8)
DefaultDependencies=no
Before=local-fs-pre.target systemd-udevd.service
ConditionCapability=CAP_SYS_MODULE

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
TimeoutSec=10s

[Install]
WantedBy=local-fs-pre.target
EOF

    # Create additional systemd service overrides for common live boot issues
    cat > "$WORK"/etc/systemd/system/systemd-fsck@.service <<'EOF'
[Unit]
Description=File System Check on %f (disabled for live)
Documentation=man:systemd-fsck@.service(8)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
TimeoutSec=0

[Install]
WantedBy=multi-user.target
EOF

    cat > "$WORK"/etc/systemd/system/systemd-fsck-root.service <<'EOF'
[Unit]
Description=File System Check on Root Device (disabled for live)
Documentation=man:systemd-fsck-root.service(8)

[Service]
Type=oneshot
RemainAfterExit=yes
ExecStart=/bin/true
TimeoutSec=0

[Install]
WantedBy=local-fs.target
EOF

    # Create live-friendly fstab
    cat > "$WORK"/etc/fstab <<'EOF'
# Live system fstab
tmpfs /tmp tmpfs defaults,noatime 0 0
tmpfs /var/log tmpfs defaults,noatime 0 0
tmpfs /var/tmp tmpfs defaults,noatime 0 0
proc /proc proc defaults 0 0
sysfs /sys sysfs defaults 0 0
devpts /dev/pts devpts gid=5,mode=620 0 0
EOF

    # Blacklist problematic modules
    cat > "$WORK"/etc/modprobe.d/live-blacklist.conf <<'EOF'
# Blacklist problematic modules for live boot
blacklist pcspkr
blacklist snd_pcsp
EOF

    # Remove machine-id files to force regeneration
    rm -f "$WORK"/etc/machine-id
    rm -f "$WORK"/var/lib/dbus/machine-id

    # Check if mksquashfs version is 4.3 or higher
    check_mksquashfs_version=$(mksquashfs -version | awk 'NR==1 { print $3 }' | grep -o 4.3)
    verlte() {
        [  "$1" = "`echo -e "$1\n$2" | sort -V | head -n1`" ]
    }

    verlt() {
        [ "$1" = "$2" ] && return 1 || verlte $1 $2
    }

    if verlt $check_mksquashfs_version 4.3
    then
        yad  --center --title="Choose Compression Type" --text "  Now you may want to do some extra cleaning to save more space before creating module with mksquashfs.\n For example: ~/.mozilla  \n Open filemanager in '$WORK' to do so. \n  Make a choice to finally create:\n   '$SQFS'  \n  <b>Choose which algorthim to compress the sfs with.</b> \n  Chosing XZ here will give you a smaller file but \n  may be slower than GZIP on very lowspec machines. " --button=" XZ :1" --button=" GZIP :0" --buttons-layout=spread

        button1=$?
        echo -e "\e[0;36mCreating $SQFS....\033[0m"

        case $button1 in
        0)
            xterm -T "RemasterCow" -si -sb -fg white -bg SkyBlue4 -geometry 65x14 -e "mksquashfs "$WORK" "$SQFS""
            ;;
        1)
            xterm -T "RemasterCow" -si -sb -fg white -bg SkyBlue4 -geometry 65x14 -e "mksquashfs "$WORK" "$SQFS" -comp xz -b 512k -Xbcj x86"
            ;;
        esac
    else
        yad  --center --title="Choose Compression Type" --text "  Now you may want to do some extra cleaning to save more space before creating module with mksquashfs.\n  For example: ~/.mozilla  \n  Open filemanager in '$WORK' to do so. \n  Make a choice to finally create:\n   '$SQFS' \n   <b>Choose which algorthim to compress the sfs with.</b> \n  Chosing XZ here will give you a smaller file but \n  may be slower than GZIP on very lowspec machines \n  LZ4 is the fastest, but gives a larger file as GZIP. " --button=" XZ :2" --button=" GZIP :1" --button=" LZ4 :0" --buttons-layout=spread

        button1=$?
        echo -e "\e[0;36mCreating $SQFS....\033[0m"

        case $button1 in
        0)
            xterm -T "RemasterDog" -si -sb -fg white -bg SkyBlue4 -geometry 65x14 -e "mksquashfs "$WORK" "$SQFS" -comp lz4 -Xhc"
            ;;
        1)
            xterm -T "RemasterDog" -si -sb -fg white -bg SkyBlue4 -geometry 65x14 -e "mksquashfs "$WORK" "$SQFS""
            ;;
        2)
            xterm -T "RemasterDog" -si -sb -fg white -bg SkyBlue4 -geometry 65x14 -e "mksquashfs "$WORK" "$SQFS" -comp xz -b 512k -Xbcj x86"
            ;;
        esac
    fi

    # Remove working directory?
    if [ -f "$SQFS" ]; then
        yad --title="RemasterDog" --center --text=" Done creating '$SQFS' \n Do you want to remove '$WORK'? " --button="gtk-yes:0" --button="gtk-no:1"
        ret=$?
        # Only remove work directory if user clicked "Yes" (ret=0)
        if [[ $ret -eq 0 ]]; then
            if [[ -n "$SFS" && -n "$DRV" ]]; then
                rm -rf "$WORK"
            fi
        fi
        
        # MODIFIED: Always return the squashfs path if file exists, regardless of cleanup choice
        echo "$SQFS"
        return 0
    else
        yad --title="RemasterDog" --center --text=" Error: '$SQFS' is not created. \n Do you want to remove '$WORK'? " --button="gtk-yes:0" --button="gtk-no:1"
        ret=$?
        # Only exit if user wants to exit, otherwise just clean up and return error
        if [[ $ret -eq 0 ]]; then
            if [[ -n "$SFS" && -n "$DRV" ]]; then
                rm -rf "$WORK"
            fi
        fi
        return 1
    fi
}

# ISO CREATION FUNCTIONS (from original ISO script, converted to YAD)
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

create_grub_config() {
    local iso_dir="$1"
    local name="$2"
    local vmlinuz="$3"
    local initrd="$4"
    local live_dir="$5"
    
    mkdir -p "$iso_dir/boot/grub"
    
    if [ -f "$iso_dir/isolinux/splash.png" ]; then
        echo -e "${BLUE}Copying splash screen for GRUB...${NC}"
        cp "$iso_dir/isolinux/splash.png" "$iso_dir/boot/grub/splash.png" 2>/dev/null
        cp "$iso_dir/isolinux/splash.png" "$iso_dir/splash.png" 2>/dev/null
    fi
    
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
    
    cat > "$iso_dir/boot/grub/grub.cfg" <<EOF
# GRUB2 Configuration - Proven Theme Approach

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

if [ -s \$prefix/theme.cfg ]; then
  set theme=\$prefix/theme.cfg
fi

set default=0
set timeout=10

menuentry "$name - LIVE" {
    linux /live/$vmlinuz boot=live config quiet splash
    initrd /live/$initrd
}

menuentry "$name - Boot to RAM" {
    linux /live/$vmlinuz boot=live config quiet splash toram
    initrd /live/$initrd
}

menuentry "$name - Encrypted Persistence" {
    linux /live/$vmlinuz boot=live components quiet splash persistent=cryptsetup persistence-encryption=luks persistence
    initrd /live/$initrd
}

if [ -f /boot/grub/custom.cfg ]; then
    menuentry "Custom Options" {
        configfile /boot/grub/custom.cfg
    }
fi

EOF
    echo -e "${GREEN}Created GRUB configuration${NC}"
}

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

create_autorun() {
    local iso_dir="$1"
    local name="$2"
    
    cat > "$iso_dir/autorun.inf" <<EOF
[Autorun]
icon=glitch.ico
label=$name
EOF
}

create_iso() {
    local source_dir="$1"
    local output_file="$2"
    local volume_label="$3"
    
    echo -e "${BLUE}Creating ISO: $output_file${NC}"
    
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

# ISO CREATION WORKFLOW (YAD version of CLI prompts)
create_live_iso() {
    local squashfs_file="$1"
    
    # Prompt: Proceed with ISO creation?
    PROCEED=`yad --title="Proceed With ISO Creation?" --center --width=450 --height=200 \
        --text="<b>Proceed With creating ISO file from .squashfs system?</b>\n\nSquashFS: $squashfs_file\nSize: $(du -h "$squashfs_file" | cut -f1)" \
        --button="No, Exit:1" --button="Yes, Create ISO:0"`
    ret=$?
    [[ $ret -ne 0 ]] && exit 0

    # Prompt: System name
    SYSTEM_NAME=`yad --title="System Name" --center --width=400 \
        --text="<b>Enter name of system:</b>" \
        --entry --entry-text="MyLiveSystem" \
        --button="gtk-cancel:1" --button="gtk-ok:0"`
    ret=$?
    [[ $ret -ne 0 ]] && exit 0
    
    live_system="$SYSTEM_NAME"
    
    # Create live system structure
    local target_dir="/tmp/$live_system"
    local live_dir="$target_dir/live"
    
    echo -e "${BLUE}Creating live system structure: $target_dir${NC}"
    mkdir -p "$live_dir"
    
    # Copy squashfs as filesystem.squashfs
    echo -e "${BLUE}Copying SquashFS to live system...${NC}"
    cp "$squashfs_file" "$live_dir/filesystem.squashfs"
    
    # Copy vmlinuz and initrd from system boot
    echo -e "${BLUE}Copying kernel and initrd from /boot...${NC}"
    local vmlinuz_found=""
    local initrd_found=""
    
    for kernel in /boot/vmlinuz-* /boot/vmlinuz; do
        if [ -f "$kernel" ]; then
            vmlinuz_found="$kernel"
            break
        fi
    done
    
    for initrd in /boot/initrd.img-* /boot/initrd.img /boot/initramfs-*.img; do
        if [ -f "$initrd" ]; then
            initrd_found="$initrd"
            break
        fi
    done
    
    if [ -z "$vmlinuz_found" ] || [ -z "$initrd_found" ]; then
        yad --title="Error" --center --text="Cannot find kernel or initrd in /boot!\n\nKernel: $vmlinuz_found\nInitrd: $initrd_found" --button="gtk-close:0"
        rm -rf "$target_dir"
        exit 1
    fi
    
    cp "$vmlinuz_found" "$live_dir/vmlinuz"
    cp "$initrd_found" "$live_dir/initrd.img"
    
    # Download bootfiles
    download_bootfiles "$target_dir"
    
    # Create configurations
    create_grub_config "$target_dir" "$live_system" "vmlinuz" "initrd.img" "live"
    create_isolinux_config "$target_dir"
    create_autorun "$target_dir" "$live_system"
    
    # YAD version of custom files prompt
    yad --title="Add Custom Files" --center --width=500 --height=200 \
        --text="<b>You can now add custom files that you wish to include in the iso</b>\n\nAdd your files to: $target_dir\n\nClick OK when ready to continue with ISO creation." \
        --button="gtk-ok:0"
    
    # Get filenames using YAD
    ISO_SETTINGS=`yad --title="ISO Settings" --center --width=400 --height=200 \
        --text="<b>ISO Creation Settings</b>" \
        --form \
        --field="ISO filename:" "$live_system.iso" \
        --field="Volume label:" "${live_system^^}" \
        --button="gtk-cancel:1" --button="gtk-ok:0"`
    ret=$?
    [[ $ret -ne 0 ]] && exit 0
    
    iso_name="`echo $ISO_SETTINGS | cut -d "|" -f 1`"
    volume_label="`echo $ISO_SETTINGS | cut -d "|" -f 2`"
    
    [[ "$iso_name" != *.iso ]] && iso_name="${iso_name}.iso"
    volume_label=$(echo "$volume_label" | tr '[:lower:]' '[:upper:]' | tr -cd '[:alnum:]_-' | cut -c1-32)
    
    # Set output path in same directory as SquashFS
    local squashfs_dir=$(dirname "$squashfs_file")
    local output_file="$squashfs_dir/$iso_name"
    
    # Create ISO
    if create_iso "$target_dir" "$output_file" "$volume_label"; then
        local iso_size=$(du -h "$output_file" | cut -f1)
        yad --title="Success!" --center --width=500 --height=200 \
            --text="<b>🎉 Live ISO Created Successfully!</b>\n\nFile: $output_file\nSize: $iso_size\n\nYour bootable live ISO is ready!" \
            --button="gtk-ok:0"
        
        # Cleanup
        CLEANUP=`yad --title="Cleanup" --center --width=400 \
            --text="Remove temporary ISO working directory?\n\n$target_dir" \
            --button="Keep:1" --button="Remove:0"`
        cleanup_ret=$?
        if [[ $cleanup_ret -eq 0 ]]; then
            rm -rf "$target_dir"
            echo "Temporary files cleaned up."
        fi
        
        return 0
    else
        yad --title="Error" --center --text="❌ ISO Creation Failed!\n\nCheck terminal output for details." --button="gtk-close:0"
        return 1
    fi
}

# MAIN FUNCTION - Sequential workflow
main() {
    echo -e "${YELLOW}=== Live System Remaster & ISO Creator ===${NC}"
    echo -e "${BLUE}Sequential workflow: SquashFS → ISO creation${NC}\n"
    
    # Install all required dependencies first
    install_dependencies
    
    # Phase 1: Create SquashFS (original script)
    echo -e "${YELLOW}=== Phase 1: Creating SquashFS ===${NC}"
    SQUASHFS_FILE=$(create_squashfs)
    
    if [ $? -eq 0 ] && [ -n "$SQUASHFS_FILE" ] && [ -f "$SQUASHFS_FILE" ]; then
        echo -e "${GREEN}✅ SquashFS creation completed: $SQUASHFS_FILE${NC}"
        
        # Phase 2: Create ISO (automatically knows SquashFS location)
        echo -e "\n${YELLOW}=== Phase 2: Creating Bootable ISO ===${NC}"
        create_live_iso "$SQUASHFS_FILE"
        
        if [ $? -eq 0 ]; then
            echo -e "\n${GREEN}🎉 Complete workflow finished successfully!${NC}"
        else
            echo -e "\n${RED}💥 ISO creation failed!${NC}"
        fi
    else
        echo -e "\n${RED}💥 SquashFS creation failed!${NC}"
        exit 1
    fi
}

# Run main function
main "$@"
