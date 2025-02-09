#!/bin/bash
set -e  # Exit immediately if a command fails

# Clone the repository
git clone https://github.com/GlitchLinux/GRUB-MULTIBOOT.git
cd GRUB-MULTIBOOT

# Extract the 7z file (requires p7zip-full package)
FILE_NAME="MULTIBOOT-gLiTcH-Custom-60MB.img"
7z x MULTIBOOT-gLiTcH-Custom-60MB.7z

# Prompt user for the target device
echo "Enter the target device (e.g., /dev/sdX):"
read -r TARGET_DEVICE

# Confirm the device with the user
echo "You have selected $TARGET_DEVICE. This will overwrite all data on this device!"
read -p "Are you sure you want to continue? (yes/no): " CONFIRM

if [[ "$CONFIRM" != "yes" ]]; then
    echo "Operation canceled by the user."
    exit 1
fi

# Ensure the device exists and is a block device
if [[ ! -b $TARGET_DEVICE ]]; then
    echo "Error: $TARGET_DEVICE is not a valid block device."
    exit 1
fi

# Use dd to flash the image to the device
echo "Flashing $FILE_NAME to $TARGET_DEVICE..."
sudo dd if="$FILE_NAME" of="$TARGET_DEVICE" bs=4M status=progress conv=fsync

echo "Flashing completed successfully."

# Ensure all data is written
echo "Syncing data to device..."
sudo sync

echo "Done!"
