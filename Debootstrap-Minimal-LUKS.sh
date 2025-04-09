#!/bin/bash

# Check if running as root
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root" >&2
    exit 1
fi

# Prompt user for disk
read -p "Enter the disk to install to (e.g., /dev/sdx): " DISK

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

# Ask if user wants encryption
read -p "Would you like to encrypt the installation? [y/N]: " ENCRYPT_CHOICE
ENCRYPT_CHOICE=${ENCRYPT_CHOICE,,} # Convert to lowercase

USE_ENCRYPTION=false
if [[ "$ENCRYPT_CHOICE" == "y" || "$ENCRYPT_CHOICE" == "yes" ]]; then
    USE_ENCRYPTION=true
    
    # Prompt for encryption passphrase
    read -s -p "Enter encryption passphrase: " ENCRYPT_PASS
    echo
    read -s -p "Confirm encryption passphrase: " ENCRYPT_PASS_CONFIRM
    echo

    if [ "$ENCRYPT_PASS" != "$ENCRYPT_PASS_CONFIRM" ]; then
        echo "Error: Passphrases do not match" >&2
        exit 1
    fi
    
    # Check if cryptsetup is installed
    if ! command -v cryptsetup >/dev/null; then
        echo "Installing cryptsetup..."
        apt-get update
        apt-get install -y cryptsetup
    fi
fi

# Partition and format the disk
case $SCHEME in
    1) # MBR
        echo "Creating MBR partition scheme..."
        parted -s "$DISK" mklabel msdos
        
        if [ "$USE_ENCRYPTION" = true ]; then
            # Create a small boot partition and an encrypted partition
            parted -s "$DISK" mkpart primary ext4 1MiB 513MiB
            parted -s "$DISK" mkpart primary ext4 513MiB 100%
            partprobe "$DISK"
            BOOT_PART="${PART_PREFIX}1"
            CRYPT_PART="${PART_PREFIX}2"
            echo "Waiting for partitions to appear..."
            until [ -b "$BOOT_PART" ] && [ -b "$CRYPT_PART" ]; do sleep 1; done
            mkfs.ext4 -F -L "BOOT" "$BOOT_PART"
        else
            # Just one partition for the root filesystem
            parted -s "$DISK" mkpart primary ext4 1MiB 100%
            partprobe "$DISK"
            ROOT_PART="${PART_PREFIX}1"
            echo "Waiting for partition to appear..."
            until [ -b "$ROOT_PART" ]; do sleep 1; done
            mkfs.ext4 -F -L "ROOT" "$ROOT_PART"
        fi
        ;;
        
    2) # GPT
        echo "Creating GPT partition scheme..."
        parted -s "$DISK" mklabel gpt
        
        if [ "$USE_ENCRYPTION" = true ]; then
            # EFI partition and encrypted partition
            parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
            parted -s "$DISK" set 1 boot on
            parted -s "$DISK" set 1 esp on  # Set ESP flag explicitly
            parted -s "$DISK" mkpart primary ext4 513MiB 100%
            partprobe "$DISK"
            EFI_PART="${PART_PREFIX}1"
            CRYPT_PART="${PART_PREFIX}2"
            echo "Waiting for partitions to appear..."
            until [ -b "$EFI_PART" ] && [ -b "$CRYPT_PART" ]; do sleep 1; done
            mkfs.fat -F32 -n "EFI" "$EFI_PART"
        else
            # EFI partition and regular root partition
            parted -s "$DISK" mkpart ESP fat32 1MiB 513MiB
            parted -s "$DISK" set 1 boot on
            parted -s "$DISK" set 1 esp on  # Set ESP flag explicitly
            parted -s "$DISK" mkpart primary ext4 513MiB 100%
            partprobe "$DISK"
            EFI_PART="${PART_PREFIX}1"
            ROOT_PART="${PART_PREFIX}2"
            echo "Waiting for partitions to appear..."
            until [ -b "$EFI_PART" ] && [ -b "$ROOT_PART" ]; do sleep 1; done
            mkfs.fat -F32 -n "EFI" "$EFI_PART"
            mkfs.ext4 -F -L "ROOT" "$ROOT_PART"
        fi
        ;;
        
    *)
        echo "Invalid selection" >&2
        exit 1
        ;;
