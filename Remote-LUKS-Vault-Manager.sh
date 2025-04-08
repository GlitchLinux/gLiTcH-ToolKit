#!/bin/bash

sudo apt update && sudo apt install sshpass sshfs python3 python3-paramiko openssh-server

git clone https://github.com/GlitchLinux/Remote-LUKS-Vault-Manager.git
cd Remote-LUKS-Vault-Manager
sudo chmod +x luks_remote.py
sudo ./luks_remote.py
