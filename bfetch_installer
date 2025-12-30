#!/bin/bash

cd /tmp
wget https://raw.githubusercontent.com/GlitchLinux/BORDERIZE/refs/heads/main/borderize
sudo chmod +x borderize && sudo mv borderize /usr/local/bin/
git clone https://github.com/GlitchLinux/BonsaiFetch.git
cd BonsaiFetch/bfetch
sudo cp -r * /usr/local/bin/
sudo chmod +x /usr/local/bin/bfetch
sudo chmod +x /usr/local/bin/bfetch.cfg 
sudo chmod 777 /usr/local/bin/bfetch.cfg 
sudo chmod 777 /usr/local/bin/bfetch
sudo chmod -R +x /usr/local/bin/bfetch-modules/
bfetch
