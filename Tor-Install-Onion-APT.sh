# Install TOR through tor-projects own repo

sudo apt update && sudo apt install apt-transport-https gnupg -y

sudo rm -f /etc/apt/sources.list.d/tor.list

sudo xterm -e 'echo "deb [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main" > /etc/apt/sources.list.d/tor.list'
sudo xterm -e 'echo "deb-src [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main" >> /etc/apt/sources.list.d/tor.list'

echo ""
cat /etc/apt/sources.list.d/tor.list && sleep 3
echo ""

sudo mv /etc/apt/sources.list /tmp/sources.list

sudo wget -qO- https://deb.torproject.org/torproject.org/A3C4F0F979CAA22CDBA8F512EE8CBC9E886DDD89.asc | gpg --dearmor | sudo tee /usr/share/keyrings/deb.torproject.org-keyring.gpg >/dev/null

sudo apt update && sudo apt install tor deb.torproject.org-keyring torbrowser-launcher -y

sudo xterm -e 'echo "#deb [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main" > /etc/apt/sources.list.d/tor.list'
sudo xterm -e 'echo "#deb-src [signed-by=/usr/share/keyrings/deb.torproject.org-keyring.gpg] https://deb.torproject.org/torproject.org bookworm main" >> /etc/apt/sources.list.d/tor.list'

sudo mv /tmp/sources.list /etc/apt/sources.list
echo ""
cat /etc/apt/sources.list
echo ""
cat /etc/apt/sources.list.d/tor.list
echo ""
echo "Tor & Tor Browser installed, onion repo used for install have been deactivated and original sources.list is restored "

sleep 15

which tor && which torbrowser-launcher

exit

