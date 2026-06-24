#!/bin/bash
#
# gLiTcH-ToolKit Installer
# Creates: /usr/local/bin/apps, /usr/local/bin/.apps, /usr/local/bin/gui-apps, /usr/local/bin/cli-apps
#

set -uo pipefail

# Colors
Y='\033[1;35m'    # bright pink
C='\033[0;36m'    # cyan
G='\033[1;32m'    # bright green
R='\033[0;31m'    # red
N='\033[0m'       # reset

echo -e "${C}gLiTcH-ToolKit Installer${N}\n"

# Check if we need sudo
if [ "$EUID" -ne 0 ]; then
    echo -e "${Y}This installer needs sudo access to write to /usr/local/bin${N}"
    sudo bash "$0"
    exit $?
fi

# === Universal App Launcher ===
echo -e "${C}Installing: /usr/local/bin/apps${N}"
cat > /usr/local/bin/apps << 'EOF'
#!/bin/bash
if [ -n "$DISPLAY" ]; then
    bash /usr/local/bin/gui-apps
else
    bash /usr/local/bin/cli-apps
fi
EOF
chmod 755 /usr/local/bin/apps
echo -e "${G}✓ Created /usr/local/bin/apps${N}"

# === GUI Launcher ===
echo -e "${C}Installing: /usr/local/bin/gui-apps${N}"
cat > /usr/local/bin/gui-apps << 'EOF'
#!/bin/bash
xterm -maximize -fs 14 -e 'bash /usr/local/bin/.apps' 2>&1 &
sleep 1 && exit
EOF
chmod 755 /usr/local/bin/gui-apps
echo -e "${G}✓ Created /usr/local/bin/gui-apps${N}"

# === CLI Launcher ===
echo -e "${C}Installing: /usr/local/bin/cli-apps${N}"
cat > /usr/local/bin/cli-apps << 'EOF'
#!/bin/bash
bash /usr/local/bin/.apps
EOF
chmod 755 /usr/local/bin/cli-apps
echo -e "${G}✓ Created /usr/local/bin/cli-apps${N}"

# === Main Toolkit Script ===
echo -e "${C}Installing: /usr/local/bin/.apps (main toolkit)${N}"
cat > /usr/local/bin/.apps << 'TOOLKIT'
#!/bin/bash
#
# gLiTcH-ToolKit launcher
# Browse, search, run, and copy scripts from the gLiTcH-ToolKit repo.
#

set -uo pipefail

# Colors (truecolor — needs a 24-bit capable terminal)
NUM_NORMAL='\033[38;2;0;255;11m'      # #00ff0b — bright green (normal mode)
NUM_SUDO='\033[38;2;219;0;185m'       # #db00b9 — magenta     (sudo mode)
Y='\033[1;35m'                        # bright pink (highlights)
C='\033[0;36m'                        # cyan
RC='\033[0;31m'                       # red (sudo marker)
N='\033[0m'                           # reset

REPO="https://github.com/GlitchLinux/gLiTcH-ToolKit.git"
DIR="/tmp/gLiTcH-ToolKit"

# State
declare -a T=()
SUDO_MODE=0      # 0 = normal, 1 = sudo

# Active number color for current mode
num_color() {
    if (( SUDO_MODE == 1 )); then
        printf '%b' "$NUM_SUDO"
    else
        printf '%b' "$NUM_NORMAL"
    fi
}

# Prompt marker (e.g. " x :~$" or " ROOT :~$") — leading space included
prompt_marker() {
    if (( SUDO_MODE == 1 )); then
        printf ' %bROOT :~$%b' "$RC" "$N"
    else
        printf ' %b%s :~$%b' "$C" "$USER" "$N"
    fi
}

