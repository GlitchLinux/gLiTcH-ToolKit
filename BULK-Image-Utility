#!/usr/bin/env bash
# ─────────────────────────────────────────────
#  install_bulk.sh — Installer for bulk image tool
# ─────────────────────────────────────────────

R='\033[0;31m'  G='\033[0;32m'  Y='\033[1;33m'
C='\033[0;36m'  W='\033[1;37m'
DIM='\033[2m'   BOLD='\033[1m'  NC='\033[0m'

echo -e ""
echo -e "${C}${BOLD}  ██████╗ ██╗   ██╗██╗     ██╗  ██╗"
echo -e "  ██╔══██╗██║   ██║██║     ██║ ██╔╝"
echo -e "  ██████╔╝██║   ██║██║     █████╔╝ "
echo -e "  ██╔══██╗██║   ██║██║     ██╔═██╗ "
echo -e "  ██████╔╝╚██████╔╝███████╗██║  ██╗"
echo -e "  ╚═════╝  ╚═════╝ ╚══════╝╚═╝  ╚═╝${NC}"
echo -e "  ${DIM}  INSTALLER   ·   bulk image tool${NC}"
echo -e ""

# ── Root check ────────────────────────────────
if [ "$EUID" -ne 0 ]; then
  echo -e "${R}✗  Please run as root (sudo ./install_bulk.sh)${NC}"
  exit 1
fi

# ── Dependencies ──────────────────────────────
echo -e "${W}> Installing dependencies…${NC}"

apt-get update -qq

PKGS=(imagemagick optipng curl bc)
for pkg in "${PKGS[@]}"; do
  printf "  %-20s" "$pkg"
  if dpkg -s "$pkg" &>/dev/null; then
    echo -e "${DIM}already installed${NC}"
  else
    if apt-get install -y -qq "$pkg" &>/dev/null; then
      echo -e "${G}✓ installed${NC}"
    else
      echo -e "${R}✗ failed${NC}"
    fi
  fi
done

# ── Fetch script ──────────────────────────────
echo ""
echo -e "${W}> Fetching bulk from GitHub…${NC}"

URL="https://raw.githubusercontent.com/GlitchLinux/bulk/refs/heads/main/bulk"
DEST="/usr/local/bin/bulk"

if curl -fsSL "$URL" -o "$DEST"; then
  echo -e "  ${G}✓ Downloaded → ${DEST}${NC}"
else
  echo -e "  ${R}✗ Download failed. Check URL or network.${NC}"
  exit 1
fi

# ── Permissions ───────────────────────────────
chmod +x "$DEST"
echo -e "  ${G}✓ chmod +x ${DEST}${NC}"

# ── Done ──────────────────────────────────────
echo ""
echo -e "  ┌─────────────────────────────────────┐"
printf  "  │  ${G}${BOLD}✓ Installation complete!${NC}             │\n"
printf  "  │  Run with: ${BOLD}%-26s${NC}│\n" "bulk"
echo -e "  └─────────────────────────────────────┘"
echo ""
