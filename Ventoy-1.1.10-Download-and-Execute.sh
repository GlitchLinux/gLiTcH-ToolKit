#!/bin/bash

cd /tmp
sudo rm -f ventoy-1.1.10-linux.tar.gz && sudo rm -rf /tmp/ventoy-1.1.10/
wget https://github.com/ventoy/Ventoy/releases/download/v1.1.10/ventoy-1.1.10-linux.tar.gz
tar -xvf ventoy-1.1.10-linux.tar.gz 
sudo chmod 777 -R ventoy-1.1.10
sudo chmod +x -R ventoy-1.1.10
sudo chmod +x /tmp/ventoy-1.1.10/VentoyGUI.x86_64
setsid sudo /tmp/ventoy-1.1.10/VentoyGUI.x86_64 \
  </dev/null >/tmp/ventoy.log 2>&1 &
exit
