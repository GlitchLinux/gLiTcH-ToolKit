#!/bin/bash

# URL of the file to download
FILE_URL="https://edef7.pcloud.com/cfZtGl5dgZb9cpdX7ZC4AmZZWlpJXkZ2ZZ2G0ZZMlhhVZ2pZuXZm7ZozZ4pZHHZwHZjJZ55ZgHZ9FZKHZWFZQHZq4iQQvkLPs7kOny6jnJEhQCs06Oy/MULTIBOOT-gLiTcH-Custom-60MB.img"

# Destination file name
FILE_NAME="MULTIBOOT-gLiTcH-Custom-60MB.img"

# Download the file
echo "Downloading file..."
wget -O "$FILE_NAME" "$FILE_URL"

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to download the file."
    exit 1
fi

echo "File downloaded successfully: $FILE_NAME"

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

# Ensure the device exists
if [[ ! -b $TARGET_DEVICE ]]; then
    echo "Error: $TARGET_DEVICE is not a valid block device."
    exit 1
fi

# Use dd to flash the image to the device
echo "Flashing $FILE_NAME to $TARGET_DEVICE..."
sudo dd if="$FILE_NAME" of="$TARGET_DEVICE" bs=4M status=progress conv=fsync

if [[ $? -ne 0 ]]; then
    echo "Error: Failed to flash the image to the device."
    exit 1
fi

echo "Flashing completed successfully."

# Optionally, sync to ensure data is written
echo "Syncing data to device..."
sudo sync

echo "Done!"
