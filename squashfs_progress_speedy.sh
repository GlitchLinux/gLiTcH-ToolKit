#!/usr/bin/env bash
# Optimized SquashFS Creator with better performance

version="squashfs-creator-2.1"
TEXTDOMAIN=squashfs-creator

# Check for root
if [[ $(id -u) -ne 0 ]]; then
    echo "ERROR: This script must be run as root"
    exit 1
fi

# Configuration - Built-in defaults
WORK_DIR="/tmp/squashfs-work"
SQUASHFS_DIR="/squashfs-output"
CONFIG_DIR="/etc/squashfs-creator"
EXCLUDES_FILE="$CONFIG_DIR/excludes.txt"
CONFIG_FILE="$CONFIG_DIR/squashfs-creator.conf"
ERROR_LOG="/var/log/squashfs-creator.log"

# Performance tuning defaults
CPU_CORES=$(nproc)
RSYNC_OPTS="-a --no-whole-file --inplace"
MKSQUASHFS_OPTS="-comp zstd -Xcompression-level 15 -b 1M -no-xattrs -no-recovery -processors $CPU_CORES"

# Progress display functions
progress_start() {
    echo -n "[$(date +%H:%M:%S)] $1... "
    if [[ "$2" == "spinner" ]]; then
        spinner &
        spinner_pid=$!
    fi
}

progress_end() {
    if [[ -n "$spinner_pid" ]]; then
        kill "$spinner_pid" 2>/dev/null
        unset spinner_pid
        echo -ne "\b\b\b"
    fi
    if [[ "$1" == "OK" ]]; then
        echo -e "\e[32m✓\e[0m"
    elif [[ "$1" == "SKIPPED" ]]; then
        echo -e "\e[33m⤷\e[0m"
    else
        echo -e "\e[31m✗\e[0m"
    fi
}

spinner() {
    local i=0
    local sp='/-\|'
    while sleep 0.1; do
        printf "\b${sp:i++%${#sp}:1}"
    done
}

