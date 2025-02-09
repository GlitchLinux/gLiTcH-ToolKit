#!/bin/bash

# Function to display a separator line
function separator_line() {
    echo "----------------------------------------"
}

sudo apt update && sudo apt install nala -y

# Automatically fetch new mirrors
sudo nala fetch 

# Update package lists
sudo nala update

# Upgrade installed packages
sudo nala upgrade

# Install any missing dependencies
nala install -f

# Remove unused packages
nala autoremove

# Clean up the package cache
nala clean

# Display a separator line for clarity
separator_line

# Optional: Display the list of available upgrades
echo "List of available upgrades:"
nala list --upgradeable

# Optional: Display the transaction history
echo "Package transaction history:"
nala history

# Display a separator line for clarity
separator_line

echo "Script completed successfully."

# Get the PID of the current shell
current_pid=$$

# Sleep for a short duration to allow the script to finish
sleep 2

# Kill the terminal that launched the script
kill -9 $current_pid
