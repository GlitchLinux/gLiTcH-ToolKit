#!/bin/bash
sudo apt install -y lxc
sudo lxc-create -t download -n mycontainer -- -d ubuntu -r focal -a amd64
echo "LXC container created."
