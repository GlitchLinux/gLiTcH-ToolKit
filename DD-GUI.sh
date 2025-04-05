#!/bin/bash
wget https://github.com/GlitchLinux/dd_py_GUI/releases/download/dd_gui_amd64_v1.1/dd_gui_amd64_v1.1.deb
sudo dpkg -i dd_gui_amd64_v1.1.deb && rm dd_gui_amd64_v1.1.deb 
sudo python3 /etc/dd_gui/DD_GUI.py
