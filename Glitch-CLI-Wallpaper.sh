#!/bin/bash

cd /tmp
wget https://raw.githubusercontent.com/GlitchLinux/Glitch-Plymouth/refs/heads/main/Glitch-Ksplash/Glitch-CLI-Wallpaper.sh
sudo cp Glitch-CLI-Wallpaper.sh /usr/local/bin/Glitch-CLI-Wallpaper.sh
sudo chmod +x /usr/local/bin/Glitch-CLI-Wallpaper.sh
sudo chmod 777 /usr/local/bin/Glitch-CLI-Wallpaper.sh

cat > ~/.config/autostart/Glitch-CLI-Wallpaper.sh << 'EOF'
[Desktop Entry]
Type=Application
Name=Glitch-CLI-Wallpaper
Exec=/usr/local/bin/Glitch-CLI-Wallpaper.sh
Hidden=false
EOF
