cd /tmp
sudo apt update && sudo apt install -y python3 python3-pip git pv dosfstools parted cryptsetup util-linux
sudo wget https://github.com/GlitchLinux/dd_py_CLI/releases/download/dd-cli_v0.1/dd-cli_v0.1_amd64.deb
sudo dpkg -i dd-cli_v0.1_amd64.deb
sudo rm dd-cli_v0.1_amd64.deb
bash -i -c "DD"
