#!/bin/bash

# Check if the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root."
    exit 1
fi

# Delete all files and directories in /tmp except for the script itself
rm -rf /tmp/*

# Install required packages
apt update && apt install -y qemu-system wget qemu-utils qemu-system-gui xdotool

# Define netboot.xyz image URL and file path
netboot_url="https://boot.netboot.xyz/ipxe/netboot.xyz.img"
netboot_path="/tmp/netboot.xyz.img"

# Download netboot.xyz image to /tmp in the background
wget --progress=bar:force:noscroll -O "$netboot_path" "$netboot_url" &

# Wait for the download to complete
while [ ! -f "$netboot_path" ]; do
    sleep 1
done

# Start a VM with QEMU using the netboot.xyz file with 4GB of RAM, KVM acceleration, and CPU optimization in the background
(qemu-system-x86_64 -enable-kvm -cpu host -m 3000 -drive format=raw,file="$netboot_path" &) &

# Minimize terminal
xdotool key "super+Down"
