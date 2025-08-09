#!/bin/bash
cd /tmp
sudo apt update && sudo apt --reinstall install gcc-12 cpp-12
wget https://download.virtualbox.org/virtualbox/7.1.12/virtualbox-7.1_7.1.12-169651~Ubuntu~oracular_amd64.deb
sudo dpkg --force-all -i virtualbox-7.1_7.1.12-169651~Ubuntu~oracular_amd64.deb
sudo apt install -f
sudo apt install linux-headers-amd64
sudo '/sbin/vboxconfig'
sudo adduser $USER vboxusers
cd /home/x/Desktop && wget https://download.virtualbox.org/virtualbox/7.1.6/Oracle_VirtualBox_Extension_Pack-7.1.6.vbox-extpack
exit