esac

# Set up encryption if requested
if [ "$USE_ENCRYPTION" = true ]; then
    echo "Setting up LUKS encryption..."
    echo -n "$ENCRYPT_PASS" | cryptsetup luksFormat --pbkdf pbkdf2 --iter-time 2000 "$CRYPT_PART"
    echo -n "$ENCRYPT_PASS" | cryptsetup luksOpen "$CRYPT_PART" cryptroot

    # Create file system on the decrypted device
    echo "Creating file system on encrypted partition..."
    mkfs.ext4 -F -L "ROOT" /dev/mapper/cryptroot
    ROOT_DEVICE="/dev/mapper/cryptroot"
else
    ROOT_DEVICE="$ROOT_PART"
fi

# Mount the root partition
MOUNT_POINT="/mnt/debian"
mkdir -p "$MOUNT_POINT"
echo "Mounting root filesystem to $MOUNT_POINT"
mount -o rw,relatime,errors=remount-ro "$ROOT_DEVICE" "$MOUNT_POINT" || { echo "Failed to mount root partition"; exit 1; }

# Mount boot/EFI partition if needed
if [ "$USE_ENCRYPTION" = true ] && [ "$SCHEME" -eq 1 ]; then
    # Mount separate boot partition for encrypted MBR setup
    mkdir -p "${MOUNT_POINT}/boot"
    echo "Mounting $BOOT_PART to ${MOUNT_POINT}/boot"
    mount "$BOOT_PART" "${MOUNT_POINT}/boot" || { echo "Failed to mount boot partition"; exit 1; }
fi

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
if [ "$USE_ENCRYPTION" = true ]; then
    # Include cryptsetup packages for encrypted setup
    debootstrap --include=locales,linux-image-amd64,cryptsetup-initramfs bookworm "$MOUNT_POINT" http://deb.debian.org/debian || { echo "Initial debootstrap failed"; exit 1; }
else
    # Regular installation without cryptsetup
    debootstrap --include=locales,linux-image-amd64 bookworm "$MOUNT_POINT" http://deb.debian.org/debian || { echo "Initial debootstrap failed"; exit 1; }
fi

# Prepare chroot environment
mount --bind /dev "${MOUNT_POINT}/dev"
mount --bind /dev/pts "${MOUNT_POINT}/dev/pts"
mount --bind /proc "${MOUNT_POINT}/proc"
mount --bind /sys "${MOUNT_POINT}/sys"
mount --bind /run "${MOUNT_POINT}/run"  # Important for systemd

# Generate crypttab if using encryption
if [ "$USE_ENCRYPTION" = true ]; then
    CRYPT_UUID=$(blkid -s UUID -o value "$CRYPT_PART")
    cat > "${MOUNT_POINT}/etc/crypttab" <<EOF
# <target name> <source device>         <key file>      <options>
cryptroot UUID=${CRYPT_UUID} none luks,discard
EOF
fi

# Generate fstab with correct UUIDs
if [ "$USE_ENCRYPTION" = true ]; then
    ROOT_UUID=$(blkid -s UUID -o value /dev/mapper/cryptroot)
    cat > "${MOUNT_POINT}/etc/fstab" <<EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
/dev/mapper/cryptroot /               ext4    rw,relatime,errors=remount-ro 0       1
EOF

    if [ "$SCHEME" -eq 1 ]; then
        BOOT_UUID=$(blkid -s UUID -o value "$BOOT_PART")
        cat >> "${MOUNT_POINT}/etc/fstab" <<EOF
UUID=${BOOT_UUID}  /boot           ext4    defaults        0       2
EOF
    fi
else
    ROOT_UUID=$(blkid -s UUID -o value "$ROOT_PART")
    cat > "${MOUNT_POINT}/etc/fstab" <<EOF
