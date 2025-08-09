sudo apt update && sudo apt install python3-tk zenity -y
cd /tmp
wget https://github.com/GlitchLinux/dd_py_GUI/releases/download/dd_gui_amd64_v1.1/dd_gui_amd64_v1.1.deb
sudo dpkg --force-all -i dd_gui_amd64_v1.1.deb 
sudo apt install -f
python3 /etc/dd_gui/DD-GUI.py
exit
