#!/bin/bash

sudo apt update && sudo apt install -y calamares calamares-settings-debian
sudo rm -r /etc/calamares/branding/debian/
sudo rm  /etc/calamares/settings.conf
sudo cp -r /home/x/txt.and.sh/calamares/branding/debian/ /etc/calamares/branding/
sudo cp -r /home/x/txt.and.sh/calamares/settings.conf /etc/calamares/
sudo calamares
