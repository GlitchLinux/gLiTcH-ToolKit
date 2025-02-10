#!/bin/bash

# Update package list and install Flatpak
sudo apt update
sudo apt install -y flatpak

# Add Flathub repository if not already added
flatpak remote-add --if-not-exists flathub https://flathub.org/repo/flathub.flatpakrepo

echo "Flatpak installation and configuration completed."

exit
