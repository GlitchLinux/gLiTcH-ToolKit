#!/bin/bash
#══════════════════════════════════════════════════════════════════════════════
# KDE-Styler-Wizard.sh - Interactive wrapper for kde-styler.py
# Auto-fetches kde-styler.py from GitHub if not present
#══════════════════════════════════════════════════════════════════════════════

REPO_URL="https://raw.githubusercontent.com/GlitchLinux/KDE-Styler/main"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
KDE_STYLER="${SCRIPT_DIR}/kde-styler.py"

# Colors
R='\033[0;31m' G='\033[0;32m' Y='\033[1;33m' B='\033[0;34m' C='\033[0;36m' 
BOLD='\033[1m' NC='\033[0m'

# Default paths
DEFAULT_BACKUP_DIR="$HOME/KDE-Styler-Backups"

clear_screen() { printf '\033[2J\033[H'; }

header() {
    clear_screen
    echo -e "${BOLD}${C}"
    echo "╔══════════════════════════════════════════════════════════════╗"
    echo "║                    KDE-STYLER WIZARD                         ║"
    echo "║              Backup & Restore KDE Appearance                 ║"
    echo "╚══════════════════════════════════════════════════════════════╝"
    echo -e "${NC}"
}

fetch_kde_styler() {
    echo -e "${B}[INFO]${NC} Fetching kde-styler.py from GitHub..."
    
    if command -v curl &>/dev/null; then
        curl -fsSL "${REPO_URL}/kde-styler.py" -o "$KDE_STYLER"
    elif command -v wget &>/dev/null; then
        wget -q "${REPO_URL}/kde-styler.py" -O "$KDE_STYLER"
    else
        echo -e "${R}[ERROR]${NC} Neither curl nor wget found. Install one:"
        echo "  sudo apt install curl"
        return 1
    fi
    
    if [[ $? -eq 0 && -f "$KDE_STYLER" ]]; then
        chmod +x "$KDE_STYLER"
        echo -e "${G}[SUCCESS]${NC} Downloaded kde-styler.py"
        return 0
    else
        echo -e "${R}[ERROR]${NC} Failed to download kde-styler.py"
        return 1
    fi
}

check_deps() {
    # Check/fetch kde-styler.py
    if [[ ! -f "$KDE_STYLER" ]]; then
        echo -e "${Y}[WARNING]${NC} kde-styler.py not found locally"
        fetch_kde_styler || exit 1
    fi
    
    # Check python3
    if ! command -v python3 &>/dev/null; then
        echo -e "${R}[ERROR]${NC} python3 not found. Install it:"
        echo "  sudo apt install python3"
        exit 1
    fi
    
    # Check dpkg-repack (optional but recommended)
    if ! command -v dpkg-repack &>/dev/null; then
        echo -e "${Y}[WARNING]${NC} dpkg-repack not found. Installing..."
        sudo apt-get install -y dpkg-repack fakeroot 2>/dev/null || {
            echo -e "${Y}[WARNING]${NC} Could not install dpkg-repack (optional)"
        }
    fi
}

update_kde_styler() {
    header
    echo -e "${BOLD}UPDATE KDE-STYLER${NC}\n"
    echo -e "This will download the latest kde-styler.py from GitHub.\n"
    read -p "Continue? [Y/n]: " confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        return
    fi
    
    # Backup current version
    if [[ -f "$KDE_STYLER" ]]; then
        cp "$KDE_STYLER" "${KDE_STYLER}.bak"
    fi
    
    if fetch_kde_styler; then
        echo -e "\n${G}[SUCCESS]${NC} Updated to latest version"
        rm -f "${KDE_STYLER}.bak"
    else
        # Restore backup on failure
        if [[ -f "${KDE_STYLER}.bak" ]]; then
            mv "${KDE_STYLER}.bak" "$KDE_STYLER"
            echo -e "${Y}[INFO]${NC} Restored previous version"
        fi
    fi
    
    read -p "Press Enter to continue..."
}

