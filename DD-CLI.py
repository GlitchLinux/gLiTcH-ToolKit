#!/bin/bash
# Install DD-CLI system-wide with alias for all users

# 1. Clean previous install
sudo rm -rf /etc/dd_cli/

# 2. Create fresh directory
sudo mkdir -p /etc/dd_cli/

# 3. Download the script
echo " "
echo "Downloading DD-CLI"
echo "Creating alias DD as shortcut"
sudo curl -sLo /etc/dd_cli/DD-CLI.py \
    https://raw.githubusercontent.com/GlitchLinux/dd_py_CLI/main/DD-CLI.py || {
    echo "Download failed!"
    exit 1
}

# 4. Make executable
sudo chmod +x /etc/dd_cli/DD-CLI.py

# Create aliases for all users
ALIAS_CMD='alias DD="python3 /etc/dd_cli/DD-CLI.py"'

# For current user
echo "$ALIAS_CMD" >> ~/.bashrc
[ -f ~/.zshrc ] && echo "$ALIAS_CMD" >> ~/.zshrc

# For root
sudo bash -c "echo '$ALIAS_CMD' >> /root/.bashrc"

# For future users (global)
echo "$ALIAS_CMD" | sudo tee /etc/profile.d/dd_cli.sh >/dev/null
sudo chmod +x /etc/profile.d/dd_cli.sh

# Reload current shell
source ~/.bashrc 2>/dev/null || true

# Verify installation
echo "Installation complete, Run DD to execute"
echo " "
