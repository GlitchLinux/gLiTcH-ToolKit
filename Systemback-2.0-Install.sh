#!/bin/bash

cd /tmp

sudo mkdir systemback && cd systemback 

sudo wget https://github.com/GlitchLinux/systemback-2.0/raw/refs/heads/main/SystemBack_2_Deb+Source.tar && sleep 2

sudo tar xvf SystemBack_2_Deb+Source.tar

cd Install

sudo dpkg --force-all -i *deb

sudo apt update && sudo apt install -f -y

echo"Systemback 2.0 Have Been Sucessfully Installed!"

sleep 3 && cd && exit
