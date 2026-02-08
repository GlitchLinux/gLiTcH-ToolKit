#!/bin/bash

cd /usr/local/bin
sudo rm -f PATH
sudo wget https://raw.githubusercontent.com/GlitchLinux/PATH/refs/heads/main/PATH 
sudo chmod +x PATH
sudo chmod 777 PATH
clear
echo ""
echo "PATH was Installed to system"
echo "============================"
echo "PATH -- Displays full paths "
echo "Usage: PATH [--list] <target>"
echo "============================"
sleep 15
exit
