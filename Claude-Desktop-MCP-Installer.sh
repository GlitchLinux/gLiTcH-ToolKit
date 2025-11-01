#!/usr/bin/env bash
# mount_and_run_mcp.sh
# Downloads MCP-container.img, sets up loop + LUKS, mounts to /tmp/MCP and runs MCP-autoinstaller.sh
# Usage: ./mount_and_run_mcp.sh
set -euo pipefail

IMG_URL="https://glitchlinux.wtf/claude-cloud/MCP-container.img"
WORKDIR="/tmp/MCP"
IMG_PATH="$WORKDIR/MCP-container.img"
MAPPER_NAME="mcpcrypt"
MAPPER_DEV="/dev/mapper/$MAPPER_NAME"

cleanup() {
  echo
  echo "Cleaning up..."
  # If mounted, try to unmount
  if mountpoint -q "$WORKDIR"; then
    echo " - unmounting $WORKDIR"
    sudo umount "$WORKDIR" || echo "   failed to unmount (maybe already unmounted)"
  fi

  # Close crypt device if open
  if [ -e "$MAPPER_DEV" ]; then
    echo " - closing LUKS mapper $MAPPER_NAME"
    sudo cryptsetup luksClose "$MAPPER_NAME" || echo "   failed to luksClose"
  fi

  # detach loop device if we set one
  if [ -n "${LOOP_DEVICE:-}" ]; then
    # If /dev/loopXpY partition nodes were used, losetup -d on $LOOP_DEVICE will free it
    if sudo losetup --list | grep -q "$LOOP_DEVICE"; then
      echo " - detaching loop device $LOOP_DEVICE"
      sudo losetup -d "$LOOP_DEVICE" || echo "   failed to detach loop"
    fi
  fi
}
trap cleanup EXIT INT TERM

# Check for required commands
need_cmd() {
  command -v "$1" >/dev/null 2>&1 || { echo "Need '$1' but it's not installed. Aborting."; exit 2; }
}

# Prefer curl, fallback to wget
if command -v curl >/dev/null 2>&1; then
  DOWNLOADER="curl -fLo"
elif command -v wget >/dev/null 2>&1; then
  DOWNLOADER="wget -O"
else
  echo "Install curl or wget and try again."
  exit 2
fi

need_cmd losetup
need_cmd cryptsetup
need_cmd mount
need_cmd sudo
need_cmd grep
need_cmd awk

echo "Preparing $WORKDIR ..."
sudo mkdir -p "$WORKDIR"
sudo chown "$(id -u):$(id -g)" "$WORKDIR"   # make sure current user can write there

echo "Downloading image to $IMG_PATH ..."
# download
if [[ "$DOWNLOADER" == curl* ]]; then
  curl -fLo "$IMG_PATH" "$IMG_URL"
else
  wget -O "$IMG_PATH" "$IMG_URL"
fi

if [[ ! -f "$IMG_PATH" ]]; then
  echo "Download failed or file missing: $IMG_PATH"
  exit 3
fi

# Attach loop device with partition scanning (-P)
echo "Attaching loop device..."
LOOP_DEVICE=$(sudo losetup --find --show -P "$IMG_PATH")
echo "Loop device: $LOOP_DEVICE"

# Determine candidate device for LUKS
CANDIDATE=""
if [[ -e "${LOOP_DEVICE}p1" ]]; then
  CANDIDATE="${LOOP_DEVICE}p1"
  echo "Found partition: $CANDIDATE (trying this first)"
else
  # For some older losetup versions partition naming might be different; check /dev/loopXp1 too
  if ls "${LOOP_DEVICE}"* 1>/dev/null 2>&1; then
    # fallback: try a numeric partition suffix if present
    # otherwise use loop device itself
    echo "No partition node '${LOOP_DEVICE}p1' found; will try the whole loop device: $LOOP_DEVICE"
    CANDIDATE="$LOOP_DEVICE"
  else
    CANDIDATE="$LOOP_DEVICE"
  fi
fi

# Try to open LUKS on candidate; if fails, and candidate was a partition, try whole loop device
open_luks() {
  local dev="$1"
  echo "Attempting to open LUKS on $dev"
  # cryptsetup will prompt for passphrase interactively
  if sudo cryptsetup luksOpen "$dev" "$MAPPER_NAME"; then
    echo "LUKS opened as $MAPPER_DEV"
    return 0
  else
    echo "Failed to open LUKS on $dev"
    return 1
  fi
}

if ! open_luks "$CANDIDATE"; then
  # If we tried partition, try loop device
  if [[ "$CANDIDATE" != "$LOOP_DEVICE" ]]; then
    echo "Retrying on the whole loop device $LOOP_DEVICE ..."
    if ! open_luks "$LOOP_DEVICE"; then
      echo "Unable to open LUKS on either partition or loop device. Exiting."
      exit 4
    fi
  else
    echo "Unable to open LUKS on $LOOP_DEVICE. Exiting."
    exit 4
  fi
fi

# Wait a moment for the mapper device
sleep 0.5

# Create mountpoint dir (owned by current user)
mkdir -p "$WORKDIR"
# Mount the decrypted mapper device
echo "Mounting $MAPPER_DEV to $WORKDIR ..."
sudo mount "$MAPPER_DEV" "$WORKDIR"

# Verify MCP-autoinstaller.sh exists
if [[ ! -f "$WORKDIR/MCP-autoinstaller.sh" ]]; then
  echo "Warning: $WORKDIR/MCP-autoinstaller.sh not found inside the mounted volume."
  echo "Listing $WORKDIR:"
  ls -lah "$WORKDIR" || true
  echo "You can exit (Ctrl+C) or still attempt to run (will likely fail)."
  read -p "Continue and attempt to run MCP-autoinstaller.sh anyway? [y/N] " -r
  if [[ ! "$REPLY" =~ ^[Yy]$ ]]; then
    echo "Exiting without running installer."
    exit 0
  fi
fi

# Run the installer (with sudo as requested)
echo "Changing directory to $WORKDIR and running 'sudo bash MCP-autoinstaller.sh' ..."
cd "$WORKDIR"
sudo bash ./MCP-autoinstaller.sh

echo "Installer finished. Leaving volume mounted. Script will now cleanup and unmount."
# cleanup will be invoked by trap on exit
exit 0
