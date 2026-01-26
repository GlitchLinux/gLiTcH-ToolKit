#!/bin/bash
# MiniTrixie Persistent Docker - Install & Launch
# https://glitchlinux.wtf

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
CYAN='\033[0;36m'
NC='\033[0m'

echo -e "${CYAN}╭─────────────────────────────────╮${NC}"
echo -e "${CYAN}│ MiniTrixie Persistent Installer │${NC}"
echo -e "${CYAN}╰─────────────────────────────────╯${NC}"

# Root check
if [ "$EUID" -ne 0 ]; then
    echo -e "${RED}Run as root${NC}"
    exit 1
fi

# Install Docker if missing
if ! command -v docker &>/dev/null; then
    echo -e "${CYAN}[+] Installing Docker...${NC}"
    apt-get update -qq
    apt-get install -y -qq docker.io || {
        # Fallback for non-Debian
        curl -fsSL https://get.docker.com | sh
    }
    systemctl enable --now docker
    echo -e "${GREEN}[✓] Docker installed${NC}"
else
    echo -e "${GREEN}[✓] Docker present${NC}"
fi

# Pull MiniTrixie
IMAGE="glitchlinux/minitrixie:persistent-v2"
URL="https://glitchlinux.wtf/docker/minitrixie-persistent-v2.tar.gz"

if ! docker images --format '{{.Repository}}:{{.Tag}}' | grep -q "^${IMAGE}$"; then
    echo -e "${CYAN}[+] Downloading MiniTrixie...${NC}"
    curl -L "$URL" | gunzip | docker import - "$IMAGE"
    echo -e "${GREEN}[✓] Image imported${NC}"
else
    echo -e "${GREEN}[✓] Image exists${NC}"
fi

# Launch
echo -e "${CYAN}[+] Launching MiniTrixie...${NC}"
exec docker run -it --rm "$IMAGE" /bin/bash
