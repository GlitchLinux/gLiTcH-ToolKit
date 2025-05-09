if ! mountpoint -q /mnt/nas; then
    sshfs x@192.168.0.198:/home/x/Desktop/VirtualDisks/ /mnt/nas -o allow_other,reconnect,ServerAliveInterval=15
fi
