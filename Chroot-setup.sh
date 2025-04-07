#!/bin/bash

# Define ANSI color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[0;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Function to display partition information
show_partitions() {
    clear
    echo -e "${CYAN}┌───────────────────────────────────────────────────────┐"
    echo -e "│ ${YELLOW}Chroot Setup Utility ${CYAN}                              │"
    echo -e "└───────────────────────────────────────────────────────┘${NC}"
    echo ""
    
    echo -e "${YELLOW}Available partitions:${NC}"
    lsblk -o NAME,SIZE,FSTYPE,MOUNTPOINT,LABEL | grep -v "loop"
    echo ""
}

show_partitions

# Prompt for root partition
while true; do
    echo -e "${GREEN}Enter root partition (e.g., sda2, nvme0n1p3):${NC} "
    read -r root_part
    
    if [[ -e "/dev/$root_part" ]]; then
        break
    else
        echo -e "${RED}Partition /dev/$root_part does not exist!${NC}"
    fi
done

# Ask if they want to mount a separate boot partition
echo -e "${YELLOW}Do you have a separate boot partition? (y/n):${NC} "
read -r has_boot

if [[ "$has_boot" == "y" ]]; then
    while true; do
        echo -e "${GREEN}Enter boot partition (e.g., sda1, nvme0n1p1):${NC} "
        read -r boot_part
        
        if [[ -e "/dev/$boot_part" ]]; then
            break
        else
            echo -e "${RED}Partition /dev/$boot_part does not exist!${NC}"
        fi
    done
fi

# Mount the partitions
echo -e "\n${YELLOW}Mounting partitions...${NC}"
sudo umount /mnt 2>/dev/null
sudo mount "/dev/$root_part" /mnt

if [[ "$has_boot" == "y" ]]; then
    sudo mkdir -p /mnt/boot
    sudo mount "/dev/$boot_part" /mnt/boot
fi

# Mount necessary directories
echo -e "${YELLOW}Mounting system directories...${NC}"
sudo mount --bind /dev /mnt/dev
sudo mount --bind /proc /mnt/proc
sudo mount --bind /sys /mnt/sys
sudo mount --bind /run /mnt/run

# Display final instructions
clear
echo -e "${CYAN}┌───────────────────────────────────────────────────────┐"
echo -e "│ ${YELLOW}Chroot Setup Complete ${CYAN}                              │"
echo -e "└───────────────────────────────────────────────────────┘${NC}"
echo -e "${GREEN}Your system is ready for chroot. Use this command:${NC}\n"
echo -e "${RED}sudo chroot /mnt${NC}\n"
echo -e "${YELLOW}When finished, exit chroot and run:${NC}"
echo -e "${BLUE}sudo umount -R /mnt${NC}\n"

# Offer to enter chroot directly
echo -e "${YELLOW}Do you want to enter chroot now? (y/n):${NC} "
read -r enter_chroot

if [[ "$enter_chroot" == "y" ]]; then
    sudo chroot /mnt
fi
