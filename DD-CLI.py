#!/bin/bash

# Create /etc/dd_cli/ with sudo (only if needed)
echo "[+] Creating /etc/dd_cli/..."
sudo mkdir -p /etc/dd_cli/ || {
    echo "[-] Failed to create /etc/dd_cli/ (check permissions?)";
    exit 1;
}

# Download DD-CLI.py directly to /etc/dd_cli/
echo "[+] Downloading DD-CLI.py..."
if command -v wget &> /dev/null; then
    sudo wget -q https://raw.githubusercontent.com/GlitchLinux/dd_py_CLI/main/DD-CLI.py -O /etc/dd_cli/DD-CLI.py
elif command -v curl &> /dev/null; then
    sudo curl -s -o /etc/dd_cli/DD-CLI.py https://raw.githubusercontent.com/GlitchLinux/dd_py_CLI/main/DD-CLI.py
else
    echo "[-] Error: Neither wget nor curl is installed. Install one and try again."
    exit 1
fi

# Make the script executable (with sudo)
sudo chmod +x /etc/dd_cli/DD-CLI.py
echo "[+] Made DD-CLI.py executable."

# Add alias ONLY to the current user's shell config
USER_SHELL_CONFIG="$HOME/.bashrc"
if [ -n "$ZSH_VERSION" ]; then
    USER_SHELL_CONFIG="$HOME/.zshrc"
fi

ALIAS_CMD='alias DD="python3 /etc/dd_cli/DD-CLI.py"'

if ! grep -q 'alias DD=' "$USER_SHELL_CONFIG"; then
    echo "$ALIAS_CMD" >> "$USER_SHELL_CONFIG"
    echo "[+] Added alias to $USER_SHELL_CONFIG"
else
    echo "[!] Alias already exists in $USER_SHELL_CONFIG (skipping)"
fi

# Auto-reload the shell config
echo "[+] Reloading shell config..."
source "$USER_SHELL_CONFIG" 2>/dev/null || true

# Test DD
echo "[+] Testing DD command..."
DD