# Create all required directories and files
setup_environment() {
    progress_start "Setting up environment" spinner
    
    mkdir -p "$WORK_DIR/myfs" 2>/dev/null
    mkdir -p "$SQUASHFS_DIR" 2>/dev/null
    mkdir -p "$CONFIG_DIR" 2>/dev/null
    
    if [[ ! -f "$EXCLUDES_FILE" ]]; then
        cat > "$EXCLUDES_FILE" << 'EOF'
# Default excludes list for squashfs-creator
/proc/*
/sys/*
/dev/*
/run/*
/tmp/*
/var/tmp/*
/var/run/*
/var/lock/*
/media/*
/mnt/*
/lost+found
/home/*/.cache/*
/home/*/.thumbnails/*
/var/cache/apt/archives/*.deb
/var/lib/dhcp/*
*.swp
*.bak
*.tmp
EOF
    fi
    
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << EOF
# SquashFS Creator Configuration

# Directory paths
work_dir="$WORK_DIR"
squashfs_dir="$SQUASHFS_DIR"
snapshot_excludes="$EXCLUDES_FILE"
error_log="$ERROR_LOG"

# Performance options
rsync_options="$RSYNC_OPTS"
mksquashfs_options="$MKSQUASHFS_OPTS"
use_zstd="yes"          # "yes" for zstd (faster), "no" for xz (smaller)
parallel_compression="yes"

# Behavior options
make_sha256sum="yes"
save_work="no"
edit_before_squash="no"
EOF
    fi
    
    source "$CONFIG_FILE"
    
    # Apply performance settings
    if [[ "$use_zstd" == "yes" ]]; then
        MKSQUASHFS_OPTS="${MKSQUASHFS_OPTS/-comp * /-comp zstd }"
    else
        MKSQUASHFS_OPTS="${MKSQUASHFS_OPTS/-comp * /-comp xz }"
    fi
    
    if [[ "$parallel_compression" != "yes" ]]; then
        MKSQUASHFS_OPTS="${MKSQUASHFS_OPTS/-processors * /-processors 1 }"
    fi
    
    progress_end "OK"
}

# Check for required commands
check_dependencies() {
    progress_start "Checking dependencies" spinner
    local missing=()
    
    for cmd in rsync mksquashfs sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        progress_end "FAIL"
        echo "ERROR: Missing required commands: ${missing[*]}"
        echo "Try: apt-get install rsync squashfs-tools coreutils"
        exit 1
    else
        progress_end "OK"
    fi
}

# Copy the filesystem with better rsync options
copy_filesystem() {
    echo -e "\n[$(date +%H:%M:%S)] Starting filesystem copy (this may take a while)"
    echo "  → Using $(nproc) CPU cores for parallel operations"
    echo "  → Rsync options: $rsync_options"
    
    progress_start "Calculating initial size" spinner
    local src_size=$(du -sh / 2>/dev/null | awk '{print $1}')
    progress_end "OK"
    echo "  → Source size: $src_size"

    progress_start "Copying filesystem" spinner
    rsync $rsync_options / "$WORK_DIR/myfs/" \
        --exclude="$WORK_DIR" \
        --exclude="$SQUASHFS_DIR" \
        --exclude-from="$snapshot_excludes" \
        --info=progress2 \
        --no-inc-recursive 2>&1 | \
        awk '/^ / {print "\r  → Progress: "$0; fflush()}'
    
    progress_end "OK"
    echo "  → Copy completed at $(date +%H:%M:%S)"
}

# Clean the copied filesystem
clean_filesystem() {
    progress_start "Cleaning filesystem copy" spinner
    
    # Fast log truncation
    find "$WORK_DIR/myfs/var/log" -type f -exec truncate -s 0 {} + 2>/dev/null
    
    # Essential device files
    mkdir -p "$WORK_DIR/myfs/dev" 2>/dev/null
    for node in console null zero ptmx tty random urandom; do
        [[ -e "$WORK_DIR/myfs/dev/$node" ]] || {
            case $node in
                console) mknod -m 622 "$WORK_DIR/myfs/dev/console" c 5 1 ;;
                null)    mknod -m 666 "$WORK_DIR/myfs/dev/null" c 1 3 ;;
                zero)    mknod -m 666 "$WORK_DIR/myfs/dev/zero" c 1 5 ;;
                ptmx)    mknod -m 666 "$WORK_DIR/myfs/dev/ptmx" c 5 2 ;;
                tty)     mknod -m 666 "$WORK_DIR/myfs/dev/tty" c 5 0 ;;
                random)  mknod -m 444 "$WORK_DIR/myfs/dev/random" c 1 8 ;;
                urandom) mknod -m 444 "$WORK_DIR/myfs/dev/urandom" c 1 9 ;;
            esac
        } 2>/dev/null
    done
    
    progress_end "OK"
}

# Create the squashfs image with performance options
create_squashfs() {
    local timestamp=$(date +%Y%m%d_%H%M)
    local squashfile="filesystem-$timestamp.squashfs"
    
    echo -e "\n[$(date +%H:%M:%S)] Creating SquashFS image"
    echo "  → Compression: $(echo "$MKSQUASHFS_OPTS" | grep -oP '-comp \K\S+')"
    echo "  → Using $CPU_CORES processor cores"
    echo "  → Options: $MKSQUASHFS_OPTS"
    
    progress_start "Calculating source size" spinner
    local src_size=$(du -sh "$WORK_DIR/myfs" 2>/dev/null | awk '{print $1}')
    progress_end "OK"
    echo "  → Source size: $src_size"
    
    progress_start "Compressing filesystem" spinner
    mksquashfs "$WORK_DIR/myfs" "$SQUASHFS_DIR/$squashfile" $MKSQUASHFS_OPTS -progress 2>&1 | \
        while read -r line; do
            printf "\r  → %s" "$line"
        done
    
    if [[ "$make_sha256sum" = "yes" ]]; then
        progress_start "Creating SHA256 checksum" spinner
        (cd "$SQUASHFS_DIR" && sha256sum "$squashfile" > "$squashfile.sha256")
        progress_end "OK"
    fi
    
    local final_size=$(du -h "$SQUASHFS_DIR/$squashfile" | awk '{print $1}')
    progress_end "OK"
    echo -e "\n  → SquashFS created: $SQUASHFS_DIR/$squashfile"
    echo "  → Final size: $final_size"
    echo "  → Compression completed at $(date +%H:%M:%S)"
}

# Main execution flow
main() {
    echo -e "\n\e[1mSquashFS Creator $version (Optimized)\e[0m"
    echo "===================================="
    
    setup_environment
    check_dependencies
    copy_filesystem
    clean_filesystem
    
    if [[ "$edit_before_squash" = "yes" ]]; then
        echo -e "\n\e[33m[PAUSE] Filesystem copied to $WORK_DIR/myfs\e[0m"
        read -p "Press Enter to continue or Ctrl+C to abort..."
    fi
    
    create_squashfs
    
    if [[ "$save_work" = "no" ]]; then
        progress_start "Cleaning work directory" spinner
        rm -rf "$WORK_DIR/myfs" 2>/dev/null
        progress_end "OK"
    fi
    
    echo -e "\n\e[32m[SUCCESS] Operation completed!\e[0m"
    echo "===================================="
}

main 2>&1 | tee -a "$ERROR_LOG"
