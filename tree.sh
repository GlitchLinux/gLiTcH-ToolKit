#!/bin/bash
# ============================================
# tree.sh – Enhanced interactive tree viewer
# Features: smart search, ignore patterns, save, stats
# ============================================

set -euo pipefail

# Color codes
readonly RED=$'\033[0;31m'
readonly GREEN=$'\033[0;32m'
readonly YELLOW=$'\033[1;33m'
readonly BLUE=$'\033[0;34m'
readonly NC=$'\033[0m'

# Dependencies check
check_dependencies() {
    if ! command -v tree >/dev/null 2>&1; then
        echo -e "${YELLOW}[*] 'tree' command not found. Installing...${NC}"
        if command -v apt >/dev/null 2>&1; then
            sudo apt update && sudo apt install -y tree >/dev/null 2>&1
        else
            echo -e "${RED}[!] Please install 'tree' manually and re-run this script.${NC}"
            exit 1
        fi
    fi
}

# Cleanup temp files on exit
cleanup() {
    rm -f /tmp/tree_*.tmp 2>/dev/null || true
}
trap cleanup EXIT

# Print banner
print_banner() {
    echo -e "${BLUE}╔════════════════════════════════════════════════════════╗${NC}"
    echo -e "${BLUE}║${NC} Enhanced Tree Viewer – Interactive Directory Explorer ${BLUE}║${NC}"
    echo -e "${BLUE}╚════════════════════════════════════════════════════════╝${NC}"
}

# Print menu
print_menu() {
    echo
    echo -e "${YELLOW}[Menu]${NC}"
    echo "  ${GREEN}[Enter]${NC}  – Exit"
    echo "  ${GREEN}[s]${NC}     – Search (AND/OR logic)"
    echo "  ${GREEN}[f]${NC}     – Filter & redisplay tree"
    echo "  ${GREEN}[d]${NC}     – Show directory stats"
    echo "  ${GREEN}[p]${NC}     – Save to file"
    echo "  ${GREEN}[?]${NC}     – Show this menu"
    echo
}

# Search with AND/OR logic
search_tree() {
    local file="$1"
    local terms="$2"
    local logic="${3:-OR}"
    local result_file="$4"

    > "$result_file"

    if [[ "$logic" == "AND" ]]; then
        local grep_cmd="grep -i"
        for term in $terms; do
            grep_cmd="$grep_cmd -e '$term'"
        done
        eval "$grep_cmd '$file'" >> "$result_file" 2>/dev/null || true
    else
        local pattern=$(echo "$terms" | sed 's/ /|/g')
        grep -iE "$pattern" "$file" >> "$result_file" 2>/dev/null || true
    fi

    sort -u -o "$result_file" "$result_file"
}

# Display results with highlighting
display_results() {
    local file="$1"
    local search_terms="${2:-}"

    if [[ ! -s "$file" ]]; then
        echo -e "${RED}[!] No matches found.${NC}"
        return 1
    fi

    echo -e "${GREEN}[+] Found $(wc -l < "$file") results${NC}"
    echo "────────────────────────────────────────"

    if [[ -n "$search_terms" ]]; then
        local pattern=$(echo "$search_terms" | sed 's/ /|/g')
        grep -iE --color=always "$pattern" "$file" || cat "$file"
    else
        cat "$file"
    fi

    echo "────────────────────────────────────────"
}

