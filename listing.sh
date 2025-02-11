
#!/bin/bash

# Set repo URL and local directory
REPO_URL="https://github.com/GlitchLinux/gLiTcH-ToolKit.git"
LOCAL_DIR="gLiTcH-ToolKit"

# Clone or update the repository
if [ -d "$LOCAL_DIR/.git" ]; then
    echo "Updating repository..."
    git -C "$LOCAL_DIR" pull
else
    echo "Cloning repository..."
    git clone "$REPO_URL" "$LOCAL_DIR"
fi

while true; do
    # Scan repository contents and list files/folders
    echo "\nContents of $LOCAL_DIR:"  
    entries=()
    count=1
    while IFS= read -r entry; do
        echo "$count. $entry"
        entries["$count"]="$entry"
        ((count++))
    done < <(find "$LOCAL_DIR" -mindepth 1 -not -path "*/.git*" -printf "%P\n" | sort)

    # Prompt user for selection
    echo "\nEnter a number to execute the corresponding file, or press 0 to quit: "
    read -r choice

    # Exit if user chooses 0
    if [[ "$choice" == "0" ]]; then
        echo "Exiting."
        break
    fi

    # Execute selected file if valid
    if [[ -n "$choice" && -n "${entries[$choice]}" ]]; then
        selected_file="$LOCAL_DIR/${entries[$choice]}"
        if [ -x "$selected_file" ]; then
            echo "Executing $selected_file..."
            "$selected_file"
        else
            echo "Selected file is not executable. Attempting to run with bash..."
            bash "$selected_file"
        fi
    else
        echo "Invalid selection. Please try again."
    fi

done
