#!/bin/bash

cd /home/$USER/
sudo rm -f grub-efi-wrapper-fix.sh
sudo wget https://raw.githubusercontent.com/GlitchLinux/gLiTcH-ToolKit/refs/heads/main/grub-efi-wrapper-fix.sh
sleep 3 && sudo rm -f /tmp/wrapper.sh
echo 'sudo bash /home/x/grub-efi-wrapper-fix.sh && sleep 8' > /tmp/wrapper.sh
echo 'nohup sudo bash /usr/sbin/efi-directory-correction.sh sudo update-grub && sudo bash /usr/sbin/grub-install && sudo update-grub' >> /tmp/wrapper.sh
nohup sudo bash /tmp/wrapper.sh > /dev/null &
sudo bash /usr/sbin/grub-install && sudo update-grub
sleep 2 && ls /boot/efi/EFI && sleep 3
echo "cleaning any invalid EFI directories and createing /boot/*.efi"
sudo mkdir /boot/efi/EFI/BONSAI-EFI
sudo cp -f /boot/efi/EFI/Bonsai/* /boot/efi/EFI/BONSAI-EFI/
sudo cp -f /boot/efi/EFI/*ebian/* /boot/efi/EFI/BONSAI-EFI/
sudo cp -f /boot/efi/EFI/BOOT/* /boot/efi/EFI/BONSAI-EFI/
sudo cp -f /boot/efi/EFI/boot/* /boot/efi/EFI/BONSAI-EFI/
ls /boot/efi/EFI/BONSAI-EFI/ && sleep 6
sudo rm -r -f /boot/efi/EFI/BOOT/
sudo rm -r -f /boot/efi/EFI/*ebian/
sudo rm -r -f /boot/efi/EFI/Boot/
sudo rm -r -f /boot/efi/EFI/Bonsai/
sudo cp -r /boot/efi/EFI/BONSAI-EFI/ /boot/efi/EFI/BOOT
sudo rm -r /boot/efi/EFI/BONSAI-EFI/
sudo update-grub && sleep 2
eCho "Any invalid EFI directories have been corrected.."
tree /boot/efi/EFI/ && sleep 6
read -p "Hit enter to finish"
