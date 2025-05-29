#!/bin/bash

# Exit on error and print commands
set -ex

# Update the system and install essential packages
apt-get update
apt-get upgrade -y
apt-get install -y --no-install-recommends \
    sudo \
    curl \
    wget \
    gnupg \
    ca-certificates \
    systemd \
    dbus \
    locales \
    keyboard-configuration \
    console-setup \
    network-manager \
    openssh-server \
    cloud-init \
    ifupdown \
    net-tools \
    iputils-ping \
    dnsutils \
    less \
    git \
    rsync \
    cron \
    logrotate \
    btop \
    iotop \
    iftop \
    ntp \
    ntpdate \
    unattended-upgrades \
    apt-transport-https \
    software-properties-common \
    debconf-utils \
    tasksel \
    debootstrap \
    squashfs-tools \
    xorriso \
    isolinux \
    syslinux-efi \
    grub-pc \
    shim-signed \
    dosfstools \
    mtools \
    memtest86+ \
    ufw \
    fail2ban \
    lm-sensors \
    smartmontools \
    ethtool \
    lshw \
    pciutils \
    usbutils \
    dmidecode \
    hdparm \
    parted \
    gdisk \
    efibootmgr \
    lvm2 \
    mdadm \
    btrfs-progs \
    xfsprogs \
    sshpass

#Kernel modules
sudo apt install --reinstall linux-image-amd64 linux-headers-amd64 -y
sudo apt install mlocate pv xz-utils cpio -y
# Force non-interactive mode (no GUI prompts)
export DEBIAN_FRONTEND=noninteractive

# Set English locale (system language)
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
update-locale LANG=en_US.UTF-8

# Configure network (use NetworkManager)
systemctl enable NetworkManager
systemctl disable networking
echo "nameserver 8.8.8.8" >> /etc/resolv.conf

# Configure SSH
mkdir -p /etc/ssh/sshd_config.d
echo "PermitRootLogin no" > /etc/ssh/sshd_config.d/disable-root.conf
echo "PasswordAuthentication no" >> /etc/ssh/sshd_config.d/disable-root.conf
systemctl enable ssh

# Install cloud-init for cloud compatibility (even if not using cloud)
cat > /etc/cloud/cloud.cfg.d/99_defaults.cfg <<EOF
datasource_list: [ NoCloud, ConfigDrive ]
manage_etc_hosts: true
preserve_hostname: false
ssh_pwauth: false
users:
  - default
  - name: admin
    sudo: ALL=(ALL) NOPASSWD:ALL
    shell: /bin/bash
    ssh_authorized_keys:
      - ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIINSERTYOURPUBLICKEYHERE admin@debian-iso
EOF

# Install additional useful tools
apt-get install -y \
    jq \
    yq \
    screen \
    ncdu \
    tree \
    zip \
    unzip \
    bzip2 \
    lzop \
    p7zip-full \
    nano

# Ensure script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Function to validate username
validate_username() {
    local username="$1"
    if [[ ! "$username" =~ ^[a-z_][a-z0-9_-]*$ ]]; then
        echo "Invalid username: must start with lowercase letter or underscore, and contain only lowercase letters, digits, underscores, or hyphens" >&2
        return 1
    fi
    if id -u "$username" &>/dev/null; then
        echo "User '$username' already exists" >&2
        return 1
    fi
    return 0
}

# Function to validate hostname
validate_hostname() {
    local hostname="$1"
    if [[ ! "$hostname" =~ ^[a-zA-Z0-9][a-zA-Z0-9-]{1,61}[a-zA-Z0-9]$ ]]; then
        echo "Invalid hostname: must be 2-63 characters, alphanumeric with hyphens (but not at start/end)" >&2
        return 1
    fi
    if [[ "$hostname" =~ ^[0-9]+$ ]]; then
        echo "Invalid hostname: cannot be all numbers" >&2
        return 1
    fi
    return 0
}

# Prompt for username
while true; do
    read -rp "Enter new username: " username
    if validate_username "$username"; then
        break
    fi
done

# Prompt for password (twice for verification)
while true; do
    read -rsp "Enter password for $username: " password
    echo
    read -rsp "Confirm password: " password_confirm
    echo
    
    if [ -z "$password" ]; then
        echo "Password cannot be empty" >&2
    elif [ "$password" != "$password_confirm" ]; then
        echo "Passwords do not match" >&2
    else
        break
    fi
done

#!/bin/bash

# Check if script is run as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Prompt user for new hostname
read -p "Enter new hostname: " new_hostname

