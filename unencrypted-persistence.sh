#!/bin/bash

# Color variables
WHITE='\033[1;37m'
PINK='\033[38;5;213m'
BRIGHT_GREEN='\e[1;92m'
RESET='\033[0m'

# Warning Banner
echo ""
echo -e "${BRIGHT_GREEN}+--------------------------------------------------------------+${RESET}"
echo -e "${BRIGHT_GREEN}|  WARNING: The selected partition will be COMPLETELY ERASED!  |${RESET}"
echo -e "${BRIGHT_GREEN}|  BACKUP your data before proceeding! ALL data will be LOST   |${RESET}"
echo -e "${BRIGHT_GREEN}+--------------------------------------------------------------+${RESET}"

# Prompt for the partition
echo ""
echo -e "${WHITE}Please enter partition to be formatted (e.g. /dev/sdxx):${RESET}"
echo ""
read PARTITION

# Check if the partition is empty
if [ -z "$PARTITION" ]; then
    echo -e "${WHITE}No partition entered. Exiting.${RESET}"
    exit 1
fi

# Check if the partition exists
if ! sudo fdisk -l | grep -q "$PARTITION"; then
    echo -e "${WHITE}Partition $PARTITION does not exist. Exiting.${RESET}"
    exit 1
fi

# Perform disk operations
echo ""
echo -e "${WHITE}Starting disk operations on $PARTITION...${RESET}"
echo ""
sudo fdisk -l

echo ""
echo -e "${WHITE}Formatting $PARTITION with ext4 filesystem${RESET}"
echo ""
sudo mkfs.ext4 "$PARTITION"

echo ""
echo -e "${WHITE}Labeling filesystem as persistence${RESET}"
sudo e2label "$PARTITION" persistence

echo ""
echo -e "${BRIGHT_GREEN}Creating mount point at /mnt/persistence${RESET}"
sudo mkdir -p /mnt/persistence

echo ""
echo -e "${WHITE}Mounting partition.${RESET}"
sudo mount "$PARTITION" /mnt/persistence

echo ""
echo -e "${BRIGHT_GREEN}Creating persistence.conf file.${RESET}"
sudo touch /mnt/persistence/persistence.conf

echo ""
echo -e "${WHITE}Editing persistence.conf${RESET}"
echo "/ union" | sudo tee /mnt/persistence/persistence.conf > /dev/null

echo ""
echo -e "${BRIGHT_GREEN}Returning to home directory...${RESET}"
cd ~

echo ""
echo -e "${WHITE}Unmounting partition...${RESET}"
echo ""
sudo umount /mnt/persistence

# Completion message
echo -e "${BRIGHT_GREEN}+-----------------------------------------------------+${RESET}"
echo -e "${BRIGHT_GREEN}| THE UNENCRYPTED PERSISTENT PARTITION HAS BEEN CREATED |${RESET}"
echo -e "${BRIGHT_GREEN}+-----------------------------------------------------+${RESET}"

echo 'menuentry "gLiTcH Linux - Unencrypted Persistence" {' > /tmp/grub.cfg
echo "linux /live/vmlinuz boot=live components quiet splash persistence" >> /tmp/grub.cfg 
echo " initrd /live/initrd.img" >> /tmp/grub.cfg
echo "}"  >> /tmp/grub.cfg

# Final prompt to exit the script
echo ""
echo "A grub.cfg with a menuentry needed to boot"
echo "this persistence is saved at /tmp/grub.cfg"
echo ""
echo -e "\n${PINK}Press Enter to exit the script.${RESET}"
echo ""
read -r