# Sync repo: git pull if exists, else clone. Falls back to fresh clone on pull failure.
sync_repo() {
    local sudo_cmd=""
    [ "${1:-}" = "root" ] && sudo_cmd="sudo"

    if [ -d "$DIR/.git" ]; then
        if ! $sudo_cmd git -C "$DIR" pull --quiet --ff-only 2>/dev/null; then
            echo -e "${Y}Pull failed, performing fresh clone...${N}"
            $sudo_cmd rm -rf "$DIR" 2>/dev/null
            $sudo_cmd git clone --quiet "$REPO" "$DIR"
        fi
    else
        $sudo_cmd rm -rf "$DIR" 2>/dev/null
        $sudo_cmd git clone --quiet "$REPO" "$DIR"
    fi
}

# Refresh tool list
refresh_list() {
    mapfile -t T < <(find "$DIR" -type f -not -path "*/.git*" -printf "%f\n" | sort -f)
}

# Column layout based on terminal width and longest filename
calculate_layout() {
    local items=$1
    local maxlen=$2
    local min_cols=3
    local max_cols=4
    local terminal_width=${COLUMNS:-80}
    local col_width=$((maxlen + 6))

    local possible_cols=$(( terminal_width / col_width ))
    possible_cols=$(( possible_cols > max_cols ? max_cols : possible_cols ))
    possible_cols=$(( possible_cols < min_cols ? min_cols : possible_cols ))

    local rows=$(( (items + possible_cols - 1) / possible_cols ))
    echo "$possible_cols $rows $col_width"
}

