#!/bin/bash
sudo apt update && sudo apt install wget git parted -y
cd /tmp
wget glitchlinux.wtf/apps
sudo bash apps
sudo rm /tmp/apps
apps
sudo adduser x
sudo adduser x sudo
echo 'echo "x      ALL=(ALL) NOPASSWD: ALL" >> /etc/sudoers' > /tmp/visudo
sudo bash /tmp/visudo
