#!/bin/bash

cd /tmp 
sudo rm -rf Glitch-CLI-Wallpaper.sh
wget https://raw.githubusercontent.com/GlitchLinux/Glitch-Plymouth/refs/heads/main/Glitch-Ksplash/Glitch-CLI-Wallpaper.sh
sudo cp Glitch-CLI-Wallpaper.sh /usr/local/bin/Glitch-CLI-Wallpaper.sh
sudo chmod +x /usr/local/bin/Glitch-CLI-Wallpaper.sh
sudo chmod 777 /usr/local/bin/Glitch-CLI-Wallpaper.sh

mkdir -p /home/x/.config/autostart/

cat > /home/x/.config/autostart/glitch-wallpaper-autostart.sh << 'EOF'
[Desktop Entry]
Type=Application
Name=Glitch-Wallpaper-Launcher
Exec=/usr/local/bin/Glitch-CLI-Wallpaper.sh
Hidden=false
EOF

echo ' '
echo 'Dynamic Wallpaper auto-launcher was successfully installed!' | borderize 
echo ' '
