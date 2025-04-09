#!/bin/bash

# Author: GlitchLinux
# Description: Script to select and apply keyboard layout in Debian-based distros.

# Function to check if running in X11 or TTY
is_x11() {
    [[ $DISPLAY ]] && return 0 || return 1
}

# Available layouts
declare -A layouts=(
    [1]="us"
    [2]="se"
    [3]="de"
    [4]="fr"
    [5]="gb"
)

echo "Select a keyboard layout:"
for index in "${!layouts[@]}"; do
    echo "$index) ${layouts[$index]}"
done

read -rp "Enter number (e.g. 1): " choice

layout="${layouts[$choice]}"

if [[ -z $layout ]]; then
    echo "Invalid selection."
    exit 1
fi

if is_x11; then
    echo "Setting X11 keyboard layout to '$layout' using setxkbmap..."
    setxkbmap "$layout"
else
    echo "Setting TTY keyboard layout to '$layout' using loadkeys..."
    sudo loadkeys "$layout"
fi

echo "Keyboard layout set to: $layout"
