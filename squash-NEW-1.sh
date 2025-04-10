#!/bin/bash

# Function to install required dependencies
install_dependencies() {
    echo "Installing required packages..."
    if command -v apt-get &>/dev/null; then
        sudo apt-get install -y squashfs-tools
    elif command -v dnf &>/dev/null; then
        sudo dnf install -y squashfs-tools
    elif command -v yum &>/dev/null; then
        sudo yum install -y squashfs-tools
    elif command -v pacman &>/dev/null; then
        sudo pacman -S --noconfirm squashfs-tools
    else
        echo "ERROR: Could not detect package manager to install dependencies."
        exit 1
    fi
}

# Function to create the filesystem.squashfs
create_squashfs() {
    local iso_dir="$1"
    echo "Creating filesystem.squashfs..."

    # Ensure the output directory exists
    mkdir -p "$iso_dir/live"

    # Define exclusions for mksquashfs
    local exclude_list=(
        "/dev/*"
        "/proc/*"
        "/sys/*"
        "/tmp/*"
        "/run/*"
        "/mnt/*"
        "/media/*"
        "/lost+found"
        "/var/tmp/*"
        "/var/cache/apt/archives/*"
        "/var/lib/apt/lists/*"
        "/home/$USER"
        "/home/*.iso"
        "/root/.bash_history"
        "/root/.cache/*"
        "/usr/src/*"
        "/boot/*rescue*"
        "/boot/System.map*"
        "/boot/vmlinuz.old"
        "/swapfile"
        "/swap.img"
    )

    # Convert exclusions into a format suitable for mksquashfs
    local exclude_args=()
    for item in "${exclude_list[@]}"; do
        exclude_args+=("-e" "$item")
    done

    # Create the squashfs file
    echo "Creating filesystem.squashfs directly (this may take a while)..."
    sudo mksquashfs \
        / \
        "$iso_dir/live/filesystem.squashfs" \
        -comp xz \
        -b 1048576 \
        -noappend \
        "${exclude_args[@]}"

    local squashfs_result=$?
    if [ $squashfs_result -ne 0 ]; then
        echo "Error creating squashfs filesystem"
        exit 1
    fi

    # Verify the squashfs file
    if ! unsquashfs -s "$iso_dir/live/filesystem.squashfs" > /dev/null; then
        echo "Error: Created squashfs file is invalid"
        exit 1
    fi

    echo "filesystem.squashfs created successfully at $iso_dir/live/"
}

# Main script execution
main() {
    echo "=== SquashFS Creation Script ==="

    # Check and install dependencies
    if ! command -v mksquashfs &>/dev/null; then
        install_dependencies
    fi

    # Get ISO directory name
    read -p "Enter the name for your ISO directory (this will be used for directory structure): " iso_name
    local iso_dir="/home/$iso_name"

    # Remove previous directory if it exists
    if [ -d "$iso_dir" ]; then
        echo "Removing previous $iso_dir..."
        sudo rm -rf "$iso_dir"
    fi

    # Create the squashfs
    create_squashfs "$iso_dir"
}

# Run main function
main
