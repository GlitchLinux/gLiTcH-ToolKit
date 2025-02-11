#!/bin/bash
sudo apt install -y qemu-kvm libvirt-daemon-system libvirt-clients bridge-utils virt-manager
sudo systemctl enable libvirtd
sudo systemctl start libvirtd
echo "KVM setup complete."
