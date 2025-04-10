#!/usr/bin/env bash
# Self-contained SquashFS Creator - Creates all required files and directories

version="squashfs-creator-2.0"
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

# Create all required directories and files
setup_environment() {
    echo "Setting up required directories and files..."
    
    # Create working directories
    mkdir -p "$WORK_DIR/myfs"
    mkdir -p "$SQUASHFS_DIR"
    mkdir -p "$CONFIG_DIR"
    
    # Create default excludes file if missing
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
    
    # Create default config file if missing
    if [[ ! -f "$CONFIG_FILE" ]]; then
        cat > "$CONFIG_FILE" << EOF
# SquashFS Creator Configuration

# Directory paths
work_dir="$WORK_DIR"
squashfs_dir="$SQUASHFS_DIR"
snapshot_excludes="$EXCLUDES_FILE"
error_log="$ERROR_LOG"

# Rsync options
rsync_option1="--delete"
rsync_option2="--delete-excluded"
rsync_option3="--force"

# mksquashfs options
mksq_opt="-comp xz -b 1M -no-xattrs -no-recovery"

# Behavior options
limit_cpu="no"
stamp="datetime"          # "datetime" or "sequential"
make_sha256sum="yes"
save_work="no"
edit_before_squash="no"
EOF
    fi
    
    # Load the configuration
    source "$CONFIG_FILE"
}

# Check for required commands
check_dependencies() {
    local missing=()
    
    for cmd in rsync mksquashfs sha256sum; do
        if ! command -v "$cmd" >/dev/null 2>&1; then
            missing+=("$cmd")
        fi
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        echo "ERROR: Missing required commands: ${missing[*]}"
        echo "Try: apt-get install rsync squashfs-tools coreutils"
        exit 1
    fi
}

# Copy the filesystem
copy_filesystem() {
    echo "Copying filesystem (this may take a while)..."
    
    local pid=""
    if [[ "$limit_cpu" = "yes" ]] && command -v cpulimit >/dev/null; then
        cpulimit -e rsync -l "$limit" &
        pid=$!
    fi
    
    rsync -a / "$WORK_DIR/myfs/" \
        --exclude="$WORK_DIR" \
        --exclude="$SQUASHFS_DIR" \
        --exclude-from="$snapshot_excludes" \
        ${rsync_option1} ${rsync_option2} ${rsync_option3}
    
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
}

# Clean the copied filesystem
clean_filesystem() {
    echo "Cleaning filesystem copy..."
    
    # Truncate logs
    find "$WORK_DIR/myfs/var/log" -type f -exec truncate -s 0 {} \;
    
    # Clear machine-id
    : > "$WORK_DIR/myfs/etc/machine-id"
    
    # Create essential device files
    mkdir -p "$WORK_DIR/myfs/dev"
    mknod -m 622 "$WORK_DIR/myfs/dev/console" c 5 1
    mknod -m 666 "$WORK_DIR/myfs/dev/null" c 1 3
    mknod -m 666 "$WORK_DIR/myfs/dev/zero" c 1 5
    mknod -m 666 "$WORK_DIR/myfs/dev/ptmx" c 5 2
    mknod -m 666 "$WORK_DIR/myfs/dev/tty" c 5 0
    mknod -m 444 "$WORK_DIR/myfs/dev/random" c 1 8
    mknod -m 444 "$WORK_DIR/myfs/dev/urandom" c 1 9
}

# Create the squashfs image
create_squashfs() {
    echo "Creating SquashFS image..."
    
    # Generate output filename
    local timestamp=$(date +%Y%m%d_%H%M)
    local squashfile="filesystem-$timestamp.squashfs"
    
    local pid=""
    if [[ "$limit_cpu" = "yes" ]] && command -v cpulimit >/dev/null; then
        cpulimit -e mksquashfs -l "$limit" &
        pid=$!
    fi
    
    mksquashfs "$WORK_DIR/myfs" "$SQUASHFS_DIR/$squashfile" $mksq_opt
    
    [[ -n "$pid" ]] && kill "$pid" 2>/dev/null
    
    # Create checksum if enabled
    if [[ "$make_sha256sum" = "yes" ]]; then
        (cd "$SQUASHFS_DIR" && sha256sum "$squashfile" > "$squashfile.sha256")
    fi
    
    echo "SquashFS created: $SQUASHFS_DIR/$squashfile"
}

# Clean up working files
cleanup() {
    if [[ "$save_work" = "no" ]]; then
        echo "Cleaning up work directory..."
        rm -rf "$WORK_DIR/myfs"
    fi
}

# Main execution flow
main() {
    # Set up everything needed
    setup_environment
    check_dependencies
    
    # Do the actual work
    copy_filesystem
    clean_filesystem
    
    if [[ "$edit_before_squash" = "yes" ]]; then
        echo "Filesystem copied to $WORK_DIR/myfs"
        echo "You can now inspect/modify it before SquashFS creation"
        read -p "Press Enter to continue or Ctrl+C to abort..."
    fi
    
    create_squashfs
    cleanup
    
    echo "Operation completed successfully!"
    echo "Output files are in: $SQUASHFS_DIR"
}

# Run main function and log errors
main 2>&1 | tee -a "$ERROR_LOG"
