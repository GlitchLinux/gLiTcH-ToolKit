#!/bin/bash
sudo apt install -y wget;
wget -O- https://sourceforge.net/projects/boot-repair/files/key.gpg | sudo tee /etc/apt/keyrings/boot-repair.gpg;
echo 'deb [signed-by=/etc/apt/keyrings/boot-repair.gpg] https://ppa.launchpadcontent.net/yannubuntu/boot-repair/ubuntu noble main' | sudo tee /etc/apt/sources.list.d/boot-repair.list;
sudo apt update && sudo apt install -y boot-repair
