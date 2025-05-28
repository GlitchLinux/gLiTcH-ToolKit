sudo dpkg --configure -a
sudo apt-get install -fy
sudo apt-get purge --allow-remove-essential -y grub-com*
sudo apt-get purge --allow-remove-essential -y grub2-com*
sudo apt-get purge --allow-remove-essential -y shim-signed
sudo apt-get purge --allow-remove-essential -y grub-common:*
sudo apt-get purge --allow-remove-essential -y grub2-common:*

echo "PURGE COMPLETED NOW REINSTALL GRUB!"
echo ""
echo "sudo apt install grub-efi #UEFI"
echo ""
echo "OR ->"
echo ""
echo "sudo apt install grub-pc  #BIOS"
echo ""
sleep 60

exit
