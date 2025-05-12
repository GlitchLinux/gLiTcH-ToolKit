sudo apt update
sudo apt install qemu-system wget qemu-utils qemu-system-gui xdotool ovmf qemu-system zenity orchis-gtk-theme -y
cd /tmp && git clone https://github.com/GlitchLinux/QEMU-QuickBoot.git
cd QEMU-QuickBoot
sudo rm -f /home/x/txt.and.sh/BASH-SCRIPTS/QEMU-QuickBoot-NAS.sh
sudo cp QEMU-QuickBoot.sh /home/x/txt.and.sh/BASH-SCRIPTS/QEMU-QuickBoot-NAS.sh 
sudo rm -r /tmp/QEMU-QuickBoot
sudo bash /home/x/txt.and.sh/BASH-SCRIPTS/QEMU-QuickBoot-NAS.sh
