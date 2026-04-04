#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════╗
# ║           FolderVault  v2.0                   ║
# ║     gocryptfs-backed Directory Locker         ║
# ╚═══════════════════════════════════════════════╝

set -euo pipefail

# ── Colors ────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1;34m'; W='\033[1;37m'
DIM='\033[2m'; BOLD='\033[1m'; RST='\033[0m'

# ── Config ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CIPHER_DIR="$SCRIPT_DIR/.foldervault.cipher"   # encrypted blobs (always on disk)
PLAIN_DIR="$SCRIPT_DIR/foldervault"            # live mountpoint (only when unlocked)

# ── Helpers ───────────────────────────────────────
banner() {
    echo -e ""
    echo -e "${C}╔════════════════════════════════════╗${RST}"
    echo -e "${C}║  ${W}${BOLD}🔐 FolderVault${RST}  ${DIM}v2.0 gocryptfs${RST}${C}  ║${RST}"
    echo -e "${C}╚════════════════════════════════════╝${RST}"
    echo -e ""
}

die()    { echo -e "${R}✖  $*${RST}" >&2; exit 1; }
ok()     { echo -e "${G}✔  $*${RST}"; }
info()   { echo -e "${C}→  $*${RST}"; }
warn()   { echo -e "${Y}⚠  $*${RST}"; }
prompt() { echo -ne "${W}${BOLD}$*${RST} "; }

check_deps() {
    for cmd in gocryptfs fusermount; do
        command -v "$cmd" &>/dev/null \
            || die "'$cmd' not found. Install with: sudo apt install gocryptfs"
    done
}

read_pass() {
    local __var="$1" __prompt="${2:-Passphrase}"
    local __pass
    echo -ne "${W}${BOLD}${__prompt}:${RST} "
    read -rs __pass
    echo ""
    eval "$__var='$__pass'"
}

# ── Check if plain dir is currently mounted ───────
is_mounted() {
    mountpoint -q "$PLAIN_DIR" 2>/dev/null
}

# ── Lock: just unmount ────────────────────────────
do_lock() {
    info "Locking vault..."
    fusermount -u "$PLAIN_DIR" 2>/dev/null \
        || die "Failed to unmount — is the vault in use?"
    rmdir "$PLAIN_DIR" 2>/dev/null || true
    ok "Vault locked."
}

# ── Unlock: mount with passphrase ─────────────────
do_unlock() {
    local pass="$1"
    mkdir -p "$PLAIN_DIR"
    echo "$pass" | gocryptfs -passfile /dev/stdin "$CIPHER_DIR" "$PLAIN_DIR" 2>/dev/null \
        || { rmdir "$PLAIN_DIR" 2>/dev/null; return 1; }
}

# ── Init: create new encrypted vault ─────────────
do_init() {
    local pass="$1"
    mkdir -p "$CIPHER_DIR"
    echo "$pass" | gocryptfs -init -passfile /dev/stdin "$CIPHER_DIR" 2>/dev/null \
        || { rm -rf "$CIPHER_DIR"; die "Vault initialisation failed."; }
}

# ── Show vault contents ───────────────────────────
show_contents() {
    echo ""
    echo -e "${G}${BOLD}  Vault contents:${RST}"
    echo -e "${DIM}  ─────────────────────────────────${RST}"
    ls --color=always -lah "$PLAIN_DIR" 2>/dev/null | sed 's/^/  /'
    echo -e "${DIM}  ─────────────────────────────────${RST}"
    echo -e "${DIM}  Path: ${PLAIN_DIR}${RST}"
    echo ""
}

# ── Change passphrase ─────────────────────────────
change_passphrase() {
    local old_pass new_pass confirm
    read_pass old_pass "Current passphrase"
    read_pass new_pass "New passphrase"
    read_pass confirm  "Confirm new passphrase"
    [[ "$new_pass" == "$confirm" ]] || die "Passphrases do not match."
    [[ -n "$new_pass" ]]           || die "Passphrase cannot be empty."
    # gocryptfs -passwd: pipe old passphrase only; it prompts interactively for new
    # Use expect-free approach: write a temp askpass helper
    local tmp_old tmp_new
    tmp_old="$(mktemp)"
    tmp_new="$(mktemp)"
    echo "$old_pass" > "$tmp_old"
    echo "$new_pass" > "$tmp_new"
    gocryptfs -passwd \
        -extpass "cat $tmp_old" \
        -passfile "$tmp_new" \
        "$CIPHER_DIR" 2>/dev/null \
        || { rm -f "$tmp_old" "$tmp_new"; die "Passphrase change failed — wrong current passphrase?"; }
    rm -f "$tmp_old" "$tmp_new"
    ok "Passphrase updated."
}