# Validate input
if [ -z "$new_hostname" ]; then
    echo "Error: Hostname cannot be empty"
    exit 1
fi

echo "Setting hostname to: $new_hostname"

# For read-only container environments, we'll:
# 1. Set the hostname in the current session (may not work in all containers)
if ! echo "$new_hostname" > /proc/sys/kernel/hostname 2>/dev/null; then
    echo "Warning: Could not set transient hostname (read-only filesystem)"
fi

# 2. Set the hostname in environment files
echo "$new_hostname" > /etc/hostname 2>/dev/null || echo "Warning: Could not write to /etc/hostname"

# 3. Update /etc/hosts
if grep -q "127.0.1.1" /etc/hosts; then
    sed -i "s/127.0.1.1.*/127.0.1.1\t$new_hostname/" /etc/hosts
else
    echo -e "127.0.1.1\t$new_hostname" >> /etc/hosts
fi

# 4. Alternative method using hostname command (if available)
if command -v hostname &>/dev/null; then
    hostname "$new_hostname" 2>/dev/null || echo "Warning: hostname command failed"
fi

# 5. Export the hostname to the current environment
export HOSTNAME="$new_hostname"

echo "Hostname configuration attempted. Results may vary in container environments."
echo "For persistent changes in Docker, use --hostname flag when creating containers."

# Create the user
echo "Creating user $username..."
adduser --gecos "" --disabled-password "$username"
echo "$username:$password" | chpasswd

# Add user to sudo group
echo "Adding $username to sudo group..."
usermod -aG sudo "$username"

# Configure sudo without password (optional)
echo "Configuring passwordless sudo for $username..."
echo "$username ALL=(ALL) NOPASSWD:ALL" > "/etc/sudoers.d/90-$username"
chmod 440 "/etc/sudoers.d/90-$username"

# Display summary
echo -e "\n=== Setup Complete ==="
echo "Username: $username"
echo "Hostname: $(hostname)"

cd /
sudo wget https://raw.githubusercontent.com/GlitchLinux/gLiTcH-ToolKit/refs/heads/main/apps
sudo chmod +x apps && sudo chmod 777 apps
sudo cp apps /home && cp apps /home/x && cp apps /root 

cd /tmp
wget https://github.com/GlitchLinux/docker-remastering/raw/refs/heads/main/REFRACTA-ALL-TOOLS_DEB_FILES/refractasnapshot-base_10.2.12_all.deb
wget https://github.com/GlitchLinux/docker-remastering/raw/refs/heads/main/REFRACTA-ALL-TOOLS_DEB_FILES/live-config-refracta_0.0.5.deb
wget https://github.com/GlitchLinux/docker-remastering/raw/refs/heads/main/REFRACTA-ALL-TOOLS_DEB_FILES/live-boot-initramfs-tools_20221008~fsr1_all.deb
wget https://github.com/GlitchLinux/docker-remastering/raw/refs/heads/main/REFRACTA-ALL-TOOLS_DEB_FILES/live-boot_20221008~fsr1_all.deb
wget https://github.com/GlitchLinux/docker-remastering/raw/refs/heads/main/grub-efi-amd64-signed_1+2.06+13+deb12u1_amd64.deb
wget https://raw.githubusercontent.com/GlitchLinux/docker-remastering/refs/heads/main/ssh-file-transfer.sh

sudo dpkg --force-all -i live-boot_20221008~fsr1_all.deb live-boot-initramfs-tools_20221008~fsr1_all.deb live-config-refracta_0.0.5.deb refractasnapshot-base_10.2.12_all.deb grub-efi-amd64-signed_1+2.06+13+deb12u1_amd64.deb
sudo apt update && sudo apt install -f -y
sudo dpkg --configure -a 

sudo rm -f /etc/refractasnapshot.conf
sudo wget https://raw.githubusercontent.com/GlitchLinux/docker-remastering/refs/heads/main/refractasnapshot.conf
sudo mv refractasnapshot.conf /etc

sleep 10

sudo refractasnapshot

###########################################################################

echo "|==================================================================|"
echo "|    YOUR CUSTOM ISO HAVE BEEN CREATED AND SAVED SUCSESSFULLY      |"
echo "| -> SSH FILE TRANSFER WILL START SHORTLY, Ctrl+C TO SKIP IT NOW   |"  
echo "|   AND run manually LATER -> sudo bash /tmp/ssh-file-transfer.sh  |" 
echo "|==================================================================|"

###########################################################################

sleep 25

sudo bash /tmp/ssh-file-transfer.sh

### FIN ###