# <file system> <mount point>   <type>  <options>       <dump>  <pass>
UUID=${ROOT_UUID} /               ext4    rw,relatime,errors=remount-ro 0       1
EOF
fi

# Add EFI partition to fstab if using GPT
if [ "$SCHEME" -eq 2 ]; then
    EFI_UUID=$(blkid -s UUID -o value "$EFI_PART")
    cat >> "${MOUNT_POINT}/etc/fstab" <<EOF
UUID=${EFI_UUID}  /boot/efi       vfat    umask=0077      0       2
EOF
fi

# Set variables for use in chroot
CRYPT_UUID_FOR_CHROOT=""
if [ "$USE_ENCRYPTION" = true ]; then
    CRYPT_UUID_FOR_CHROOT="$CRYPT_UUID"
fi

USE_ENCRYPTION_FOR_CHROOT="$USE_ENCRYPTION"
SCHEME_FOR_CHROOT="$SCHEME"
DISK_FOR_CHROOT="$DISK"

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
deb http://deb.debian.org/debian bookworm main contrib non-free-firmware non-free
deb http://deb.debian.org/debian bookworm-updates main contrib non-free-firmware non-free
deb http://security.debian.org/debian-security bookworm-security main contrib non-free-firmware non-free
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

# Install encryption packages if using encryption
if [ "$USE_ENCRYPTION_FOR_CHROOT" = true ]; then
    apt-get install -y --no-install-recommends \
        cryptsetup \
        cryptsetup-initramfs \
        cryptsetup-run \
        cryptsetup-bin \
        keyutils
fi

# Ensure getty services are properly configured
for i in {1..6}; do
    systemctl enable getty@tty\${i}.service
done

# Install GRUB packages based on scheme
if [ "$SCHEME_FOR_CHROOT" -eq 1 ]; then
    apt-get install -y --no-install-recommends grub-pc
else
    # For EFI, install both grub-efi and efibootmgr with full recommended packages
    apt-get install -y grub-efi-amd64 efibootmgr
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

# Configure encryption in GRUB if using encryption
if [ "$USE_ENCRYPTION_FOR_CHROOT" = true ]; then
    sed -i 's/GRUB_CMDLINE_LINUX_DEFAULT=".*"/GRUB_CMDLINE_LINUX_DEFAULT="quiet"/' /etc/default/grub
    sed -i 's/GRUB_CMDLINE_LINUX=""/GRUB_CMDLINE_LINUX="cryptdevice=UUID='${CRYPT_UUID_FOR_CHROOT}':cryptroot root=\/dev\/mapper\/cryptroot"/' /etc/default/grub
    
    # Configure encryption in initramfs
    echo "CRYPTSETUP=y" >> /etc/cryptsetup-initramfs/conf-hook
fi

# Configure GRUB
if [ "$SCHEME_FOR_CHROOT" -eq 1 ]; then
    grub-install "$DISK_FOR_CHROOT"
else
    # For EFI, be more explicit with the installation
    apt-get install -y --no-install-recommends dosfstools
    
    # Make sure EFI directory exists and has correct permissions
    mkdir -p /boot/efi/EFI/debian
    mkdir -p /boot/efi/EFI/BOOT
    
    #set crypto disk enable 
    echo "GRUB_ENABLE_CRYPTODISK=y" >> /etc/default/grub

    # Install GRUB for EFI
    grub-install --target=x86_64-efi --efi-directory=/boot/efi --bootloader-id=debian --recheck
    
    # Create fallback boot entries
    cp /boot/efi/EFI/debian/grubx64.efi /boot/efi/EFI/BOOT/bootx64.efi || true
fi

# Generate GRUB config
update-grub

# Generate initramfs
update-initramfs -u -k all

#download glitch toolkit to new system
cd /root
wget --no-check-certificate https://glitchlinux.wtf/apps
chmod +x apps

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

if [ "$USE_ENCRYPTION" = true ]; then
    echo "IMPORTANT: Your system is encrypted. You will be prompted for your encryption passphrase during boot."
fi
