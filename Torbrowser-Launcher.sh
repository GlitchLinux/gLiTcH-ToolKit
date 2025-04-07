#!/bin/bash
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
torbrowser-launcher
end
