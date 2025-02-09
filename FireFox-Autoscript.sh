#!/bin/bash

# Display banner
echo "╔════════════════════════════════╗"
echo "║ AUTOMATED FIREFOX ESR INSTALLER ║"
echo "╚════════════════════════════════╝"

# Step 1: Download Firefox ESR
echo "Downloading Firefox ESR..."
wget -O firefox-esr.tar.bz2 'https://download.mozilla.org/?product=firefox-esr-latest&os=linux64&lang=en-US'

# Step 2: Extract Firefox ESR
echo "Extracting Firefox ESR..."
tar -xjf firefox-esr.tar.bz2

# Step 3: Move Firefox ESR to /opt directory (requires sudo)
echo "Installing Firefox ESR..."
sudo mv firefox /opt/firefox-esr

# Step 4: Create a symbolic link for easier access
echo "Creating symbolic link..."
sudo ln -s /opt/firefox-esr/firefox /usr/local/bin/firefox-esr

# Step 5: Run Firefox ESR
echo "Running Firefox ESR..."
firefox-esr &

echo "Firefox ESR installation completed successfully."
