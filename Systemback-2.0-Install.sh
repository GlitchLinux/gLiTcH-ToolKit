#!/bin/bash

cd /tmp

sudo mkdir systemback && cd systemback 

sudo wget https://github.com/GlitchLinux/systemback-2.0/raw/refs/heads/main/SystemBack_2_Deb+Source.tar && sleep 2

sudo tar xvf SystemBack_2_Deb+Source.tar && sudo apt update

sudo dpkg --force-all -i systemback-cli_2.0_amd64.deb systemback_2.0_amd64.deb  systemback-locales_2.0_all.deb systemback-efiboot-amd64_2.0_all.deb libsystemback_2.0_amd64.deb

sudo apt install -f -y

sudo dpkg --force-all -i systemback-cli_2.0_amd64.deb systemback_2.0_amd64.deb  systemback-locales_2.0_all.deb systemback-efiboot-amd64_2.0_all.deb libsystemback_2.0_amd64.deb

cd /tmp && sudo rm -r systemback

echo"Systemback 2.0 Have Been Sucessfully Installed!"

cd && exit