# Display the full tool grid
display_tools() {
    local tools=("$@")
    local count=${#tools[@]}
    local cols rows col_width maxlen=0
    local nc
    nc="$(num_color)"

    for t in "${tools[@]}"; do
        (( ${#t} > maxlen )) && maxlen=${#t}
    done

    read -r cols rows col_width <<< "$(calculate_layout "$count" "$maxlen")"
    local pad=$((col_width - 5))

    local mode_label="NORMAL"
    (( SUDO_MODE == 1 )) && mode_label="SUDO"
    echo -e "${C}Glitch Toolkit - ${count} tools available  [${mode_label}]${N}\n"

    for ((row=0; row<rows; row++)); do
        for ((col=0; col<cols; col++)); do
            local index=$((row + col*rows))
            if (( index < count )); then
                printf "${nc}%3d.${N} %-*s" "$((index+1))" "$pad" "${tools[index]}"
            fi
        done
        echo
    done
}

# Run a tool by its 1-based index in T[]; uses sudo when in sudo mode
run_tool() {
    local idx=$1
    clear
    echo -e "${Y}Running: ${T[idx-1]}${N}\n"
    local F="$DIR/${T[idx-1]}"
    local runner=()
    (( SUDO_MODE == 1 )) && runner=(sudo)

    if [ -x "$F" ]; then
        ( "${runner[@]}" "$F" ) || true
    else
        ( "${runner[@]}" bash "$F" ) || true
    fi
    echo -en "\n${C}Press Enter to continue...${N}"
    read -r
}

# Copy mode — guided multi-step prompt. Returns silently on B/Q-back.
# Uses 'return 2' to signal "user wants to fully quit the launcher".
copy_mode() {
    local marker nc
    marker="$(prompt_marker)"
    nc="$(num_color)"

    # --- Step 1: pick script number ---
    clear
    display_tools "${T[@]}"
    echo
    printf '%b %b[Enter script number to copy]: [%bB%b]ack [%bQ%b]uit%b > ' \
        "$marker" "$C" "$nc" "$C" "$nc" "$C" "$N"
    local IDX
    read -r IDX
    case "${IDX,,}" in
        b|"") return 0 ;;
        q)    exit 0 ;;
    esac
    if ! [[ "$IDX" =~ ^[0-9]+$ ]] || (( IDX < 1 || IDX > ${#T[@]} )); then
        echo -e "${Y}Invalid number${N}"
        sleep 1
        return 0
    fi

    local src_name="${T[IDX-1]}"
    local src_path="$DIR/$src_name"

    # --- Step 2: destination path ---
    printf '%b %b[Enter copy Path]: [%bB%b]ack [%bQ%b]uit%b > ' \
        "$marker" "$C" "$nc" "$C" "$nc" "$C" "$N"
    local DEST_RAW
    read -r DEST_RAW
    case "${DEST_RAW,,}" in
        b|"") return 0 ;;
        q)    exit 0 ;;
    esac
    # Expand ~ and env vars
    local DEST
    DEST=$(eval echo "$DEST_RAW")

    # --- Step 3: rename ---
    printf '%b %b[Rename File]: [%bB%b]ack [%bQ%b]uit [New name or enter to skip]%b > ' \
        "$marker" "$C" "$nc" "$C" "$nc" "$C" "$N"
    local NEW_NAME
    read -r NEW_NAME
    case "${NEW_NAME,,}" in
        b)    return 0 ;;
        q)    exit 0 ;;
    esac
    [ -z "$NEW_NAME" ] && NEW_NAME="$src_name"

    # Resolve final destination path
    local final_path
    if [[ "$DEST" == */ ]] || [ -d "$DEST" ]; then
        final_path="${DEST%/}/$NEW_NAME"
        local target_dir="${DEST%/}"
    else
        # Treat DEST as a full path; if NEW_NAME differs from basename, append it
        if [ "$NEW_NAME" = "$src_name" ]; then
            final_path="$DEST"
        else
            final_path="$(dirname "$DEST")/$NEW_NAME"
        fi
        local target_dir
        target_dir="$(dirname "$final_path")"
    fi

    # --- Step 4: executable? ---
    printf '%b %b[Make Executable?]: [%bB%b]ack [%bQ%b]uit%b > Y/n : ' \
        "$marker" "$C" "$nc" "$C" "$nc" "$C" "$N"
    local EXEC
    read -r EXEC
    case "${EXEC,,}" in
        b)    return 0 ;;
        q)    exit 0 ;;
    esac
    local make_exec=1
    [[ "${EXEC,,}" == "n" || "${EXEC,,}" == "no" ]] && make_exec=0

    # --- Perform operation ---
    local sudo_cmd=()
    (( SUDO_MODE == 1 )) && sudo_cmd=(sudo)

    echo
    echo -e "${C}Source:${N}      $src_path"
    echo -e "${C}Destination:${N} $final_path"
    echo -e "${C}Executable:${N}  $([[ $make_exec -eq 1 ]] && echo yes || echo no)"
    (( SUDO_MODE == 1 )) && echo -e "${C}Privilege:${N}   sudo"
    echo

    # Create dir if missing
    if [ ! -d "$target_dir" ]; then
        echo -e "${Y}Target directory does not exist: $target_dir${N}"
        printf 'Create it? Y/n : '
        local MK
        read -r MK
        if [[ "${MK,,}" == "n" || "${MK,,}" == "no" ]]; then
            echo -e "${Y}Aborted${N}"
            sleep 1
            return 0
        fi
        if ! "${sudo_cmd[@]}" mkdir -p "$target_dir"; then
            echo -e "${Y}Failed to create directory${N}"
            sleep 2
            return 0
        fi
    fi

    # Confirm overwrite
    if [ -e "$final_path" ]; then
        printf '%bDestination exists. Overwrite? Y/n :%b ' "$Y" "$N"
        local OW
        read -r OW
        if [[ "${OW,,}" == "n" || "${OW,,}" == "no" ]]; then
            echo -e "${Y}Aborted${N}"
            sleep 1
            return 0
        fi
    fi

    if ! "${sudo_cmd[@]}" cp -f "$src_path" "$final_path"; then
        echo -e "${Y}Copy failed${N}"
        sleep 2
        return 0
    fi

    if (( make_exec == 1 )); then
        if ! "${sudo_cmd[@]}" chmod +x "$final_path"; then
            echo -e "${Y}chmod failed${N}"
            sleep 2
            return 0
        fi
    fi

    echo -e "${C}Done.${N} Copied to ${Y}$final_path${N}"
    echo -en "\n${C}Press Enter to continue...${N}"
    read -r
}

