#!/bin/bash

cd /home/x/
sudo rm -f android-x86-phone.qcow2
sudo rm -f Androidx86-headless.sh
wget glitchlinux.wtf/FILES/android-x86/android-x86-phone.qcow2
wget glitchlinux.wtf/FILES/android-x86/Androidx86-headless.sh
sudo cp Androidx86-headless.sh /bin/androidx86-headless.sh
sudo chmod +x /bin/androidx86-headless.sh
xterm -e 'bash /bin/androidx86-headless.sh' &
sleep 1 && exit