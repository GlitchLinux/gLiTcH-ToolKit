#!/bin/bash
cd /tmp
wget https://download.virtualbox.org/virtualbox/7.1.6/virtualbox-7.1_7.1.6-167084~Debian~bookworm_amd64.deb
sudo dpkg -i virtualbox-7.1_7.1.6-167084~Debian~bookworm_amd64.deb
sudo apt install -f
sudo adduser $USER vboxusers
