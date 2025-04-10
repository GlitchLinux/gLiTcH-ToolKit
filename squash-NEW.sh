#!/bin/bash

# Script to create an optimized bootable filesystem.squashfs for Debian
# Improved version with better handling of /proc and other virtual filesystems

# Configuration
SOURCE_DIR="/"                          # Source directory to squash
OUTPUT_FILE="/home/filesystem.squashfs" # Output squashfs file
WORKING_DIR="/tmp/squashfs_work"        # Temporary working directory
COMPRESSION="xz"                        # Compression algorithm (xz, lz4, zstd, gzip, lzo)
BLOCK_SIZE="1M"                         # Block size for squashfs
THREADS=$(nproc)                        # Number of CPU threads to use

# List of directories and files to exclude
EXCLUDE_LIST=(
    # Virtual filesystems
    "/dev/*"
    "/proc/*"
    "/sys/*"
    "/run/*"
    "/tmp/*"
    
    # System directories not needed in squashfs
    "/boot/*"
    "/lost+found"
    "/mnt/*"
    "/media/*"
    "/home/*"
    "/root/*"
    
    # Cache and temporary files
    "/var/cache/*"
    "/var/tmp/*"
    "/var/log/*"
    "/var/lib/apt/lists/*"
    "/var/lib/dpkg/*-old"
    "/var/lib/systemd/*"
    
    # Documentation and development files
    "/usr/share/doc/*"
    "/usr/share/man/*"
    "/usr/share/locale/[a-df-z]*" # Keep en_US locale
    "/usr/share/locale/e[a-np-z]*"
    "/usr/share/locale/eo"
    "/usr/share/locale/l[a-np-z]*"
    "/usr/src/*"
    "/usr/include/*"
    
    # Large applications not needed in minimal system
    "/usr/lib/libreoffice/*"
    "/usr/lib/x86_64-linux-gnu/libreoffice/*"
    "/usr/share/texlive/*"
    "/usr/share/texmf/*"
    "/usr/share/gnome/*"
    "/usr/share/kde4/*"
    "/usr/share/xsessions/*"
    
    # Specific files that cause issues
    "/etc/mtab"
    "/etc/fstab"
    "/etc/hostname"
    "/etc/resolv.conf"
)

# Create the exclude file for mksquashfs
EXCLUDE_FILE=$(mktemp)
for item in "${EXCLUDE_LIST[@]}"; do
    echo "$item" >> "$EXCLUDE_FILE"
done

# Check if mksquashfs is available
if ! command -v mksquashfs &> /dev/null; then
    echo "Error: mksquashfs not found. Please install squashfs-tools."
    echo "Run: sudo apt-get install squashfs-tools"
    exit 1
fi

# Create working directory
mkdir -p "$WORKING_DIR"

echo "=============================================="
echo " Creating Optimized SquashFS Filesystem"
echo "=============================================="
echo "Source Directory: $SOURCE_DIR"
echo "Output File:      $OUTPUT_FILE"
echo "Compression:      $COMPRESSION"
echo "Block Size:       $BLOCK_SIZE"
echo "Threads:          $THREADS"
echo "----------------------------------------------"

# Create a temporary directory for the filesystem
FS_COPY="$WORKING_DIR/rootfs"
mkdir -p "$FS_COPY"

echo "Creating a copy of the filesystem without excluded files..."
rsync -a --delete --exclude-from="$EXCLUDE_FILE" "$SOURCE_DIR" "$FS_COPY" || {
    echo "Error: Failed to create filesystem copy"
    exit 1
}

# Create essential directories that were excluded but are needed
mkdir -p "$FS_COPY"/{dev,proc,sys,run,tmp}
chmod 1777 "$FS_COPY/tmp"

echo "Creating empty versions of critical files..."
touch "$FS_COPY/etc/mtab"
ln -s /proc/mounts "$FS_COPY/etc/mtab" 2>/dev/null || true
touch "$FS_COPY/etc/resolv.conf"

echo "Starting filesystem creation... (this may take several minutes)"
mksquashfs "$FS_COPY" "$OUTPUT_FILE" \
    -comp "$COMPRESSION" \
    -b "$BLOCK_SIZE" \
    -processors "$THREADS" \
    -noappend \
    -no-recovery \
    -no-progress \
    -no-exports \
    -xattrs

# Check if successful
if [ $? -eq 0 ]; then
    echo "----------------------------------------------"
    echo "Successfully created SquashFS filesystem!"
    echo "File: $OUTPUT_FILE"
    
    # Show filesystem information
    echo "Filesystem Information:"
    unsquashfs -s "$OUTPUT_FILE" | grep -E 'Compression|Block size|Filesystem size'
    
    # Get size information
    ORIG_SIZE=$(du -sh --apparent-size "$FS_COPY" | cut -f1)
    SQUASH_SIZE=$(du -h "$OUTPUT_FILE" | cut -f1)
    echo "Original size (filtered): $ORIG_SIZE"
    echo "SquashFS size:           $SQUASH_SIZE"
else
    echo "Error: Failed to create SquashFS filesystem"
    exit 1
fi

# Clean up
rm -f "$EXCLUDE_FILE"
rm -rf "$WORKING_DIR"

echo "=============================================="
echo " Done!"
echo "=============================================="
