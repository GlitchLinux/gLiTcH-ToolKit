#!/bin/bash

cd /usr/local/bin
sudo rm -f PATH
sudo wget https://raw.githubusercontent.com/GlitchLinux/PATH/refs/heads/main/PATH 
sudo chmod +x PATH
sudo chmod 777 PATH
echo ""
echo "PATH Utility Installed to system"
echo ""
sleep 8
exit
