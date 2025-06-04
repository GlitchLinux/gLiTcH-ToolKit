sudo apt-get update && sudo apt-get install -y \
python3-pyqt5 python3-pyqt5.qtwebengine \
gparted testdisk ntfs-3g chntpw pastebinit \
grub-common grub2-common parted dosfstools \
mtools syslinux os-prober coreutils \
python3-pyqt5.qtwebkit

cd /tmp
wget https://github.com/GlitchLinux/rescapp/raw/refs/heads/main/rescapp_amd64.deb 
sudo dpkg -i rescapp_amd64.deb && sudo apt install -f

apt-cache depends rescapp | grep Depends

echo "rescapp have been installed your system!"
echo "start through gui desktop launcher"
echo "or run: rescapp in terminal"
sleep 5 && exit
