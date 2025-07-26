#!/bin/bash

# Install TOR through tor-projects own repo

# Set the GTK theme to dark
export GTK_THEME=Orchis:dark

sudo apt update && sudo apt install apt-transport-tor gnupg -y

sudo mv /etc/apt/sources.list /tmp/sources.list
sudo mv /etc/apt/sources.list.d/ /tmp/sources.list.d/

sudo xterm -e 'echo "deb [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] tor+http://apow7mjfryruh65chtdydfmqfpj5btws7nbocgtaovhvezgccyjazpqd.onion/torproject.org bookworm main" > /etc/apt/sources.list'

echo ""
cat /etc/apt/sources.list && sleep 3
echo ""

sudo wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | sudo tee /usr/share/keyrings/deb.torproject.org-keyring.gpg >/dev/null

sudo apt update && sudo apt install tor deb.torproject.org-keyring -y

cd /tmp && sudo wget http://ftp.us.debian.org/debian/pool/contrib/t/torbrowser-launcher/torbrowser-launcher_0.3.7-3_amd64.deb
sudo dpkg --force-all -i torbrowser-launcher_0.3.7-3_amd64.deb && sudo apt install -f -y
sudo dpkg --force-all -i torbrowser-launcher_0.3.7-3_amd64.deb && sudo apt install -f
echo ""
which torbrowser-launcher
echo ""
sleep 5 && sudo rm -f /tmp/torbrowser-launcher_0.3.7-3_amd64.deb

sudo rm -f /etc/apt/sources.list
sudo mv /tmp/sources.list /etc/apt/sources.list
sudo mv /tmp/sources.list.d/ /etc/apt/sources.list.d/

ls /etc/apt/sources.list.d/ && ls /etc/apt/sources.list

echo ""
echo "Tor & Tor Browser installed, onion repo used for install have been deactivated and original sources.list is restored "
echo ""
sleep 10

which tor && which torbrowser-launcher

exit

