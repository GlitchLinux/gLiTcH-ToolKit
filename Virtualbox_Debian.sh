#!/bin/bash
cd /tmp
sudo apt update && sudo apt --reinstall install gcc-12 cpp-12 -y
wget https://download.virtualbox.org/virtualbox/7.2.14/virtualbox-7.2_7.2.14-174565~Debian~trixie_amd64.deb
wget https://download.virtualbox.org/virtualbox/7.2.14/Oracle_VirtualBox_Extension_Pack-7.2.14.vbox-extpack
sudo dpkg -i virtualbox-7.2_7.2.14-174565~Debian~trixie_amd64.deb
sudo apt install -f -y
sudo apt install linux-headers-amd64 -y
sudo '/sbin/vboxconfig'
sudo adduser $USER vboxusers
