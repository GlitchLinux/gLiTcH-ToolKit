#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Prompt user for disk
read -p "Enter the disk to install to (e.g., /dev/sdd): " DISK

# Verify the disk exists
if [ ! -b "$DISK" ]; then
    echo "Error: Disk $DISK does not exist" >&2
    exit 1
fi

# Determine partition naming scheme
if [[ "$DISK" =~ /dev/loop ]] || [[ "$DISK" =~ /dev/nvme ]]; then
    PART_PREFIX="${DISK}p"
else
    PART_PREFIX="${DISK}"
fi

# Prompt for partition scheme
read -p "Partition scheme: (1) MBR or (2) GPT? [1/2]: " SCHEME

# Partition and format the disk
case $SCHEME in
    1)
        echo "Creating MBR partition scheme..."
        parted -s "$DISK" mklabel msdos
        parted -s "$DISK" mkpart primary ext4 1MiB 100%
        partprobe "$DISK"
        ROOT_PART="${PART_PREFIX}1"
        echo "Waiting for partition to appear..."
        until [ -b "$ROOT_PART" ]; do sleep 1; done
        mkfs.ext4 -F -L "ROOT" "$ROOT_PART"
        ;;
    2)
        echo "Creating GPT partition scheme..."
        parted -s "$DISK" mklabel gpt
        parted -s "$DISK" mkpart ESP fat32 1MiB 49MiB
        parted -s "$DISK" set 1 boot on
        parted -s "$DISK" mkpart primary ext4 49MiB 100%
        partprobe "$DISK"
        EFI_PART="${PART_PREFIX}1"
        ROOT_PART="${PART_PREFIX}2"
        echo "Waiting for partitions to appear..."
        until [ -b "$EFI_PART" ] && [ -b "$ROOT_PART" ]; do sleep 1; done
        mkfs.fat -F32 -n "EFI" "$EFI_PART"
        mkfs.ext4 -F -L "ROOT" "$ROOT_PART"
        ;;
    *)
        echo "Invalid selection" >&2
        exit 1
        ;;
esac

# Mount the root partition
MOUNT_POINT="/mnt/debian"
mkdir -p "$MOUNT_POINT"
echo "Mounting $ROOT_PART to $MOUNT_POINT"
mount -o rw,relatime,errors=remount-ro "$ROOT_PART" "$MOUNT_POINT" || { echo "Failed to mount root partition"; exit 1; }

# Mount EFI partition if GPT
if [ "$SCHEME" -eq 2 ]; then
    mkdir -p "${MOUNT_POINT}/boot/efi"
    echo "Mounting $EFI_PART to ${MOUNT_POINT}/boot/efi"
    mount "$EFI_PART" "${MOUNT_POINT}/boot/efi" || { echo "Failed to mount EFI partition"; exit 1; }
fi

# Install debootstrap if not installed
if ! command -v debootstrap >/dev/null; then
    echo "Installing debootstrap..."
    apt-get update
    apt-get install -y debootstrap
fi

# Run debootstrap with minimal packages first
echo "Starting minimal debootstrap installation of Debian Bookworm..."
debootstrap --include=locales,linux-image-amd64 bookworm "$MOUNT_POINT" http://deb.debian.org/debian || { echo "Initial debootstrap failed"; exit 1; }

# Prepare chroot environment
mount --bind /dev "${MOUNT_POINT}/dev"
mount --bind /dev/pts "${MOUNT_POINT}/dev/pts"
mount --bind /proc "${MOUNT_POINT}/proc"
mount --bind /sys "${MOUNT_POINT}/sys"
mount --bind /run "${MOUNT_POINT}/run"  # Important for systemd

# Generate fstab with correct UUIDs to prevent boot issues
ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
cat > "${MOUNT_POINT}/etc/fstab" <<EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=${ROOT_UUID} /               ext4    rw,relatime,errors=remount-ro 0       1
EOF

if [ "$SCHEME" -eq 2 ]; then
    EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
    cat >> "${MOUNT_POINT}/etc/fstab" <<EOF
