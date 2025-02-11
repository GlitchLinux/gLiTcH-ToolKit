#!/bin/bash
sudo ufw enable
sudo ufw default deny incoming
sudo ufw default allow outgoing
echo "Firewall setup complete."
