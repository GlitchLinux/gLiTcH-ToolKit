#!/bin/bash

# Create sparky.list file
echo "Creating /etc/apt/sources.list.d/sparky.list..."
sudo touch /etc/apt/sources.list.d/sparky.list
echo "deb [signed-by=/usr/share/keyrings/sparky.gpg.key] https://repo.sparkylinux.org/ orion main" >> /etc/apt/sources.list.d/sparky.list
echo "deb-src [signed-by=/usr/share/keyrings/sparky.gpg.key] https://repo.sparkylinux.org/ orion main >> /etc/apt/sources.list.d/sparky.list

echo "deb [signed-by=/usr/share/keyrings/sparky.gpg.key] https://repo.sparkylinux.org/ core main" >> /etc/apt/sources.list.d/sparky.list
echo "deb-src [signed-by=/usr/share/keyrings/sparky.gpg.key] https://repo.sparkylinux.org/ core main" >> /etc/apt/sources.list.d/sparky.list


# Create preferences file
sudo touch etc/apt/preferenc/es.d/sparky
echo "Package: *" >> etc/apt/preferenc/es.d/sparky
echo "Pin: release o=SparkyLinux" >> etc/apt/preferenc/es.d/sparky
echo "Pin-Priority: 1001 >> etc/apt/preferenc/es.d/sparky

# Try to get the latest keyring package
cd /tmp
sudo wget -O - https://sourceforge.net/projects/sparkylinux/files/repo/sparky.gpg.key | sudo tee /usr/share/keyrings/sparky.gpg.key

apt update 

echo "Sparky repository setup complete."
