#!/bin/bash

# Docker Installation and docker-to-linux Setup Script
# For Debian/Ubuntu systems
# Run as root or with sudo

set -e  # Exit on any error

echo "=== Docker Installation and docker-to-linux Setup ==="
echo "Detected system: $(lsb_release -si) $(lsb_release -sr)"
echo

# Function to check if command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Update package index
echo "[1/8] Updating package index..."
apt-get update

# Install required packages
echo "[2/8] Installing prerequisites..."
apt-get install -y \
    ca-certificates \
    curl \
    gnupg \
    lsb-release \
    software-properties-common \
    apt-transport-https

# Add Docker's official GPG key
echo "[3/8] Adding Docker GPG key..."
mkdir -p /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/$(lsb_release -si | tr '[:upper:]' '[:lower:]')/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

# Add Docker repository
echo "[4/8] Adding Docker repository..."
echo "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/$(lsb_release -si | tr '[:upper:]' '[:lower:]') $(lsb_release -cs) stable" | tee /etc/apt/sources.list.d/docker.list > /dev/null

# Update package index again
echo "[5/8] Updating package index with Docker repository..."
apt-get update

# Install Docker
echo "[6/8] Installing Docker CE..."
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Start and enable Docker service
echo "[7/8] Starting Docker service..."
systemctl start docker
systemctl enable docker

# Verify Docker installation
echo "[8/8] Verifying Docker installation..."
if command_exists docker; then
    echo "✓ Docker installed successfully!"
    docker --version
    echo
    
    # Test Docker with hello-world
    echo "Testing Docker with hello-world container..."
    docker run --rm hello-world
    echo
else
    echo "✗ Docker installation failed!"
    exit 1
fi

# Check if QEMU is installed (required for docker-to-linux)
echo "=== Checking QEMU installation ==="
if command_exists qemu-system-x86_64; then
    echo "✓ QEMU is already installed"
    qemu-system-x86_64 --version | head -1
else
    echo "Installing QEMU..."
    apt-get install -y qemu-system-x86 qemu-utils
    echo "✓ QEMU installed successfully"
fi

echo
echo "=== docker-to-linux Usage Instructions ==="
echo "Now you can run docker-to-linux commands:"
echo
echo "1. Build a Debian image:"
echo "   make debian"
echo
echo "2. Build an Ubuntu image:"
echo "   make ubuntu"
echo
echo "3. Build an Alpine image:"
echo "   make alpine"
echo
echo "4. Run the VM (after building):"
echo "   qemu-system-x86_64 -drive file=debian.img,index=0,media=disk,format=raw -m 4096"
echo "   # Login: username 'root', password 'root'"
echo
echo "5. Clean up when done:"
echo "   make clean"
echo
echo "=== Additional Notes ==="
echo "• If you need to run Docker as non-root user, add them to docker group:"
echo "  usermod -aG docker \$USERNAME"
echo "• You may need to log out/in for group changes to take effect"
echo "• For better security, consider creating a non-root user for Docker operations"
echo
echo "Installation complete! 🐳"
