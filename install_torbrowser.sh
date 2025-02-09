#!/bin/bash

# Display fancy banner
echo "╔═══════════════════════════╗"
echo "║ TOR BROWSER - AutoScript! ║"
echo "║ Browser will now download ║"
echo "║     install & start.      ║"
echo "╚═══════════════════════════╝"
echo "‎ "

# Get the username
USERNAME=$USER

# Construct the path to the user's Desktop
DESKTOP_PATH="/home/$USERNAME/Desktop"

# Define the temp directory and download URL
TEMP_DIR="/tmp/tor"
TOR_BROWSER_URL="https://www.torproject.org/dist/torbrowser/14.0.3/tor-browser-linux-x86_64-14.0.3.tar.xz"

# Remove the existing /tmp/tor/ directory if it exists
# echo "Cleaning up any previous installation in /tmp/tor"
rm -rf ${TEMP_DIR}
rm -f /home/$USERNAME/Desktop/tor.desktop

# Create a temporary directory for the installation
mkdir -p ${TEMP_DIR}
cd ${TEMP_DIR} || exit

# Download the Tor Browser tarball
echo "Downloading Tor Browser version 14.0.2..."
if ! curl -# -fLO "${TOR_BROWSER_URL}"; then
    echo
    echo "A problem occurred when downloading Tor Browser"
    echo "Please try again"
    echo
    exit 1
fi

# Extract the downloaded tarball
echo "Extracting tor-browser-linux-x86_64-14.0.2.tar.xz..."
tar -xf "tor-browser-linux-x86_64-14.0.2.tar.xz"
rm "tor-browser-linux-x86_64-14.0.2.tar.xz"

# Move into the extracted directory
cd tor-browser/ || exit

#Create a desktop icon
touch /home/$USERNAME/Desktop/Tor.desktop
echo "[Desktop Entry]" >> /home/$USERNAME/Desktop/tor.desktop
echo "Version=1.0" >> /home/$USERNAME/Desktop/tor.desktop
echo "Type=Application" >> /home/$USERNAME/Desktop/tor.desktop
echo "Name=Tor Browser" >> /home/$USERNAME/Desktop/tor.desktop
echo "Comment=" >> /home/$USERNAME/Desktop/tor.desktop
echo "Exec=bash /tmp/tor/tor-browser/Browser/start-tor-browser" >> /home/$USERNAME/Desktop/tor.desktop
echo "Icon=/tmp/tor/tor-browser/Browser/browser/chrome/icons/default/about-logo.svg" >> /home/$USERNAME/Desktop/tor.desktop
echo "Path=" >> /home/$USERNAME/Desktop/tor.desktop
echo "Terminal=false" >> /home/$USERNAME/Desktop/tor.desktop
echo "StartupNotify=false" >> /home/$USERNAME/Desktop/tor.desktop
rm /home/$USERNAME/Desktop/Tor.desktop
chmod +x /home/$USERNAME/Desktop/tor.desktop

# Launch Tor Browser in detached mode
echo "Launching Tor Browser"
echo "‎ "
echo "CLOSING THIS TERMINAL WILL KILL YOUR BROWSER SESSION!"
echo "‎ "
echo "Use desktop icon to start Tor if terminal closes"
bash "/tmp/tor/tor-browser/Browser/start-tor-browser"