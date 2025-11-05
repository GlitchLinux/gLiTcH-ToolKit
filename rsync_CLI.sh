#!/bin/bash
# CLI-based rsync tool for Debian
# Prompts for source and destination paths and shows progress in terminal

# Colors
YELLOW='\033[1;33m'
GREEN='\033[0;32m'
RED='\033[0;31m'
NC='\033[0m' # No Color

echo -e "${YELLOW}=== CLI rsync Utility ===${NC}"

# Prompt for source and destination paths
read -rp "Enter SOURCE path: " SOURCE
read -rp "Enter DESTINATION path: " DESTINATION

# Verify paths
echo -e "\n${YELLOW}Verifying paths...${NC}"
if [ ! -e "$SOURCE" ]; then
    echo -e "${RED}Error:${NC} Source path does not exist: $SOURCE"
    exit 1
fi

if [ ! -d "$(dirname "$DESTINATION")" ]; then
    echo -e "${RED}Error:${NC} Destination directory does not exist: $(dirname "$DESTINATION")"
    exit 1
fi

# Confirmation prompt
echo -e "\n${YELLOW}You are about to perform rsync with the following settings:${NC}"
echo -e "  Source:      ${GREEN}$SOURCE${NC}"
echo -e "  Destination: ${GREEN}$DESTINATION${NC}\n"
read -rp "Proceed with rsync? (y/n): " CONFIRM

if [[ "$CONFIRM" =~ ^[Yy]$ ]]; then
    echo -e "\n${YELLOW}Starting rsync...${NC}\n"
    rsync -avh --progress "$SOURCE" "$DESTINATION"

    # Check result
    if [ $? -eq 0 ]; then
        echo -e "\n${GREEN}✔ rsync operation completed successfully.${NC}"
    else
        echo -e "\n${RED}✖ rsync encountered an error.${NC}"
    fi
else
    echo -e "${RED}Operation canceled by user.${NC}"
fi
