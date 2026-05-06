#!/usr/bin/env bash

set -e

# Ensure required tools exist
for cmd in qemu-nbd modprobe lsblk; do
    if ! command -v "$cmd" >/dev/null 2>&1; then
        echo "Error: $cmd is not installed."
        exit 1
    fi
done

# Load nbd module if not already loaded
if ! lsmod | grep -q "^nbd"; then
    echo "[*] Loading nbd kernel module..."
    sudo modprobe nbd max_part=16
fi

echo "=============================="
echo " Fake Loop Device Manager"
echo "=============================="
echo "1) Mount new image as /dev/nbdX"
echo "2) Unmount existing /dev/nbdX"
echo "=============================="

read -rp "Enter choice: " choice

case "$choice" in
    1)
        read -rp "Enter path to disk image: " IMG

        if [ ! -f "$IMG" ]; then
            echo "Error: File does not exist."
            exit 1
        fi

        # Find a free /dev/nbdX
        for dev in /dev/nbd*; do
            if ! lsblk "$dev" | grep -q "disk"; then
                FREE_DEV="$dev"
                break
            fi
        done

        if [ -z "$FREE_DEV" ]; then
            echo "Error: No free /dev/nbd devices available."
            exit 1
        fi

        echo "[*] Using $FREE_DEV"

        sudo qemu-nbd --connect="$FREE_DEV" "$IMG"

        echo "[+] Mounted $IMG as $FREE_DEV"
        echo "[*] You can now use it like a real disk (fdisk, gparted, etc.)"
        ;;

    2)
        echo "[*] Currently connected nbd devices:"
        lsblk | grep nbd || echo "None found"

        read -rp "Enter /dev/nbdX to disconnect: " DEV

        if [ ! -b "$DEV" ]; then
            echo "Error: Invalid block device."
            exit 1
        fi

        echo "[*] Disconnecting $DEV..."
        sudo qemu-nbd --disconnect "$DEV"

        echo "[+] Disconnected $DEV"
        ;;

    *)
        echo "Invalid choice."
        exit 1
        ;;
esac
