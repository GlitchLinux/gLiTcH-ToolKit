sudo dpkg --configure -a
sudo apt-get install -fy
sudo apt-get purge --allow-remove-essential -y grub-com*
sudo apt-get purge --allow-remove-essential -y grub2-com*
sudo apt-get purge --allow-remove-essential -y shim-signed
sudo apt-get purge --allow-remove-essential -y grub-common:*
sudo apt-get purge --allow-remove-essential -y grub2-common:*
