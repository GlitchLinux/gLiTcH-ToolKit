#!/bin/bash
sudo apt install -y python3-venv
python3 -m venv myenv
source myenv/bin/activate
pip install requests
echo "Python virtual environment setup complete."
