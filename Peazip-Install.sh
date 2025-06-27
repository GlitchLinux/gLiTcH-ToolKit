#!/bin/bash

# PeaZip installer for Debian

# Define variables
PEAZIP_VERSION="10.5.0"
PEAZIP_URL="https://github.com/peazip/PeaZip/releases/download/${PEAZIP_VERSION}/peazip_${PEAZIP_VERSION}.LINUX.GTK2-1_amd64.deb"
DEB_FILENAME="peazip_${PEAZIP_VERSION}.LINUX.GTK2-1_amd64.deb"
TEMP_DIR=$(mktemp -d)

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "Please run this script as root or using sudo."
    exit 1
fi

# Download PeaZip
echo "Downloading PeaZip ${PEAZIP_VERSION}..."
wget -P "$TEMP_DIR" "$PEAZIP_URL" || {
    echo "Failed to download PeaZip."
    rm -rf "$TEMP_DIR"
    exit 1
}

# Install the downloaded package
echo "Installing PeaZip..."
dpkg -i "${TEMP_DIR}/${DEB_FILENAME}" || {
    echo "Installation failed, attempting to fix dependencies..."
    apt-get install -f -y
    dpkg -i "${TEMP_DIR}/${DEB_FILENAME}" || {
        echo "PeaZip installation failed."
        rm -rf "$TEMP_DIR"
        exit 1
    }
}

# Clean up
rm -rf "$TEMP_DIR"
echo "PeaZip ${PEAZIP_VERSION} has been successfully installed."
