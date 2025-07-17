#!/bin/bash
# usrmerge-fix.sh
# Fix broken usrmerge state on Debian 12 after upgrade

set -e

echo "[*] Starting usrmerge fix script..."

# 1. Remove safe duplicates in /bin, /sbin, /lib*
echo "[*] Removing safe duplicate files that also exist in /usr..."

CRITICAL_BINS=("sh" "bash" "dash")

for DIR in bin sbin lib lib32 lib64 libx32; do
  [ -d "/$DIR" ] || continue
  find "/$DIR" -type f -o -type l 2>/dev/null | while read -r FILE; do
    BASENAME=$(basename "$FILE")
    # Skip critical binaries
    if [[ " ${CRITICAL_BINS[*]} " == *" $BASENAME "* ]]; then
      continue
    fi
    USRFILE="/usr/$DIR/$BASENAME"
    if [ -e "$USRFILE" ]; then
      # Only remove if identical
      if cmp -s "$FILE" "$USRFILE"; then
        echo "  Removing duplicate: $FILE"
        sudo rm -f "$FILE"
      else
        echo "  Skipping different file: $FILE vs $USRFILE"
      fi
    fi
  done
done

# 2. Recreate essential symlinks in /bin and /sbin
echo "[*] Recreating essential /bin and /sbin symlinks..."

declare -A BIN_LINKS=(
  [/bin/sh]=/usr/bin/dash
  [/bin/bash]=/usr/bin/bash
  [/bin/dash]=/usr/bin/dash
  [/bin/cp]=/usr/bin/cp
  [/bin/mv]=/usr/bin/mv
  [/bin/rm]=/usr/bin/rm
  [/bin/ls]=/usr/bin/ls
  [/bin/ln]=/usr/bin/ln
  [/bin/mkdir]=/usr/bin/mkdir
  [/bin/rmdir]=/usr/bin/rmdir
  [/bin/awk]=/usr/bin/awk
)

declare -A SBIN_LINKS=(
  [/sbin/init]=/usr/lib/systemd/systemd
  [/sbin/reboot]=/usr/sbin/reboot
  [/sbin/poweroff]=/usr/sbin/poweroff
)

for link in "${!BIN_LINKS[@]}"; do
  target="${BIN_LINKS[$link]}"
  if [ ! -e "$link" ]; then
    echo "  Creating symlink: $link -> $target"
    sudo ln -s "$target" "$link"
  fi
done

for link in "${!SBIN_LINKS[@]}"; do
  target="${SBIN_LINKS[$link]}"
  if [ ! -e "$link" ]; then
    echo "  Creating symlink: $link -> $target"
    sudo ln -s "$target" "$link"
  fi
done

# 3. Run usrmerge conversion forcibly
echo "[*] Running usrmerge conversion (may take a moment)..."
sudo /usr/lib/usrmerge/convert-usrmerge --force

echo "[✔] usrmerge conversion complete!"

echo
echo "Now, run the following commands to finalize your system:"
echo "  sudo dpkg --configure -a"
echo "  sudo apt update && sudo apt upgrade"
echo
echo "You may want to reboot afterwards."

exit 0
