cd /tmp
wget https://github.com/GlitchLinux/QEMU-QuickBoot/releases/download/QEMU-QuickBoot-v1.4_amd64.deb/QEMU-QuickBoot-v1.4_amd64.deb
sudo apt update && sudo apt install -y qemu-system wget qemu-utils qemu-system-gui xdotool ovmf qemu-system zenity git orchis-gtk-theme
sudo dpkg -i QEMU-QuickBoot-v1.4_amd64.deb && sudo apt install -f
echo "QEMU-QuickBoot-v1.4 Was sucessfully installed, run from terminal with "qboot" or use desktop launcher."
sleep 5 && exit
