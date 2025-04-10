#!/bin/bash
apt update
wget --no-check-certificate https://github.com/fastfetch-cli/fastfetch/releases/download/2.36.1/fastfetch-linux-amd64.deb
sudo dpkg -i fastfetch-linux-amd64.deb
rm fastfetch-linux-amd64.deb