# Directory statistics
show_stats() {
    local dir="$1"
    local ignore_pattern="${2:-}"

    echo -e "${BLUE}[Stats for: $dir]${NC}"
    echo

    local file_count dir_count

    if [[ -n "$ignore_pattern" ]]; then
        file_count=$(tree "$dir" -I "$ignore_pattern" --dirsfirst -q 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
        dir_count=$(tree "$dir" -I "$ignore_pattern" --dirsfirst -q 2>/dev/null | tail -1 | awk '{print $3}' || echo "0")
    else
        file_count=$(tree "$dir" --dirsfirst -q 2>/dev/null | tail -1 | awk '{print $1}' || echo "0")
        dir_count=$(tree "$dir" --dirsfirst -q 2>/dev/null | tail -1 | awk '{print $3}' || echo "0")
    fi

    echo "  Files: ${GREEN}$file_count${NC}"
    echo "  Directories: ${GREEN}$dir_count${NC}"
    echo "  Total size: ${GREEN}$(du -sh "$dir" 2>/dev/null | cut -f1)${NC}"
    echo
}

# Save tree with metadata
save_tree() {
    local output_file="$1"
    local search_file="$2"
    local dest="$3"

    if [[ ! -d "$dest" ]]; then
        mkdir -p "$dest" || { echo -e "${RED}[!] Cannot create directory: $dest${NC}"; return 1; }
    fi

    if [[ -s "$search_file" ]]; then
        read -rp "Include search results in save? [Y/n]: " include_search
        include_search=${include_search:-Y}

        if [[ "$include_search" =~ ^[Yy]$ ]]; then
            {
                echo "=== Full Tree Output ==="
                cat "$output_file"
                echo
                echo "=== Search Results ==="
                cat "$search_file"
            } > "$dest/tree_combined.txt"
            echo -e "${GREEN}[+] Saved: $dest/tree_combined.txt${NC}"
        else
            cp "$output_file" "$dest/tree_full.txt"
            cp "$search_file" "$dest/tree_search.txt"
            echo -e "${GREEN}[+] Saved:${NC}"
            echo "    - $dest/tree_full.txt"
            echo "    - $dest/tree_search.txt"
        fi
    else
        cp "$output_file" "$dest/tree_output.txt"
        echo -e "${GREEN}[+] Saved: $dest/tree_output.txt${NC}"
    fi
}

# Main execution
main() {
    check_dependencies

    local LAST_SEARCH_FILE=""

    print_banner
    echo

    read -rp "Enter directory path (default: .): " DIR
    DIR=${DIR:-.}

    if [[ ! -d "$DIR" ]]; then
        echo -e "${RED}[!] Error: '$DIR' is not a valid directory.${NC}"
        exit 1
    fi

    local ABS_PATH DIR_NAME OUTPUT_FILE
    ABS_PATH=$(realpath "$DIR")
    DIR_NAME=$(basename "$ABS_PATH")
    OUTPUT_FILE="/tmp/tree_${DIR_NAME}_$$.txt"

    echo
    read -rp "Folders to ignore (space-separated, leave empty for none): " -a IGNORES
    local IGNORE_PATTERN=""
    if [[ ${#IGNORES[@]} -gt 0 ]]; then
        IGNORE_PATTERN=$(IFS='|'; echo "${IGNORES[*]}")
    fi

    echo -e "${YELLOW}[*] Generating tree...${NC}"
    {
        echo "Directory: $DIR_NAME"
        echo "Full path: $ABS_PATH"
        [[ -n "$IGNORE_PATTERN" ]] && echo "Ignored: ${IGNORES[*]}"
        echo "Generated: $(date)"
        echo "════════════════════════════════════════"
        echo

        if [[ -n "$IGNORE_PATTERN" ]]; then
            tree "$DIR" -I "$IGNORE_PATTERN" --dirsfirst
        else
            tree "$DIR" --dirsfirst
        fi
    } > "$OUTPUT_FILE"

    cat "$OUTPUT_FILE"

    print_menu

    while true; do
        read -rsn1 CHOICE
        echo

        case "$CHOICE" in
            "")
                echo -e "${GREEN}[+] Exiting.${NC}"
                break
                ;;

            [sS])
                read -rp "Search terms (space-separated): " TERMS
                [[ -z "$TERMS" ]] && { echo -e "${YELLOW}[*] Skipped.${NC}"; continue; }

                read -rp "Match logic AND/OR? [O/a]: " LOGIC
                LOGIC=${LOGIC:-OR}
                [[ "$LOGIC" =~ ^[aA]$ ]] && LOGIC="AND" || LOGIC="OR"

                LAST_SEARCH_FILE="/tmp/tree_search_$$.tmp"
                search_tree "$OUTPUT_FILE" "$TERMS" "$LOGIC" "$LAST_SEARCH_FILE"
                display_results "$LAST_SEARCH_FILE" "$TERMS"
                print_menu
                ;;

            [fF])
                local FILTER_FILE="/tmp/tree_filtered_$$.tmp"
                read -rp "Filter pattern (regex): " PATTERN
                [[ -z "$PATTERN" ]] && { echo -e "${YELLOW}[*] Skipped.${NC}"; continue; }

                grep -iE "$PATTERN" "$OUTPUT_FILE" > "$FILTER_FILE" 2>/dev/null || true
                display_results "$FILTER_FILE"
                print_menu
                ;;

            [dD])
                show_stats "$ABS_PATH" "$IGNORE_PATTERN"
                print_menu
                ;;

            [pP])
                read -rp "Save destination (default: current dir): " DEST
                DEST=${DEST:-.}
                save_tree "$OUTPUT_FILE" "${LAST_SEARCH_FILE:-}" "$DEST"
                echo
                print_menu
                ;;

            [?])
                print_menu
                ;;

            *)
                echo -e "${YELLOW}[?] Invalid input. Press '?' for menu or Enter to exit.${NC}"
                ;;
        esac
    done
}

main "$@"
