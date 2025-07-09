cd /tmp	
sudo wget https://dl.thorium.rocks/debian/dists/stable/thorium.list
sudo mv thorium.list /etc/apt/sources.list.d/
sudo apt update
sudo apt install thorium-browser -y

echo "[Desktop Entry]" > /home/x/Desktop/Thorium
echo "Categories=Internet;" >> /home/x/Desktop/Thorium
echo "Comment[en_US]=Thorium Browser" >> /home/x/Desktop/Thorium
echo "Exec=/usr/bin/thorium-browser" >> /home/x/Desktop/Thorium
echo "Icon=/usr/share/pixmaps/thorium_greyscale_1024.png" >> /home/x/Desktop/Thorium
echo "Keywords=browser;internet" >> /home/x/Desktop/Thorium
echo "Name[en_US]=Thorium" >> /home/x/Desktop/Thorium
echo "Name=Thorium" >> /home/x/Desktop/Thorium
echo "StartupNotify=false" >> /home/x/Desktop/Thorium
echo "Terminal=false" >> /home/x/Desktop/Thorium
echo "Type=Application" >> /home/x/Desktop/Thorium
echo "Version=1.0" >> /home/x/Desktop/Thorium

sudo chmod +x /home/puppy/Desktop/Thorium

sleep 15

/usr/bin/thorium-browser 

sleep 5

/usr/bin/thorium-browser 
