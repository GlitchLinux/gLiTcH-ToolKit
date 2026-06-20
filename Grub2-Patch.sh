#!/bin/bash
# ===============================================================
#  Grub2-Patch.sh - Patch GRUB2 with a1ive's map/wimboot support
# ---------------------------------------------------------------

cd /tmp
git clone https://github.com/GlitchLinux/grub2-patch.git
cd grub2-patch && sudo chmod +x Grub2-Patch.sh
sudo ./Grub2-Patch.sh
