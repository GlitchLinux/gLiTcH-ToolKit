#!/bin/bash
cd /tmp
sudo rm -rf gdisk-v3-repo/ 
wget -q https://raw.githubusercontent.com/GlitchLinux/Gdisk/refs/heads/main/boot/Gdisk-Installer/gdisk-v3-installer.sh -O gdisk-v3-installer.sh 
sudo bash gdisk-v3-installer.sh
