#!/bin/bash

# Function to prompt user for path
prompt_for_path() {
    zenity --entry --title="$1" --text="Paste the $1 path:" --width=600 --height=100
}

# Function to display confirmation dialog
confirm_rsync() {
    zenity --question --title="Confirm rsync" --text="Perform rsync task:\n\nSource: $SOURCE\nDestination: $DESTINATION\n\nCancel or Execute?" --width=400
}

# Prompt user for source and destination paths
SOURCE=$(prompt_for_path "source")
DESTINATION=$(prompt_for_path "destination")

confirm_rsync

if [ $? -eq 0 ]; then
    # Execute rsync with progress directly in the default terminal
    rsync --progress -av "$SOURCE" "$DESTINATION"

    # Check the exit status of rsync
    if [ $? -eq 0 ]; then
        zenity --info --title="rsync Completed" --text="rsync operation completed successfully." --width=300
    else
        zenity --error --title="rsync Error" --text="Error during rsync operation. Check the paths and try again." --width=300
    fi
else
    zenity --info --title="rsync Canceled" --text="rsync operation canceled by user." --width=300
fi
