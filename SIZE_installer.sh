#!/bin/bash

cd /usr/local/bin
sudo rm -f size
sudo wget https://raw.githubusercontent.com/GlitchLinux/size/refs/heads/main/size 
sudo chmod +x size
sudo chmod 777 size
echo ""
echo "size Utility Installed to system"
echo ""
sleep 8
exit
