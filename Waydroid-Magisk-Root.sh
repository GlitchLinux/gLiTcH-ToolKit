#!/bin/bash

sudo apt update && sudo apt install libdbus-1-dev libssl-dev pkg-config build-essential liblzma5 libbz2-1.0 libssl3 libdbus-1-3 libsystemd0 libcap2 -y

cd /tmp

wget https://github.com/mistrmochov/WaydroidSU/releases/download/0.1.2/wsu-0.1.2-1-x86_64-ubuntu_22+_or_debian.deb

sudo apt install ./wsu-0.1.2-1-x86_64-ubuntu_22+_or_debian.deb

clear 
echo "Dependencies and Waydroid-Sudo Installed"
echo "Starting Magisk Wsu Root in 5 seconds" 
echo ""

sleep 5

sudo wsu install

echo ""
echo "When waydroid restarted, run 'sudo wsu setup'"
echo ""

read -p 'Hit any key to exit'
