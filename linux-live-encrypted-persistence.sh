#!/bin/bash

# Prompt the user to enter the partition
echo "Please enter the partition (e.g., /dev/sdxx):"
read PARTITION

if [ -z "$PARTITION" ]; then
    echo "No partition entered. Exiting."
    exit 1
fi

# Check if the partition exists
if ! sudo fdisk -l | grep -q "$PARTITION"; then
    echo "Partition $PARTITION does not exist. Exiting."
    exit 1
fi
# Perform the steps to encrypt and set up the partition
set -e

echo "Starting disk operations on $PARTITION"
sudo fdisk -l

echo "Formatting $PARTITION with LUKS"
sudo cryptsetup --verbose --verify-passphrase luksFormat $PARTITION

echo "Opening LUKS partition"
sudo cryptsetup luksOpen $PARTITION encData

echo "Creating ext4 filesystem on encrypted partition"
sudo mkfs.ext4 /dev/mapper/encData

echo "Labeling filesystem as persistence"
sudo e2label /dev/mapper/encData persistence

echo "Creating mount point /mnt/encData"
sudo mkdir -p /mnt/encData

echo "Mounting encrypted partition"
sudo mount /dev/mapper/encData /mnt/encData

echo "Changing directory to /mnt/encData"
cd /mnt/encData

echo "Creating persistence.conf"
sudo touch persistence.conf

echo "Editing persistence.conf"
sudo bash -c 'echo "/ union" > persistence.conf'

echo "Returning to home directory"
cd ~

echo "Unmounting encrypted partition"
sudo umount /dev/mapper/encData

echo "Closing LUKS partition"
sudo cryptsetup luksClose /dev/mapper/encData

echo "Disk setup completed successfully."
