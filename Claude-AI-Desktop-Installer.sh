cd /tmp
sudo apt update -y
wget https://github.com/aaddrick/claude-desktop-debian/releases/download/v1.1.6%2Bclaude0.14.10/claude-desktop_0.14.10_amd64.deb
sudo dpkg -i claude-desktop_0.14.10_amd64.deb
sudo apt install -f -y
sleep 4
echo ""
echo "**************************************"
echo " CLAUDE DESKTOP INSTALLED SUCESSFULLY "
echo "**************************************"
echo ""
bash
