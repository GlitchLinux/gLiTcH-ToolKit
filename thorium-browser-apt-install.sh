cd /tmp	
sudo wget https://dl.thorium.rocks/debian/dists/stable/thorium.list
sudo mv thorium.list /etc/apt/sources.list.d/
sudo apt update
sudo apt install thorium-browser -y

echo "[Desktop Entry]" > /home/$USER/Desktop/Thorium
echo "Categories=Internet;" >> /home/$USER/Desktop/Thorium
echo "Comment[en_US]=Thorium Browser" >> /home/$USER/Desktop/Thorium
echo "Exec=/usr/bin/thorium-browser" >> /home/$USER/Desktop/Thorium
echo "Icon=/usr/share/pixmaps/thorium_greyscale_1024.png" >> /home/$USER/Desktop/Thorium
echo "Keywords=browser;internet" >> /home/$USER/Desktop/Thorium
echo "Name[en_US]=Thorium" >> /home/$USER/Desktop/Thorium
echo "Name=Thorium" >> /home/$USER/Desktop/Thorium
echo "StartupNotify=false" >> /home/$USER/Desktop/Thorium
echo "Terminal=false" >> /home/$USER/Desktop/Thorium
echo "Type=Application" >> /home/$USER/Desktop/Thorium
echo "Version=1.0" >> /home/$USER/Desktop/Thorium

sudo chmod +x /home/$USER/Desktop/Thorium

sleep 15

/usr/bin/thorium-browser 

sleep 5

/usr/bin/thorium-browser 
