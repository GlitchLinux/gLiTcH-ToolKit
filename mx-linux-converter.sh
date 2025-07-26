#!/bin/bash

cd /tmp
sudo mv /etc/apt/sources.list /home/sources.list-bonsai-backup 
wget https://glitchlinux.wtf/FILES/MX-convert.zip
unzip MX-convert.zip
cd /tmp/mx-apt/
sudo cp -f apt /etc/apt 
cd /tmp/mx-os-docs/
sudo cp -f * /etc/
cd /tmp
wget https://glitchlinux.wtf/FILES/MX-DEBS.zip
unzip MX-DEBS.zip
cd MX-DEBS
sudo apt update && sudo dpkg --force-all -i *
sudo apt install -f -y
sudo dpkg --force-all -i *
sudo bash /usr/local/bin/jwm-restart.sh

echo "System Converted to MX-/-Bonsai Hybrid distro"
echo "Run: sudo apt-get full-upgrade, for the complete MX dpkg base"
sleep 15 && exit
