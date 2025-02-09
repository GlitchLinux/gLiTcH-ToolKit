#!/bin/bash

while true; do
    clear
    echo "Available Scripts:" 
    echo "------------------"
    echo " 1) 3MB-VAULT.sh"
    echo " 2) NaLa.sh"
    echo " 3) autologin-xfce.sh"
    echo " 4) network-reset.sh"
    echo " 5) Brave-Browser-Install.sh"
    echo " 6) PARROT-OS-QEMU-Autoscript.sh"
    echo " 7) crypto-tools.sh"
    echo " 8) QEMU-QuickBoot.sh"
    echo " 9) dd_GUI.sh"
    echo "10) restart-network.sh"
    echo "11) FireFox-Autoscript.sh"
    echo "12) rsync_GUI.sh"
    echo "13) FLATPAK-INSTALL.sh"
    echo "14) ssh-file-transfer.sh"
    echo "15) GRUB-MULTIBOOT-CREATE.sh"
    echo "16) ssh-guard.sh"
    echo "17) install_torbrowser.sh"
    echo "18) ssh.sh"
    echo "19) linux-live-encrypted-persistence.sh"
    echo "20) sudo.visudo.conf"
    echo "21) missing-locales-fix.sh"
    echo "22) System-CleanUp.sh"
    echo "23) MultiBoot-OS-QEMU-VM.sh"
    echo "24) TAILS-OS-QEMU-Autoscript.sh"
    echo "25) MULTIBOOT-USB-CREATE.sh"
    echo " 0) Exit"
    echo "------------------"
    
    # Prompt user for choice
    read -rp "Choose a script to run (0 to exit): " choice
    
    case "$choice" in
        1) script="3MB-VAULT.sh" ;;
        2) script="NaLa.sh" ;;
        3) script="autologin-xfce.sh" ;;
        4) script="network-reset.sh" ;;
        5) script="Brave-Browser-Install.sh" ;;
        6) script="PARROT-OS-QEMU-Autoscript.sh" ;;
        7) script="crypto-tools.sh" ;;
        8) script="QEMU-QuickBoot.sh" ;;
        9) script="dd_GUI.sh" ;;
        10) script="restart-network.sh" ;;
        11) script="FireFox-Autoscript.sh" ;;
        12) script="rsync_GUI.sh" ;;
        13) script="FLATPAK-INSTALL.sh" ;;
        14) script="ssh-file-transfer.sh" ;;
        15) script="GRUB-MULTIBOOT-CREATE.sh" ;;
        16) script="ssh-guard.sh" ;;
        17) script="install_torbrowser.sh" ;;
        18) script="ssh.sh" ;;
        19) script="linux-live-encrypted-persistence.sh" ;;
        20) script="sudo.visudo.conf" ;;
        21) script="missing-locales-fix.sh" ;;
        22) script="System-CleanUp.sh" ;;
        23) script="MultiBoot-OS-QEMU-VM.sh" ;;
        24) script="TAILS-OS-QEMU-Autoscript.sh" ;;
        25) script="MULTIBOOT-USB-CREATE.sh" ;;
        0) echo "Exiting..." ; exit 0 ;;
        *) echo "Invalid selection. Please choose a number between 0 and 25." ; read -rp "Press Enter to continue..." ; continue ;;
    esac
    
    if [[ -f "$script" ]]; then
        echo "Running: $script"
        sudo bash "$script"
    else
        echo "Error: $script not found!"
    fi
    
    read -rp "Press Enter to continue..."  # Pause before re-displaying menu
done
