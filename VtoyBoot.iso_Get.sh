#!/bin/bash
cd /tmp
wget -O vtoyboot-1.0.36.iso -q https://github.com/ventoy/vtoyboot/releases/download/v1.0.36/vtoyboot-1.0.36.iso
mkdir iso
sudo mount vtoyboot-1.0.36.iso iso/
sudo cp -r iso/* /etc/
