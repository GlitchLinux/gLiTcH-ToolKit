sudo tar --exclude=/tmp --exclude=/mnt --exclude=/media --exclude=/proc/* --exclude=/lost+found --exclude=/swapfile --exclude=/var/cache/apt/archives --exclude=/MiniDeb.tar -C / -c . > ~/MiniDeb.tar
