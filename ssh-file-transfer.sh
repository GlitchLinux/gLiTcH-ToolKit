#!/bin/bash

# Ensure the script is run as root
if [[ $(id -u) -ne 0 ]]; then
  zenity --error --text="This script must be run as root! Exiting..."
  exit 1
fi

# Install sshpass if not installed
if ! command -v sshpass &>/dev/null; then
  apt update && apt install -y sshpass || {
    zenity --error --text="Failed to install sshpass. Please check your internet connection or package manager."
    exit 1
  }
fi

# Prompt for SSH credentials in a single field (user@ip-address)
credentials=$(zenity --entry --title="SSH File Transfer" --text="Enter the SSH credentials (e.g., user@ip-address):")
if [ -z "$credentials" ]; then
  zenity --error --text="Credentials are required!"
  exit 1
fi

# Extract username and host
username=$(echo "$credentials" | cut -d'@' -f1)
host=$(echo "$credentials" | cut -d'@' -f2)

# Validate extraction
if [ -z "$username" ] || [ -z "$host" ]; then
  zenity --error --text="Invalid format! Please enter in the format user@ip-address."
  exit 1
fi

# Ask for the SSH password securely
password=$(zenity --password --title="SSH Password" --text="Enter the SSH password for $username@$host:")
if [ -z "$password" ]; then
  zenity --error --text="Password is required!"
  exit 1
fi

# Optional: Ask for SSH port (default is 22)
port=$(zenity --entry --title="SSH File Transfer" --text="Enter the SSH Port (default: 22):" --entry-text="22")
port=${port:-22}  # Use 22 if no port is entered

# Validate port number
if ! [[ "$port" =~ ^[0-9]+$ ]] || [ "$port" -lt 1 ] || [ "$port" -gt 65535 ]; then
  zenity --error --text="Invalid port number! Please enter a valid port between 1 and 65535."
  exit 1
fi

# Test SSH connection with sshpass
if ! sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$host" "exit" &>/dev/null; then
  zenity --error --text="Connection failed! Check credentials and try again."
  exit 1
fi

# Select file or directory to transfer
file_path=$(zenity --file-selection --title="Select File or Directory for Transfer" --filename="$HOME/" --multiple)
if [ -z "$file_path" ]; then
  zenity --error --text="No file or directory selected!"
  exit 1
fi

# Specify destination directory on the client
destination=$(zenity --entry --title="SSH File Transfer" --text="Enter the destination path on the SSH client (e.g., /home/username/):")
if [ -z "$destination" ]; then
  zenity --error --text="Destination path is required!"
  exit 1
fi

# Start the transfer and capture process ID
{
  # Use `scp` with progress tracking
  sshpass -p "$password" scp -P "$port" -r $file_path "$username@$host:$destination" &
  transfer_pid=$!
  
  # Monitor the transfer process
  while kill -0 $transfer_pid 2>/dev/null; do
    sleep 1
  done
} | zenity --progress --title="File Transfer Progress" --text="Transferring files to $username@$host:$destination..." --percentage=0 --pulsate

# Check if transfer was successful
if [ $? -eq 0 ]; then
  zenity --info --text="File transfer successful!"
else
  zenity --error --text="File transfer failed! Check if destination directory exists and SSH user has write permissions."
fi
