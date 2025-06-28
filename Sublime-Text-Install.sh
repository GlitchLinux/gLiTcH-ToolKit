cd /tmp
wget https://download.sublimetext.com/sublime-text_build-3211_amd64.deb
sudo apt update && sudo dpkg -i sublime-text_build-3211_amd64.deb 
sudo apt install -f -y && sudo dpkg -i sublime-text_build-3211_amd64.deb
sudo rm -f /tmp/sublime-text_build-3211_amd64.deb && echo "Sublime Text Sucessfully Installed!" 
sleep 8 && exit
