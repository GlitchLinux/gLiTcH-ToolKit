#!/bin/bash

# Set the GTK theme to dark
export GTK_THEME=Orchis:dark

echo "╔═══════════════════════════╗"
echo "║ TOR BROWSER - AutoScript! ║"
echo "║ Browser will now download ║"
echo "║     install & start.      ║"
echo "╚═══════════════════════════╝"
cd /tmp
wget http://archive.ubuntu.com/ubuntu/pool/universe/t/torbrowser-launcher/torbrowser-launcher_0.3.7-2_amd64.deb
sudo dpkg -i torbrowser-launcher_0.3.7-2_amd64.deb
sudo apt install -f
sudo rm torbrowser-launcher_0.3.7-2_amd64.deb

echo "kill -TERM "$PPID" && nohup torbrowser-launcher > /dev/null" > /tmp/tor-start.sh
nohup bash /tmp/tor-start.sh >/dev/null 2>&1
