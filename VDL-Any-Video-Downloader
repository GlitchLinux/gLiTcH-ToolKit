#!/bin/bash

cd /tmp
wget https://raw.githubusercontent.com/GlitchLinux/vdl/refs/heads/main/VDL
sudo cat VDL > /usr/local/bin/VDL
sudo chmod +x /usr/local/bin/VDL
sudo chmod 777 /usr/local/bin/VDL

# Auto-install yt-dlp from GitHub (latest version)
if ! command -v yt-dlp &>/dev/null; then
    echo "Installing yt-dlp (latest)..."
    sudo curl -L https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp -o /usr/local/bin/yt-dlp
    sudo chmod +x /usr/local/bin/yt-dlp
    echo "yt-dlp installed: $(yt-dlp --version)"
fi

# Auto-install borderize
if ! command -v borderize &>/dev/null; then
    echo "Installing borderize..."
    sudo curl -sL https://raw.githubusercontent.com/GlitchLinux/BORDERIZE/main/borderize -o /usr/local/bin/borderize
    sudo chmod +x /usr/local/bin/borderize
fi

echo "VDL utility have been successfully installed!" > /tmp/vdl-installed
echo "Start job with: 'VDL' for help run: 'VDL -h'" >> /tmp/vdl-installed
clear
cat /tmp/vdl-installed | borderize -FF00FF && rm /tmp/vdl-installed
