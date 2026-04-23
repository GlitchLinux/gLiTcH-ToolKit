#!/usr/bin/env bash
# dl-and-launch-remasterglitch.sh
# Download, chmod, launch RemasterGlitch AppImage. Detach fully and close parent terminal.

set -euo pipefail

URL="https://github.com/GlitchLinux/RemasterGlitch/releases/download/RemasterGlitch-x86_64.AppImage/RemasterGlitch-x86_64.AppImage"
DEST="/tmp/RemasterGlitch-x86_64.AppImage"
FORCE="${1:-}"

# ── Download (resume-capable, skip if already present) ──
if [[ "$FORCE" == "--force" || "$FORCE" == "-f" ]]; then
    rm -f "$DEST"
fi

if [[ -s "$DEST" ]]; then
    echo "Already have $DEST ($(du -h "$DEST" | cut -f1)), skipping download."
else
    echo "Downloading RemasterGlitch AppImage..."
    if command -v curl >/dev/null; then
        curl -L --fail --progress-bar -C - -o "$DEST" "$URL"
    elif command -v wget >/dev/null; then
        wget -c --show-progress -O "$DEST" "$URL"
    else
        echo "ERROR: need curl or wget" >&2
        exit 1
    fi
fi

chmod +x "$DEST"

# ── Resolve parent terminal PID before we detach ──
# Script's parent is the shell; shell's parent is usually the terminal emulator.
SHELL_PID="$PPID"
TERM_PID="$(ps -o ppid= -p "$SHELL_PID" 2>/dev/null | tr -d ' ' || true)"

# ── Launch fully detached ──
echo "Launching $DEST..."
setsid nohup "$DEST" </dev/null >/dev/null 2>&1 &
disown 2>/dev/null || true

# Give the child a beat to actually fork/exec before we kill the terminal
sleep 1

# ── Kill the parent terminal ──
# Only kill it if it looks like a terminal emulator (not e.g. systemd, init, sshd, cron).
if [[ -n "$TERM_PID" && "$TERM_PID" != "1" && "$TERM_PID" != "0" ]]; then
    TERM_NAME="$(ps -o comm= -p "$TERM_PID" 2>/dev/null || true)"
    case "$TERM_NAME" in
        gnome-terminal*|konsole*|xterm*|xfce4-terminal*|terminator*|tilix*|alacritty*|kitty*|mate-terminal*|lxterminal*|urxvt*|st*|qterminal*|deepin-terminal*|ptyxis*|wezterm*|foot*|ghostty*)
            kill -HUP "$TERM_PID" 2>/dev/null || kill "$TERM_PID" 2>/dev/null || true
            ;;
        *)
            # Not a recognised terminal — don't touch it (probably ssh, tmux, cron, IDE).
            ;;
    esac
fi

exit 0
