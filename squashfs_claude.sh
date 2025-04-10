#!/bin/bash
set -e

# Install required packages if not present
if ! command -v mksquashfs &> /dev/null; then
    echo "Installing squashfs-tools..."
    apt-get update && apt-get install -y squashfs-tools
fi

# Create output directory
OUTPUT_DIR="$HOME/debian_live"
mkdir -p "$OUTPUT_DIR"

# Create a list of directories to exclude
cat > /tmp/squashfs-exclude.txt << EOF
/proc/*
/sys/*
/tmp/*
/dev/*
/run/*
/mnt/*
/media/*
/lost+found
/var/cache/apt/archives/*
/var/log/*
/var/tmp/*
/home/*/.cache/*
/root/.cache/*
/boot/grub/*
/swapfile
/etc/fstab
$OUTPUT_DIR/*
EOF

# Clean up apt cache to reduce image size
apt-get clean

# Create the squashfs file
echo "Creating filesystem.squashfs (this may take a while)..."
sudo mksquashfs / "$OUTPUT_DIR/filesystem.squashfs" -comp xz -ef /tmp/squashfs-exclude.txt -wildcards

echo "SquashFS image created at: $OUTPUT_DIR/filesystem.squashfs"
echo "Size: $(du -h "$OUTPUT_DIR/filesystem.squashfs" | cut -f1)"

# Cleanup
rm /tmp/squashfs-exclude.txt

echo "Note: To make this bootable, you'll need to set up a proper boot structure with initramfs and bootloader"
