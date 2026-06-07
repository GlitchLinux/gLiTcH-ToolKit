#!/bin/bash

cd /tmp
sudo rm -f ventoy-1.1.12-linux.tar.gz
sudo rm -rf /tmp/ventoy-1.1.12/
sudo rm -f /tmp/ventoy.log
wget https://github.com/ventoy/Ventoy/releases/download/v1.1.12/ventoy-1.1.12-linux.tar.gz
tar -xvf ventoy-1.1.12-linux.tar.gz 
sudo chmod 777 -R ventoy-1.1.12
sudo chmod +x -R ventoy-1.1.12
sudo chmod +x /tmp/ventoy-1.1.12/VentoyGUI.x86_64
setsid sudo /tmp/ventoy-1.1.12/VentoyGUI.x86_64 \
  </dev/null >/tmp/ventoy.log 2>&1 &
sudo pkill xfce4-terminal
sudo pkill xterm
exit
