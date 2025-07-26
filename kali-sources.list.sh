# APPLIES A WORKING KALI-LINUX REPO, WITH GPG-KEYRING
# RUN AS ROOT

sudo mv /etc/apt/sources.list.d/sparky.list /home/sparky.list
sudo mv /etc/apt/sources.list /home/sources.list
sudo mv /usr/lib/os-release /home/os-release
sudo touch /etc/apt/sources.list 
echo "deb [trusted=yes] http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" >> /etc/apt/sources.list
echo "deb-src [trusted=yes] http://http.kali.org/kali kali-rolling main contrib non-free non-free-firmware" >> /etc/apt/sources.list

sudo touch /usr/lib/os-release
echo 'PRETTY_NAME="Kali GNU/Linux Rolling"' > /usr/lib/os-release
echo 'NAME="Kali GNU/Linux"' >> /usr/lib/os-release
echo 'VERSION_ID="2025.1"' >> /usr/lib/os-release
echo 'VERSION="2025.1"' >> /usr/lib/os-release
echo 'VERSION_CODENAME=kali-rolling'  >> /usr/lib/os-release
echo 'ID=kali' >> /usr/lib/os-release
echo 'ID_LIKE=debian'  >> /usr/lib/os-release
echo 'HOME_URL="https://www.kali.org/"' >> /usr/lib/os-release
echo 'SUPPORT_URL="https://forums.kali.org/"' >> /usr/lib/os-release
echo 'BUG_REPORT_URL="https://bugs.kali.org/"' >> /usr/lib/os-release
echo 'ANSI_COLOR="1;31"'  >> /usr/lib/os-release

sudo apt-key adv --keyserver keyserver.ubuntu.com --recv-keys ED65462EC8D5E4C5

cd /etc/apt
sudo cp trusted.gpg trusted.gpg.d

sudo apt update