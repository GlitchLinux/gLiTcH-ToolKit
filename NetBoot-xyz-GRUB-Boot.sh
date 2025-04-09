#!/bin/bash

# Install grub-imageboot
apt update && apt install -y grub-imageboot

# Download netboot.xyz ISO
mkdir /boot/images
cd /boot/images
wget https://boot.netboot.xyz/ipxe/netboot.xyz.iso

# Update GRUB menu to include this ISO
update-grub2
