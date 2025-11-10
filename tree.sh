#!/bin/bash
# ============================================
# tree.sh — Interactive tree viewer with ignore, save, and grep features
# ============================================

# Ensure tree is installed
if ! command -v tree >/dev/null 2>&1; then
    echo "'tree' command not found. Installing..."
    if command -v apt >/dev/null 2>&1; then
        sudo apt update && sudo apt install -y tree
    else
        echo "Please install 'tree' manually and re-run this script."
        exit 1
    fi
fi

echo "=== Tree Viewer with Ignore and Save Options ==="
echo

# Ask for directory
read -rp "Enter the path to display (default: current directory): " DIR
DIR=${DIR:-.}

# Check directory validity
if [[ ! -d "$DIR" ]]; then
    echo "Error: '$DIR' is not a valid directory."
    exit 1
fi

# Resolve absolute path
ABS_PATH=$(realpath "$DIR")
DIR_NAME=$(basename "$ABS_PATH")

# Ask for folders to ignore
echo
read -rp "Enter folder names to ignore (separate by space, leave empty for none): " -a IGNORES

# Build ignore pattern if needed
if [[ ${#IGNORES[@]} -gt 0 ]]; then
    IGNORE_PATTERN=$(IFS='|'; echo "${IGNORES[*]}")
    IGNORE_NOTE="Ignored subfolders in output: ${IGNORES[*]}"
else
    IGNORE_PATTERN=""
    IGNORE_NOTE="No ignored subfolders."
fi

# Output file in /tmp
OUTPUT_FILE="/tmp/tree_${DIR_NAME}.txt"
SEARCH_FILE=""

# Generate tree output
{
    echo "This is a tree output of '$DIR_NAME' located at $ABS_PATH"
    echo "$IGNORE_NOTE"
    echo
    if [[ -n "$IGNORE_PATTERN" ]]; then
        tree "$DIR" -I "$IGNORE_PATTERN"
    else
        tree "$DIR"
    fi
} > "$OUTPUT_FILE"

# Display the tree
cat "$OUTPUT_FILE"

echo
echo "Tree output generated and stored temporarily at: $OUTPUT_FILE"
echo

# Main interactive loop
while true; do
    echo "Hit [Enter] to close"
    echo "Hit [g] to grep search words in tree_${DIR_NAME}.txt"
    echo "Hit [s] to save tree_${DIR_NAME}.txt & tree_${DIR_NAME}_<search>.txt"
    echo
    read -rsn1 CHOICE

    case "$CHOICE" in
        "")  # Enter pressed
            echo "Exiting."
            break
            ;;

        [gG])
            echo
            read -rp "Enter search word(s): " TERMS
            if [[ -z "$TERMS" ]]; then
                echo "No search terms entered."
                continue
            fi

            SEARCH_FILE="/tmp/tree_${DIR_NAME}_search.txt"
            > "$SEARCH_FILE"

            # Simple grep (partial matches, case-insensitive)
            for term in $TERMS; do
                grep -i "$term" "$OUTPUT_FILE" >> "$SEARCH_FILE"
            done

            # Remove duplicates and sort
            sort -u -o "$SEARCH_FILE" "$SEARCH_FILE"

            echo
            echo "Search results for: $TERMS"
            echo "------------------------------------"

            if [[ -s "$SEARCH_FILE" ]]; then
                cat "$SEARCH_FILE"
                echo
                echo "Results saved at: $SEARCH_FILE"
            else
                echo "No matches found."
                rm -f "$SEARCH_FILE"
                SEARCH_FILE=""
            fi
            echo
            ;;

        [sS])
            echo
            read -rp "Enter destination path to save (default: current directory): " DEST
            DEST=${DEST:-.}

            # Handle save logic depending on if a search was done
            if [[ -n "$SEARCH_FILE" && -s "$SEARCH_FILE" ]]; then
                echo
                read -rp "Save as a single merged file? [Y/n]: " MERGE
                MERGE=${MERGE:-Y}

                if [[ "$MERGE" =~ ^[Yy]$ ]]; then
                    MERGED_FILE="$DEST/tree_${DIR_NAME}_merged.txt"
                    cat "$OUTPUT_FILE" "$SEARCH_FILE" > "$MERGED_FILE"
                    echo "Merged file saved as: $MERGED_FILE"
                else
                    TREE_COPY="$DEST/tree_${DIR_NAME}.txt"
                    SEARCH_COPY="$DEST/tree_${DIR_NAME}_search.txt"
                    cp "$OUTPUT_FILE" "$TREE_COPY"
                    cp "$SEARCH_FILE" "$SEARCH_COPY"
                    echo "Saved:"
                    echo " - $TREE_COPY"
                    echo " - $SEARCH_COPY"
                fi
            else
                DEST_FILE="$DEST/tree_${DIR_NAME}.txt"
                cp "$OUTPUT_FILE" "$DEST_FILE"
                echo "Saved as: $DEST_FILE"
            fi
            echo
            ;;

        *)
            echo "Invalid input. Press Enter, g, or s."
            ;;
    esac
done