show_current() {
    header
    echo -e "${B}[INFO]${NC} Current KDE Appearance Settings:\n"
    python3 "$KDE_STYLER" show
    echo ""
    read -p "Press Enter to continue..."
}

do_backup() {
    header
    echo -e "${BOLD}CREATE BACKUP${NC}\n"
    
    echo -e "Default backup directory: ${C}$DEFAULT_BACKUP_DIR${NC}"
    echo ""
    read -e -p "Backup location [Enter for default]: " backup_path
    
    if [[ -z "$backup_path" ]]; then
        mkdir -p "$DEFAULT_BACKUP_DIR"
        backup_path=""
        backup_dir="$DEFAULT_BACKUP_DIR"
    else
        backup_path="${backup_path/#\~/$HOME}"
        backup_dir="$(dirname "$backup_path")"
        mkdir -p "$backup_dir"
    fi
    
    echo ""
    read -p "Create .tar.gz archive as well? [y/N]: " create_archive
    
    echo ""
    echo -e "${Y}═══════════════════════════════════════════════════════════════${NC}"
    if [[ -z "$backup_path" ]]; then
        echo -e "  Backup to: ${C}$DEFAULT_BACKUP_DIR/KDE-Styler-Backup-<timestamp>${NC}"
    else
        echo -e "  Backup to: ${C}$backup_path${NC}"
    fi
    [[ "$create_archive" =~ ^[Yy]$ ]] && echo -e "  Archive:   ${C}Yes${NC}"
    echo -e "${Y}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    read -p "Proceed with backup? [Y/n]: " confirm
    
    if [[ "$confirm" =~ ^[Nn]$ ]]; then
        echo -e "${Y}[CANCELLED]${NC} Backup cancelled."
        sleep 1
        return
    fi
    
    cmd="python3 \"$KDE_STYLER\" backup"
    [[ -n "$backup_path" ]] && cmd+=" -o \"$backup_path\""
    [[ "$create_archive" =~ ^[Yy]$ ]] && cmd+=" --archive"
    
    echo ""
    eval "$cmd"
    
    echo ""
    echo -e "${G}[DONE]${NC} Backup complete!"
    read -p "Press Enter to continue..."
}

list_backups() {
    local dir="$1"
    local backups=()
    
    if [[ -d "$dir" ]]; then
        while IFS= read -r -d '' item; do
            backups+=("$item")
        done < <(find "$dir" -maxdepth 1 \( -type d -name "KDE-Styler-Backup*" -o -name "*.tar.gz" \) -print0 2>/dev/null | sort -z)
    fi
    
    echo "${backups[@]}"
}

