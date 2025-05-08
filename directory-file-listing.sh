#!/bin/bash

# Ask the user for a directory path
read -p "Enter the directory path to analyze (e.g., /home): " dir_path

# Check if the directory exists
if [ ! -d "$dir_path" ]; then
    echo "Error: Directory '$dir_path' does not exist."
    exit 1
fi

# Output file
output_file="/tmp/directory-listing.txt"

# Generate a sorted list of files by size (largest first)
echo "Listing files in '$dir_path' (sorted by size, largest first):" > "$output_file"
echo "=============================================================" >> "$output_file"

# Use 'find' to get all files, then 'du' to get sizes, and sort numerically (largest first)
find "$dir_path" -type f -exec du -h {} + | sort -rh >> "$output_file"

# Check if leafpad is installed, then open the file
if command -v l3afpad >/dev/null 2>&1; then
    l3afpad "$output_file" &
else
    echo "Leafpad is not installed. You can view the output manually at: $output_file"
    echo "To install leafpad, run: sudo apt install leafpad"
fi

echo "Done! Output saved to: $output_file"

sleep 350

sudo rm /tmp/directory-listing.txt
