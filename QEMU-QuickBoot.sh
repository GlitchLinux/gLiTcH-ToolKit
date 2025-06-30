cd /tmp
wget https://github.com/GlitchLinux/QEMU-QuickBoot/releases/download/QEMU-QuickBoot-v1.4_amd64.deb/QEMU-QuickBoot-v1.4_amd64.deb
sudo dpkg -i QEMU-QuickBoot-v1.4_amd64.deb && sudo apt install -f
echo "QEMU-QuickBoot-v1.4 Was sucessfully installed, run from terminal with "qboot" or use desktop launcher."
sleep 5 && exit
