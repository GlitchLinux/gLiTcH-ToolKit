#!/bin/bash
sudo apt install -y docker.io docker-compose
sudo systemctl enable docker
sudo systemctl start docker
echo "Docker setup complete."
