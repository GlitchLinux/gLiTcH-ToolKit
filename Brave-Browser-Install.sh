#!/bin/bash

ROOT_UID=0
PATH=$PATH
lolcat=/usr/games/lolcat

echo "Brave-Origin-Nightly - Installer" > /tmp/brave-banner

clear

cat /tmp/brave-banner | borderize | lolcat

sudo apt install curl -y

clear

cat /tmp/brave-banner | borderize | lolcat

sudo curl -fsSLo /usr/share/keyrings/brave-browser-nightly-archive-keyring.gpg https://brave-browser-apt-nightly.s3.brave.com/brave-browser-nightly-archive-keyring.gpg

clear

cat /tmp/brave-banner | borderize | lolcat

sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-nightly.sources https://brave-browser-apt-nightly.s3.brave.com/brave-browser.sources

clear

cat /tmp/brave-banner | borderize | lolcat

sudo apt update

clear

cat /tmp/brave-banner | borderize | lolcat

sudo apt install brave-origin-nightly -y

clear

cat /tmp/brave-banner | borderize | lolcat

xterm -e 'brave-origin' &

sleep 1 && sudo pkill xterm

clear

echo "Brave-Origin-Nightly - Installed to System!" > /tmp/brave-banner

cat /tmp/brave-banner | borderize | lolcat

echo " " 

read p ' '
