#!/bin/bash
clear
cd /tmp
wget -O gdiskboot.sh https://raw.githubusercontent.com/GlitchLinux/Gdisk/refs/heads/main/boot/Gdisk-Installer/gdiskboot.sh
sudo bash gdiskboot.sh
sudo rm gdiskboot.sh
cd ~
