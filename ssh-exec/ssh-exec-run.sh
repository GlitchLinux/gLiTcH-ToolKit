#!/usr/bin/env bash
# ssh-exec-run.sh - install ssh-exec if missing, then run it
# All arguments are passed through to ssh-exec.
#
#   ./ssh-exec-run.sh                                  # interactive
#   ./ssh-exec-run.sh contabo 'sudo systemctl restart apache2'
#   ./ssh-exec-run.sh --reinstall                      # force fresh install

SRC_URL="https://raw.githubusercontent.com/GlitchLinux/gLiTcH-ToolKit/main/ssh-exec/ssh-exec"
DEST="/usr/local/bin/ssh-exec"
TMP="/tmp/ssh-exec.$$"

install_ssh_exec() {
  echo "[Installing ssh-exec to $DEST]"
  for pkg in ssh:openssh-client sshpass:sshpass wget:wget; do
    command -v "${pkg%%:*}" >/dev/null || sudo apt-get install -y "${pkg##*:}" || {
      echo "Failed to install ${pkg##*:}"; exit 1; }
  done
  wget -q -O "$TMP" "$SRC_URL" || { echo "Download failed: $SRC_URL"; rm -f "$TMP"; exit 1; }
  bash -n "$TMP" || { echo "Downloaded file failed syntax check"; rm -f "$TMP"; exit 1; }
  sudo chmod +x "$TMP" && sudo mv "$TMP" "$DEST" || { echo "Install failed"; exit 1; }
  echo "Installed ✓"
  echo "Tip: run 'ssh-exec --setup glitchserver' and 'ssh-exec --setup contabo' once for key auth"
  echo
}

if [ "$1" = "--reinstall" ]; then
  shift
  install_ssh_exec
elif ! command -v ssh-exec >/dev/null; then
  install_ssh_exec
fi

exec ssh-exec "$@"