do_restore() {
    header
    echo -e "${BOLD}RESTORE BACKUP${NC}\n"
    
    echo -e "Scanning ${C}$DEFAULT_BACKUP_DIR${NC} for backups...\n"
    
    backups=($(list_backups "$DEFAULT_BACKUP_DIR"))
    
    if [[ ${#backups[@]} -gt 0 ]]; then
        echo -e "${BOLD}Available backups:${NC}"
        echo ""
        i=1
        for backup in "${backups[@]}"; do
            name=$(basename "$backup")
            if [[ -d "$backup" ]]; then
                size=$(du -sh "$backup" 2>/dev/null | cut -f1)
                echo -e "  ${C}[$i]${NC} $name ${Y}($size)${NC}"
            else
                size=$(du -h "$backup" 2>/dev/null | cut -f1)
                echo -e "  ${C}[$i]${NC} $name ${Y}($size, archive)${NC}"
            fi
            ((i++))
        done
        echo -e "  ${C}[0]${NC} Enter custom path"
        echo ""
        
        read -p "Select backup [1-$((i-1))] or 0 for custom: " selection
        
        if [[ "$selection" == "0" ]]; then
            read -e -p "Enter backup path: " restore_path
            restore_path="${restore_path/#\~/$HOME}"
        elif [[ "$selection" =~ ^[0-9]+$ ]] && (( selection >= 1 && selection < i )); then
            restore_path="${backups[$((selection-1))]}"
        else
            echo -e "${R}[ERROR]${NC} Invalid selection"
            sleep 1
            return
        fi
    else
        echo -e "${Y}No backups found in default location.${NC}\n"
        read -e -p "Enter backup path: " restore_path
        restore_path="${restore_path/#\~/$HOME}"
    fi
    
    if [[ ! -e "$restore_path" ]]; then
        echo -e "${R}[ERROR]${NC} Path does not exist: $restore_path"
        sleep 2
        return
    fi
    
    echo ""
    echo -e "${BOLD}Restore Options:${NC}"
    echo ""
    read -p "Aggressive mode (delete existing configs)? [Y/n]: " aggressive
    read -p "Restart Plasma shell after restore? [Y/n]: " restart
    
    echo ""
    echo -e "${R}═══════════════════════════════════════════════════════════════${NC}"
    echo -e "  Restore from: ${C}$restore_path${NC}"
    [[ ! "$aggressive" =~ ^[Nn]$ ]] && echo -e "  Mode:         ${R}AGGRESSIVE (will delete existing configs)${NC}"
    [[ ! "$aggressive" =~ ^[Nn]$ ]] || echo -e "  Mode:         ${G}Merge (keep existing configs)${NC}"
    [[ ! "$restart" =~ ^[Nn]$ ]] && echo -e "  Restart:      ${Y}Yes${NC}"
    echo -e "${R}═══════════════════════════════════════════════════════════════${NC}"
    echo ""
    echo -e "${Y}WARNING: This will modify your KDE appearance settings!${NC}"
    read -p "Proceed with restore? [y/N]: " confirm
    
    if [[ ! "$confirm" =~ ^[Yy]$ ]]; then
        echo -e "${Y}[CANCELLED]${NC} Restore cancelled."
        sleep 1
        return
    fi
    
    cmd="python3 \"$KDE_STYLER\" restore \"$restore_path\""
    [[ "$aggressive" =~ ^[Nn]$ ]] && cmd+=" --no-aggressive"
    [[ "$restart" =~ ^[Nn]$ ]] && cmd+=" --no-restart"
    
    echo ""
    eval "$cmd" << RESTORE_EOF
y
y
RESTORE_EOF
    
    echo ""
    echo -e "${G}[DONE]${NC} Restore complete!"
    read -p "Press Enter to continue..."
}

main_menu() {
    while true; do
        header
        echo -e "${BOLD}Main Menu${NC}\n"
        echo -e "  ${C}[1]${NC} Show current KDE appearance"
        echo -e "  ${C}[2]${NC} Create backup"
        echo -e "  ${C}[3]${NC} Restore from backup"
        echo -e "  ${C}[4]${NC} Open backup folder"
        echo -e "  ${C}[5]${NC} Update kde-styler.py from GitHub"
        echo -e "  ${C}[q]${NC} Quit"
        echo ""
        read -p "Select option: " choice
        
        case "$choice" in
            1) show_current ;;
            2) do_backup ;;
            3) do_restore ;;
            4) 
                mkdir -p "$DEFAULT_BACKUP_DIR"
                if command -v dolphin &>/dev/null; then
                    dolphin "$DEFAULT_BACKUP_DIR" &>/dev/null &
                elif command -v xdg-open &>/dev/null; then
                    xdg-open "$DEFAULT_BACKUP_DIR" &>/dev/null &
                else
                    echo -e "${B}[INFO]${NC} Backup folder: $DEFAULT_BACKUP_DIR"
                    read -p "Press Enter to continue..."
                fi
                ;;
            5) update_kde_styler ;;
            q|Q) 
                clear_screen
                echo -e "${G}Goodbye!${NC}"
                exit 0 
                ;;
            *) 
                echo -e "${R}Invalid option${NC}"
                sleep 0.5
                ;;
        esac
    done
}

# Main
check_deps
main_menu
