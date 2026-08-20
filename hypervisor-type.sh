#!/bin/bash
# hypervisor-type.sh - Switch between QEMU/KVM and VirtualBox hypervisors

if [[ $EUID -ne 0 ]]; then
    echo "This script must be run as root (sudo)."
    exit 1
fi

# Detect CPU vendor
if grep -q "GenuineIntel" /proc/cpuinfo; then
    KVM_MOD="kvm_intel"
elif grep -q "AuthenticAMD" /proc/cpuinfo; then
    KVM_MOD="kvm_amd"
else
    echo "Unknown CPU vendor. Cannot determine KVM module."
    exit 1
fi

echo ""
echo "  Hypervisor Selector"
echo "  -------------------"
echo ""
echo "  1. QEMU/KVM"
echo "  2. VirtualBox"
echo ""
read -rp "  Enter selection [1-2]: " choice

case "$choice" in
    1)
        echo ""
        echo "[*] Unloading VirtualBox modules..."
        modprobe -r vboxnetadp vboxnetflt vboxdrv 2>/dev/null
        echo "[*] Loading KVM modules..."
        modprobe kvm
        modprobe "$KVM_MOD"
        echo "[+] QEMU/KVM is now active ($KVM_MOD loaded)."
        ;;
    2)
        echo ""
        echo "[*] Unloading KVM modules..."
        modprobe -r "$KVM_MOD" kvm 2>/dev/null
        echo "[*] Loading VirtualBox modules..."
        modprobe vboxdrv
        modprobe vboxnetflt 2>/dev/null
        modprobe vboxnetadp 2>/dev/null
        echo "[+] VirtualBox is now active."
        ;;
    *)
        echo "Invalid selection."
        exit 1
        ;;
esac

echo ""
lsmod | grep -E "kvm|vbox" && echo "" || echo "No hypervisor modules currently loaded."