UUID=${EFI_UUID}  /boot/efi       vfat    umask=0077      0       2
EOF
fi

# Chroot and configure system
echo "Chrooting into new system for configuration..."
chroot "$MOUNT_POINT" /bin/bash <<EOF
# Set up basic system
echo "en_US.UTF-8 UTF-8" > /etc/locale.gen
locale-gen
echo "LANG=en_US.UTF-8" > /etc/locale.conf
ln -sf /usr/share/zoneinfo/UTC /etc/localtime

# Set root password
echo "root:root" | chpasswd

# Configure hostname
echo "gLiTcH" > /etc/hostname

# Configure hosts file
cat > /etc/hosts <<HOSTS
127.0.0.1   localhost
127.0.1.1   gLiTcH

# The following lines are desirable for IPv6 capable hosts
::1     localhost ip6-localhost ip6-loopback
ff02::1 ip6-allnodes
ff02::2 ip6-allrouters
HOSTS

# Configure apt sources
cat > /etc/apt/sources.list <<SOURCES
deb http://deb.debian.org/debian bookworm main contrib non-free
deb http://deb.debian.org/debian bookworm-updates main contrib non-free
deb http://security.debian.org/debian-security bookworm-security main contrib non-free
SOURCES

# Update and install packages in stages
apt-get update

# Install essential packages first
apt-get install -y --no-install-recommends \
    sudo \
    systemd \
    systemd-sysv \
    dbus \
    initramfs-tools \
    console-setup \
    keyboard-configuration \
    kbd \
    getty \
    locales \
    ca-certificates \
    bash \
    dash \
    login \
    util-linux \
    systemd-timesyncd \
    udev \
    procps \
    sysvinit-utils \
    lsb-base \
    libpam-systemd \
    libsystemd0 \
    libudev1

# Ensure getty services are properly configured
for i in {1..6}; do
    systemctl enable getty@tty${i}.service
done

# Install GRUB packages based on scheme
if [ "$SCHEME" -eq 1 ]; then
    apt-get install -y --no-install-recommends grub-pc
else
    apt-get install -y --no-install-recommends grub-efi-amd64 efibootmgr
fi

# Install networking packages
apt-get install -y --no-install-recommends \
    ifupdown \
    netbase \
    isc-dhcp-client \
    network-manager \
    iproute2 \
    iputils-ping \
    wget \
    git \
    sudo \
    curl \
    tree \
    openssh-server \
    ca-certificates

# Set default target
systemctl set-default multi-user.target

# Configure GRUB
if [ "$SCHEME" -eq 1 ]; then
    grub-install "$DISK"
else
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=Debian --recheck
    mkdir -p /boot/efi/EFI/BOOT
    cp /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/BOOT/bootx64.efi || true
fi
update-grub

# Generate initramfs
update-initramfs -u

#download glitch toolkit to new system
cd /etc
wget --no-check-certificate https://glitchlinux.wtf/apps
chmod +x apps

#alias set for apps
echo 'alias apps="sudo bash /etc/apps"' >> /etc/bash.bashrc

# Enable essential services
systemctl enable getty@tty1.service
systemctl enable NetworkManager.service
systemctl enable systemd-timesyncd.service
systemctl enable systemd-udevd.service

# Configure console
cat > /etc/default/console-setup <<CONF
ACTIVE_CONSOLES="/dev/tty[1-6]"
CHARMAP="UTF-8"
CODESET="guess"
FONTFACE="Fixed"
FONTSIZE="8x16"
VIDEOMODE=
CONF

# Ensure /etc/shells exists
cat > /etc/shells <<SHELLS
/bin/sh
/bin/bash
/usr/bin/bash
SHELLS

# Clean up
apt-get clean
rm -rf /var/lib/apt/lists/*
EOF

# Clean up
umount -Rl "$MOUNT_POINT"
sync

echo "Installation complete! You can now reboot into your new Debian system."
echo "Root password is set to 'root'"
