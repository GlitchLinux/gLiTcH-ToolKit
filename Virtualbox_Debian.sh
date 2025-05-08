#!/bin/bash
cd /tmp
sudo apt update && sudo apt --reinstall install gcc-12 cpp-12
wget https://download.virtualbox.org/virtualbox/7.1.6/virtualbox-7.1_7.1.6-167084~Debian~bookworm_amd64.deb
wget https://download.virtualbox.org/virtualbox/7.1.6/Oracle_VirtualBox_Extension_Pack-7.1.6.vbox-extpack
sudo dpkg -i virtualbox-7.1_7.1.6-167084~Debian~bookworm_amd64.deb
sudo apt install -f
sudo apt install linux-headers-$(uname -r)
sudo '/sbin/vboxconfig'
sudo adduser $USER vboxusers
