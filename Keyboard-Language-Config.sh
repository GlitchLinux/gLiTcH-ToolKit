#!/bin/bash

# Author: GlitchLinux
# Description:  Select and apply keyboard layout in Debian-based distros.

apt update 
apt install console-setup keyboard-configuration -y
dpkg-reconfigure keyboard-configuration 
