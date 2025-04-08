#!/bin/bash

# Global variables
GUI_MODE=false
username=""
host=""
password=""
port=22

##############################################################################
# Function Definitions
##############################################################################

# Function to display error and exit
error_exit() {
    local message="$1"
    if [ "$GUI_MODE" = true ] && [ -x "$(command -v zenity)" ]; then
        zenity --error --text="$message" --width=400
    else
        echo -e "\nERROR: $message" >&2
    fi
    exit 1
}

# Function to check dependencies
check_dependencies() {
    local missing=()
    
    if ! command -v sshpass &> /dev/null; then
        missing+=("sshpass")
    fi
    
    if [ "$GUI_MODE" = true ] && ! command -v zenity &> /dev/null; then
        missing+=("zenity")
    fi
    
    if [ ${#missing[@]} -gt 0 ]; then
        error_exit "Missing required packages: ${missing[*]}\nInstall with: sudo apt install ${missing[*]}"
    fi
}

# Function to test SSH connection
test_ssh_connection() {
    if [ "$GUI_MODE" = true ]; then
        if ! sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$host" "exit" 2>&1 | \
           zenity --progress --title="Testing Connection" --text="Connecting to $host..." --percentage=0 --pulsate --auto-close; then
            error_exit "SSH connection failed!\n\nPossible reasons:\n1. Wrong credentials\n2. Server not reachable\n3. SSH service not running\n4. Firewall blocking port $port"
        fi
    else
        echo -n "Testing SSH connection to $host... "
        if ! sshpass -p "$password" ssh -o StrictHostKeyChecking=no -p "$port" "$username@$host" "exit" &>/dev/null; then
            echo "FAILED"
            error_exit "SSH connection failed! Check credentials and try again."
        fi
        echo "OK"
    fi
}

# Function to transfer files
transfer_files() {
    local destination="$1"
    local use_sudo="$2"
    shift 2
    local source_files=("$@")

    if [ "$GUI_MODE" = true ]; then
        (
            echo "10"
            echo "# Preparing transfer..."
            
            if [ "$use_sudo" = true ]; then
                # Create temp directory on remote server
                temp_dir="/tmp/ssh_transfer_$(date +%s)"
                echo "20"
                echo "# Creating temp directory..."
                if ! sshpass -p "$password" ssh -p "$port" "$username@$host" "mkdir -p '$temp_dir'"; then
                    echo "100"
                    error_exit "Failed to create temp directory"
                fi

                # Transfer files to temp location
                echo "40"
                echo "# Transferring to temp location..."
                if ! sshpass -p "$password" scp -P "$port" -o StrictHostKeyChecking=no "${source_files[@]}" "$username@$host:$temp_dir/"; then
                    echo "100"
                    error_exit "Transfer to temp location failed"
                fi

                # Move files to final destination with sudo
                echo "70"
                echo "# Moving to final destination (sudo)..."
                if ! sshpass -p "$password" ssh -p "$port" "$username@$host" \
                    "sudo mkdir -p '$destination' && sudo cp -r '$temp_dir/'* '$destination/' && sudo rm -rf '$temp_dir'"; then
                    echo "100"
                    error_exit "Failed to move files with sudo"
                fi
            else
                # Direct transfer
                echo "50"
                echo "# Transferring files directly..."
                if ! sshpass -p "$password" scp -P "$port" -o StrictHostKeyChecking=no "${source_files[@]}" "$username@$host:$destination"; then
                    echo "100"
                    error_exit "Direct transfer failed"
                fi
            fi

            echo "100"
            echo "# Transfer complete!"
        ) | zenity --progress --title="File Transfer" --text="Starting transfer..." --percentage=0 --auto-close
    else
        echo -n "Starting transfer..."
        
        if [ "$use_sudo" = true ]; then
            # Create temp directory
            temp_dir="/tmp/ssh_transfer_$(date +%s)"
            if ! sshpass -p "$password" ssh -p "$port" "$username@$host" "mkdir -p '$temp_dir'"; then
                echo -e "\rFailed to create temp directory on server"
                exit 1
            fi

            # Transfer to temp location
            printf "\rTransferring to temp location... "
            if ! sshpass -p "$password" scp -P "$port" -o StrictHostKeyChecking=no "${source_files[@]}" "$username@$host:$temp_dir/"; then
                echo -e "\rTransfer to temp location failed"
                exit 1
            fi

            # Move with sudo
            printf "\rMoving to final destination with sudo... "
            if ! sshpass -p "$password" ssh -p "$port" "$username@$host" \
                "sudo mkdir -p '$destination' && sudo cp -r '$temp_dir/'* '$destination/' && sudo rm -rf '$temp_dir'"; then
                echo -e "\rFailed to move files with sudo"
                exit 1
            fi
        else
            # Direct transfer
            if ! sshpass -p "$password" scp -P "$port" -o StrictHostKeyChecking=no "${source_files[@]}" "$username@$host:$destination"; then
                echo -e "\rDirect transfer failed"
                exit 1
            fi
        fi
        
        echo -e "\rTransfer completed successfully!    "
    fi
}

# Function to run in GUI mode
gui_mode() {
    GUI_MODE=true
    check_dependencies

    # Get SSH credentials
    credentials=$(zenity --entry --title="SSH File Transfer" --text="Enter SSH credentials (user@host):" --width=300)
    [ -z "$credentials" ] && error_exit "Credentials are required!"

    # Validate credentials format
    if [[ ! "$credentials" =~ ^[^@]+@[^@]+$ ]]; then
        error_exit "Invalid format! Please use user@host format"
    fi

    username=${credentials%%@*}
    host=${credentials#*@}

    # Get password
    password=$(zenity --password --title="SSH Authentication" --text="Enter password for $credentials:")
    [ -z "$password" ] && error_exit "Password is required!"

    # Get SSH port with default 22
    port=$(zenity --entry --title="SSH Port" --text="Enter SSH port:" --entry-text="22")
    port=${port:-22}

    # Test SSH connection
    test_ssh_connection

    # Select files to transfer
    files=$(zenity --file-selection --title="Select Files/Directories to Transfer" --multiple --separator=" ")
    [ -z "$files" ] && error_exit "No files selected!"

    # Convert to array
    IFS='|' read -ra files_array <<< "$files"

    # Get destination path
    destination=$(zenity --entry --title="Destination Path" --text="Enter destination path on remote host:" --entry-text="/home/$username/")
    [ -z "$destination" ] && error_exit "Destination path is required!"

    # Check if destination requires sudo
    use_sudo=false
    if [[ "$destination" =~ ^/(var|etc|usr|root)/ ]]; then
        zenity --question --title="Privileged Directory" --text="The destination directory appears to be system-protected.\n\nDo you need to use sudo to transfer files there?" --width=400
        [ $? -eq 0 ] && use_sudo=true
    fi

    # Confirm transfer
    zenity --question --title="Confirm Transfer" --text="Transfer ${#files_array[@]} item(s) to $host:$destination $( [ "$use_sudo" = true ] && echo "using sudo" )?" --width=300
    [ $? -ne 0 ] && return

    # Perform transfer
    transfer_files "$destination" "$use_sudo" "${files_array[@]}"

    # Verify transfer
    zenity --info --title="Transfer Complete" --text="Files transferred to $host:$destination $( [ "$use_sudo" = true ] && echo "using sudo" )" --width=300
}

# Function to run in CLI mode
cli_mode() {
    GUI_MODE=false
    check_dependencies

    # Get SSH credentials
    read -p "Enter SSH credentials (user@host): " credentials
    [ -z "$credentials" ] && error_exit "Credentials are required!"

    # Validate credentials format
    if [[ ! "$credentials" =~ ^[^@]+@[^@]+$ ]]; then
        error_exit "Invalid format! Please use user@host format"
    fi

    username=${credentials%%@*}
    host=${credentials#*@}

    # Get password securely
    read -s -p "Enter password for $credentials: " password
    echo
    [ -z "$password" ] && error_exit "Password is required!"

    # Get SSH port with default 22
    read -p "Enter SSH port [22]: " port
    port=${port:-22}

    # Test SSH connection
    test_ssh_connection

    # Get files to transfer
    echo "Enter paths of files/directories to transfer (one per line, press Enter on empty line to finish):"
    local files=()
    while true; do
        read -e -p "> " file
        [ -z "$file" ] && break
        # Expand path to handle relative paths
        file=$(realpath -e "$file" 2>/dev/null || echo "$file")
        files+=("$file")
    done

    [ ${#files[@]} -eq 0 ] && error_exit "No files specified!"

    # Get destination path
    read -p "Enter destination path on remote host [/home/$username/]: " destination
    destination=${destination:-"/home/$username/"}

    # Check if destination requires sudo
    use_sudo=false
    if [[ "$destination" =~ ^/(var|etc|usr|root)/ ]]; then
        read -p "The destination appears to be system-protected. Use sudo for transfer? [y/N]: " sudo_choice
        [[ "$sudo_choice" =~ ^[Yy]$ ]] && use_sudo=true
    fi

    # Confirm transfer
    echo -e "\nFiles to transfer:"
    printf -- '- %s\n' "${files[@]}"
    echo -e "\nDestination: $host:$destination"
    [ "$use_sudo" = true ] && echo "Will use sudo for transfer"
    read -p "Confirm transfer? [y/N]: " confirm
    [[ ! "$confirm" =~ ^[Yy]$ ]] && return

    # Perform transfer
    transfer_files "$destination" "$use_sudo" "${files[@]}"

    # Verify transfer
    echo -e "\nTransfer completed $( [ "$use_sudo" = true ] && echo "with sudo" )"
    echo "Files successfully transferred to $host:$destination"
}

##############################################################################
# Main Script
##############################################################################

main() {
    while true; do
        clear
        echo "=== SSH File Transfer Script ==="
        echo "=== Supports privileged directories with sudo ==="
        echo ""
        echo "1) GUI Mode (Graphical)"
        echo "2) CLI Mode (Command Line)"
        echo "3) Exit"
        echo ""
        
        # Check if running in terminal
        if [ -t 0 ]; then
            read -p "Select mode (1-3): " choice
            case $choice in
                1) 
                    if ! command -v zenity &> /dev/null; then
                        echo -e "\nzenity is not installed. Falling back to CLI mode."
                        sleep 2
                        cli_mode
                    else
                        gui_mode
                    fi
                    ;;
                2) cli_mode ;;
                3) 
                    echo "Goodbye!"
                    exit 0
                    ;;
                *) 
                    echo "Invalid option. Please enter 1, 2, or 3."
                    sleep 1
                    ;;
            esac
        else
            # Non-interactive (e.g., double-clicked) - default to GUI
            GUI_MODE=true
            if ! command -v zenity &> /dev/null; then
                error_exit "zenity is required for GUI mode but not installed.\nPlease install with: sudo apt install zenity"
            fi
            gui_mode
            break
        fi
        
        # Pause before showing menu again
        if [ "$choice" != "3" ]; then
            echo ""
            read -n 1 -s -r -p "Press any key to continue..."
        fi
    done
}

# Ensure all functions are defined before calling main
main
