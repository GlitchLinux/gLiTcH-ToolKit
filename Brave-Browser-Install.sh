#!/bin/bash

sudo apt install curl -y

sudo curl -fsSLo /usr/share/keyrings/brave-browser-nightly-archive-keyring.gpg https://brave-browser-apt-nightly.s3.brave.com/brave-browser-nightly-archive-keyring.gpg

sudo curl -fsSLo /etc/apt/sources.list.d/brave-browser-nightly.sources https://brave-browser-apt-nightly.s3.brave.com/brave-browser.sources

sudo apt update

sudo apt install brave-origin -y

xterm -e 'brave-origin' &

sleep 1 && sudo pkill xterm

exit
