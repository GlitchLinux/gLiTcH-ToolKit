#!/bin/bash
set -e

# Install required packages
sudo apt-get update
sudo apt-get install -y squashfs-tools rsync

# Setup directories
WORK_DIR="/tmp/squashfs_build"
OUTPUT_DIR="$HOME/debian_live"
mkdir -p "$WORK_DIR"
mkdir -p "$OUTPUT_DIR"

# Create a clean copy of the system, excluding problematic directories
echo "Creating system snapshot (this may take a while)..."
sudo rsync -aAXv /* "$WORK_DIR" \
    --exclude={/dev/*,/proc/*,/sys/*,/tmp/*,/run/*,/mnt/*,/media/*,/lost+found,/var/cache/apt/archives/*} \
    --exclude={/var/log/*,/var/tmp/*,/home/*/.cache/*,/root/.cache/*,/swapfile,/boot/grub/*} \
    --exclude="$OUTPUT_DIR/*" \
    --exclude="$WORK_DIR/*"

# Create the squashfs from the clean copy
echo "Creating filesystem.squashfs..."
sudo mksquashfs "$WORK_DIR" "$OUTPUT_DIR/filesystem.squashfs" -comp xz -noappend

# Cleanup
sudo rm -rf "$WORK_DIR"

echo "SquashFS image created at: $OUTPUT_DIR/filesystem.squashfs"
echo "Size: $(du -h "$OUTPUT_DIR/filesystem.squashfs" | cut -f1)"
echo "Note: To make this bootable, you'll need to set up a proper boot structure with initramfs and bootloader"