# ── Settings menu ─────────────────────────────────
settings_menu() {
    echo ""
    echo -e "${B}${BOLD}  ┌─ Vault Settings ──────────────────┐${RST}"
    echo -e "${B}${BOLD}  │${RST}  ${W}P${RST}  — Change passphrase            ${B}${BOLD}│${RST}"
    echo -e "${B}${BOLD}  │${RST}  ${W}D${RST}  — Destroy vault (wipe all)     ${B}${BOLD}│${RST}"
    echo -e "${B}${BOLD}  │${RST}  ${W}B${RST}  — Back                         ${B}${BOLD}│${RST}"
    echo -e "${B}${BOLD}  └───────────────────────────────────┘${RST}"
    echo ""
    prompt "Choice:"
    read -r choice
    case "${choice^^}" in
        P)
            # Passphrase change requires vault to be locked first
            if is_mounted; then
                info "Locking vault before passphrase change..."
                do_lock
            fi
            change_passphrase
            ;;
        D)
            warn "This will PERMANENTLY destroy the vault and ALL contents!"
            prompt "Type 'DESTROY' to confirm:"
            read -r confirm
            if [[ "$confirm" == "DESTROY" ]]; then
                if is_mounted; then
                    info "Unmounting vault..."
                    fusermount -u "$PLAIN_DIR" 2>/dev/null || true
                    rmdir "$PLAIN_DIR" 2>/dev/null || true
                fi
                rm -rf "$CIPHER_DIR" "$PLAIN_DIR"
                ok "Vault destroyed."
            else
                info "Cancelled."
            fi
            ;;
        B|"") info "Back." ;;
        *)    warn "Unknown option." ;;
    esac
}

# ══════════════════════════════════════════════════
#  MAIN LOGIC
# ══════════════════════════════════════════════════
main() {
    check_deps
    banner

    local has_cipher=false
    [[ -d "$CIPHER_DIR" && -f "$CIPHER_DIR/gocryptfs.conf" ]] && has_cipher=true

    # ── CASE 1: No vault exists ───────────────────
    if ! $has_cipher; then
        prompt "Create a password-protected folder here? [Y/n]:"
        read -r yn
        [[ "${yn^^}" == "N" ]] && { info "Aborted."; exit 0; }
        echo ""
        local pass confirm
        read_pass pass    "Set passphrase"
        read_pass confirm "Confirm passphrase"
        [[ "$pass" == "$confirm" ]] || die "Passphrases do not match."
        [[ -n "$pass" ]]            || die "Passphrase cannot be empty."
        info "Initialising vault..."
        do_init "$pass"
        ok "Vault created."
        info "Mounting..."
        do_unlock "$pass" || die "Mount failed after init."
        ok "Vault mounted."
        show_contents
        echo -e "${DIM}  Add files to ${PLAIN_DIR}${RST}"
        echo -e "${DIM}  Run this script again to lock.${RST}"
        echo ""
        exit 0
    fi

    # ── CASE 2: Vault exists and is LOCKED ────────
    if ! is_mounted; then
        echo -e "  ${Y}${BOLD}🔒 Locked vault detected${RST}"
        echo -e "  ${DIM}${CIPHER_DIR}${RST}"
        echo ""
        local attempts=0 max_attempts=3
        while (( attempts < max_attempts )); do
            local pass
            read_pass pass "Passphrase"
            if do_unlock "$pass"; then
                ok "Vault unlocked."
                show_contents
                exit 0
            fi
            (( attempts++ ))
            local remaining=$(( max_attempts - attempts ))
            (( remaining > 0 )) \
                && warn "Wrong passphrase. ${remaining} attempt(s) remaining." \
                || die "Too many failed attempts."
        done
        exit 1
    fi

    # ── CASE 3: Vault is UNLOCKED (mounted) ───────
    echo -e "  ${G}${BOLD}🔓 Vault is unlocked and mounted${RST}"
    echo -e "  ${DIM}${PLAIN_DIR}${RST}"
    echo ""
    echo -e "  ${W}L${RST}  — Lock vault"
    echo -e "  ${W}Q${RST}  — Settings  ${DIM}(change passphrase / destroy)${RST}"
    echo -e "  ${W}N${RST}  — Nothing, exit"
    echo ""
    prompt "Choice [L/q/n]:"
    read -r choice
    case "${choice^^}" in
        Q)    settings_menu ;;
        N|"") info "Exited without locking." ;;
        L|*)  do_lock ;;
    esac
    exit 0
}

main "$@"
