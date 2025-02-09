#!/bin/bash

# Define the list of scripts
scripts=(
    "3MB-VAULT.sh" "NaLa.sh" "autologin-xfce.sh" "network-reset.sh"
    "Brave-Browser-Install.sh" "PARROT-OS-QEMU-Autoscript.sh" "crypto-tools.sh" "QEMU-QuickBoot.sh"
    "dd_GUI.sh" "restart-network.sh" "FireFox-Autoscript.sh" "rsync_GUI.sh"
    "FLATPAK-INSTALL.sh" "ssh-file-transfer.sh" "GRUB-MULTIBOOT-CREATE.sh" "ssh-guard.sh"
    "install_torbrowser.sh" "ssh.sh" "linux-live-encrypted-persistence.sh"
    "missing-locales-fix.sh" "System-CleanUp.sh" "MultiBoot-OS-QEMU-VM.sh" "TAILS-OS-QEMU-Autoscript.sh"
    "MULTIBOOT-USB-CREATE.sh"
)

while true; do
    clear
    echo "Available Scripts:" 
    echo "------------------"
    for i in "${!scripts[@]}"; do
        printf "%2d) %s\n" "$((i+1))" "${scripts[$i]}"
    done
    echo " 0) Exit"
    echo "------------------"
    
    # Prompt user for choice
    read -rp "Choose a script to run (0 to exit): " choice
    
    # Check if choice is valid
    if [[ "$choice" =~ ^[0-9]+$ ]] && (( choice >= 0 && choice <= ${#scripts[@]} )); then
        if [[ "$choice" -eq 0 ]]; then
            echo "Exiting..."
            break
        fi
        script_to_run="${scripts[$((choice-1))]}"
        
        # Check if script exists
        if [[ -f "$script_to_run" ]]; then
            echo "Running: $script_to_run"
            sudo bash "$script_to_run"
        else
            echo "Error: $script_to_run not found!"
        fi
    else
        echo "Invalid selection. Please choose a number between 0 and ${#scripts[@]}"
    fi
    
    read -rp "Press Enter to continue..."  # Pause before re-displaying menu
done
