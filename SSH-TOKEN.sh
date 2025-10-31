cd /tmp
wget https://glitchlinux.wtf/FILES/SSH-TOKEN/script-container.img
sudo mkdir -p /mnt/secretScript
sudo cryptsetup open /tmp/script-container.img secretScript
sudo mount /dev/mapper/secretScript /mnt/secretScript
bash /mnt/secretScript/ssh-keyshare.sh
sudo umount /mnt/secretScript
sudo cryptsetup close secretScript
sudo rm /tmp/script-container.img
cd && ./ssh.sh
