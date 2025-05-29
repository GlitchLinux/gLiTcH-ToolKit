#!/bin/bash
cd /tmp
git clone https://github.com/GlitchLinux/docker.py
cd docker.py
chmod +x minideb-docker.py
sudo python3 minideb-docker.py