# Bottom toolbar — leading space, hides [S]udo and shows [N]ormal when already root
build_toolbar() {
    local nc marker
    nc="$(num_color)"
    marker="$(prompt_marker)"

    if (( SUDO_MODE == 1 )); then
        printf '%b %b[Number|Search]: [%bR%b]efresh [%bC%b]opy [%bN%b]ormal [%bQ%b]uit%b > ' \
            "$marker" "$C" "$nc" "$C" "$nc" "$C" "$nc" "$C" "$nc" "$C" "$N"
    else
        printf '%b %b[Number|Search]: [%bR%b]efresh [%bC%b]opy [%bS%b]udo [%bQ%b]uit%b > ' \
            "$marker" "$C" "$nc" "$C" "$nc" "$C" "$nc" "$C" "$nc" "$C" "$N"
    fi
}

# Initial sync
[ ! -d "$DIR/.git" ] && sync_repo
refresh_list

# Main loop
while true; do
    clear
    display_tools "${T[@]}"

    echo
    echo -en "$(build_toolbar)"
    read -r IN

    # Direct numeric selection
    if [[ "$IN" =~ ^[0-9]+$ ]] && ((IN > 0 && IN <= ${#T[@]})); then
        run_tool "$IN"

    # Refresh (preserves current mode)
    elif [[ "${IN,,}" = "r" ]]; then
        if (( SUDO_MODE == 1 )); then
            sync_repo root
        else
            sync_repo
        fi
        refresh_list

    # Copy mode
    elif [[ "${IN,,}" = "c" ]]; then
        copy_mode

    # Enter sudo mode
    elif [[ "${IN,,}" = "s" ]] && (( SUDO_MODE == 0 )); then
        if sudo -v 2>/dev/null; then
            SUDO_MODE=1
        else
            echo -e "${Y}Sudo authentication failed${N}"
            sleep 1
        fi

    # Drop back to normal mode
    elif [[ "${IN,,}" = "n" ]] && (( SUDO_MODE == 1 )); then
        SUDO_MODE=0

    # Quit
    elif [[ "${IN,,}" = "q" ]]; then
        exit 0

    # Search
    elif [ -n "$IN" ]; then
        M=()
        i=1
        for t in "${T[@]}"; do
            [[ "${t,,}" == *"${IN,,}"* ]] && M+=("$i:$t")
            ((i++))
        done

        if [ ${#M[@]} -eq 1 ]; then
            run_tool "${M[0]%%:*}"

        elif [ ${#M[@]} -gt 1 ]; then
            clear
            nc="$(num_color)"
            echo -e "${C}Found ${#M[@]} matches:${N}\n"
            j=1
            for m in "${M[@]}"; do
                printf "${nc}%d.${N} %s\n" "$j" "${m#*:}"
                ((j++))
            done
            echo -en "\n${C}Select match [1-${#M[@]}] or any key to cancel:${N} "
            read -r S
            if [[ "$S" =~ ^[0-9]+$ ]] && ((S > 0 && S <= ${#M[@]})); then
                run_tool "${M[S-1]%%:*}"
            fi

        else
            echo -e "${Y}No matches found${N}"
            sleep 1
        fi
    fi
done
TOOLKIT
chmod 755 /usr/local/bin/.apps
echo -e "${G}✓ Created /usr/local/bin/.apps${N}"

# === Summary ===
echo
echo -e "${G}========================================${N}"
echo -e "${G}Installation complete!${N}"
echo -e "${G}========================================${N}"
echo
echo -e "${C}Files created:${N}"
echo "  /usr/local/bin/apps      (universal launcher)"
echo "  /usr/local/bin/gui-apps  (GUI chainloader)"
echo "  /usr/local/bin/cli-apps  (CLI chainloader)"
echo "  /usr/local/bin/.apps     (main toolkit)"
echo
echo -e "${C}Usage:${N}"
echo "  $ apps              (auto-detects GUI or CLI mode)"
echo
echo -e "${C}To update toolkit:${N}"
echo "  Edit /usr/local/bin/.apps with new tools"
echo