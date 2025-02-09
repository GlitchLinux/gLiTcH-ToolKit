#!/bin/bash

# Script to install essential cryptography and LUKS packages on Debian/Ubuntu

echo "Updating package lists..."
sudo apt update

echo "Installing essential cryptography and LUKS packages..."
sudo apt install -y cryptsetup cryptsetup-initramfs lvm2 gnupg gpgv libpam-mount secure-delete wipe rng-tools haveged openssl libssl-dev pinentry-curses pinentry-tty pinentry-qt dmsetup hdparm smartmontools

echo "Cleaning up..."
sudo apt autoremove -y

echo "All essential packages for cryptography and LUKS functionality have been installed."
