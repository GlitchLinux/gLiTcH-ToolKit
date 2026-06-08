#!/usr/bin/env bash
# ╔═══════════════════════════════════════════════════════╗
# ║              FolderVault  v3.0                        ║
# ║       gocryptfs v2 - Zero-sudo Directory Locker       ║
# ╠═══════════════════════════════════════════════════════╣
# ║  - No sudo required for any operation                 ║
# ║  - Vault owner gets full rwx control                  ║
# ║  - Root/other users cannot see decrypted content      ║
# ║  - Works on any user-accessible or root-mounted disk  ║
# ║  - Passphrase set on first run, changeable later      ║
# ╚═══════════════════════════════════════════════════════╝

set -euo pipefail

# ── Version ───────────────────────────────────────
VERSION="3.0"

# ── Colors ────────────────────────────────────────
R='\033[0;31m'; G='\033[0;32m'; Y='\033[1;33m'
C='\033[0;36m'; B='\033[1;34m'; W='\033[1;37m'
DIM='\033[2m'; BOLD='\033[1m'; RST='\033[0m'

# ── Caller identity (never root) ─────────────────
VAULT_UID="$(id -u)"
VAULT_GID="$(id -g)"
VAULT_USER="$(id -un)"

# ── Config ────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
CIPHER_DIR="$SCRIPT_DIR/.foldervault.cipher"
PLAIN_DIR="$SCRIPT_DIR/foldervault"
OWNER_FILE="$SCRIPT_DIR/.foldervault.owner"

# ── Helpers ───────────────────────────────────────
banner() {
    echo ""
    echo -e "${C}╔═════════════════════════════════════════╗${RST}"
    echo -e "${C}║   ${W}${BOLD}FolderVault${RST}${DIM} v${VERSION}  gocryptfs v2${RST}        ${C}║${RST}"
    echo -e "${C}║   ${DIM}zero-sudo encrypted directory locker${RST}  ${C}║${RST}"
    echo -e "${C}╚═════════════════════════════════════════╝${RST}"
    echo ""
}

die()    { echo -e "${R}  ✖  $*${RST}" >&2; exit 1; }
ok()     { echo -e "${G}  ✔  $*${RST}"; }
info()   { echo -e "${C}  ->  $*${RST}"; }
warn()   { echo -e "${Y}  ⚠  $*${RST}"; }
prompt() { echo -ne "${W}${BOLD}  $*${RST} "; }

# ── Secure passphrase reader ─────────────────────
# Uses printf + read to avoid eval injection issues
read_pass() {
    local -n __ref="$1"
    local __prompt="${2:-Passphrase}"
    echo -ne "${W}${BOLD}  ${__prompt}: ${RST}"
    IFS= read -rs __ref
    echo ""
}

# ── Dependency check ──────────────────────────────
check_deps() {
    local missing=()
    for cmd in gocryptfs fusermount; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    if (( ${#missing[@]} > 0 )); then
        die "Missing: ${missing[*]}
      Install with: sudo apt install gocryptfs fuse3
      (one-time setup, then never need sudo again)"
    fi

    # Verify gocryptfs v2+
    local gcver
    gcver="$(gocryptfs -version 2>/dev/null | grep -oP '\d+\.\d+' | head -1)" || true
    local major="${gcver%%.*}"
    if [[ -n "$major" ]] && (( major < 2 )); then
        warn "gocryptfs ${gcver} detected - v2.0+ recommended for best security"
    fi
}

# ── Refuse to run as root ─────────────────────────
refuse_root() {
    if (( VAULT_UID == 0 )); then
        die "Do NOT run FolderVault as root/sudo.
      The whole point is user-level encryption without privilege escalation.
      Run as your normal user: ./foldervault.sh"
    fi
}

# ── Check directory writability without sudo ──────
check_writability() {
    local test_dir="$SCRIPT_DIR"
    if [[ ! -w "$test_dir" ]]; then
        die "Cannot write to ${test_dir}
      The parent directory must be writable by your user (${VAULT_USER}).
      Fix:  sudo chown ${VAULT_USER}: ${test_dir}
        or: sudo chmod o+rwx ${test_dir}
      (this is a one-time fix for root-mounted partitions)"
    fi
}

# ── Owner tracking ────────────────────────────────
save_owner() {
    echo "${VAULT_UID}:${VAULT_GID}:${VAULT_USER}" > "$OWNER_FILE"
    chmod 600 "$OWNER_FILE"
}

verify_owner() {
    if [[ -f "$OWNER_FILE" ]]; then
        local stored_uid stored_gid stored_user
        IFS=':' read -r stored_uid stored_gid stored_user < "$OWNER_FILE"
        if [[ "$stored_uid" != "$VAULT_UID" ]]; then
            die "Vault owned by '${stored_user}' (uid ${stored_uid}).
      You are '${VAULT_USER}' (uid ${VAULT_UID}).
      Only the vault owner can access it."
        fi
    fi
}

# ── Check if mounted ─────────────────────────────
is_mounted() {
    mountpoint -q "$PLAIN_DIR" 2>/dev/null
}

# ── Init: create new encrypted vault ─────────────
do_init() {
    local pass="$1"
    local init_err

    # Create cipher dir owned by the calling user
    mkdir -p "$CIPHER_DIR"
    chmod 700 "$CIPHER_DIR"

    # Init gocryptfs - capture output for master key display
    init_err="$(echo "$pass" | gocryptfs -init \
        -passfile /dev/stdin \
        "$CIPHER_DIR" 2>&1)" \
        || { rm -rf "$CIPHER_DIR"; die "Vault initialisation failed: ${init_err}"; }

    # Extract and display master key from init output
    local master_key=""
    master_key="$(echo "$init_err" | grep -A2 "Your master key" | tail -2 | tr -d ' ')" || true
    if [[ -n "$master_key" ]]; then
        echo ""
        echo -e "${Y}${BOLD}  MASTER KEY (write this down and store safely):${RST}"
        echo -e "${DIM}  ─────────────────────────────────────${RST}"
        echo -e "  ${W}${master_key}${RST}"
        echo -e "${DIM}  ─────────────────────────────────────${RST}"
        echo -e "${DIM}  This is your ONLY recovery option if you forget the passphrase.${RST}"
        echo -e "${DIM}  This message will not be shown again.${RST}"
        echo ""
    fi

    # Lock down cipher dir
    chmod 700 "$CIPHER_DIR"

    # Record vault ownership
    save_owner
}

# ── Unlock: mount with passphrase ─────────────────
# FUSE mounts already show files owned by the mounting user (kernel behaviour).
# -owner_only is gocryptfs default: only the mounting UID can access the mount.
# We do NOT use -force_owner because it implicitly enables -allow_other,
# which requires 'user_allow_other' in /etc/fuse.conf (needs root to set).
#
# Result: normal user mounts, owns everything, root/others see nothing.
do_unlock() {
    local pass="$1"
    local mount_err

    mkdir -p "$PLAIN_DIR"
    chmod 700 "$PLAIN_DIR"

    # Mount with minimal safe flags - no -force_owner, no -allow_other
    mount_err="$(echo "$pass" | gocryptfs \
        -passfile /dev/stdin \
        -nosuid \
        -nodev \
        -quiet \
        "$CIPHER_DIR" "$PLAIN_DIR" 2>&1)" \
        || {
            rmdir "$PLAIN_DIR" 2>/dev/null || true
            # Check for specific error conditions
            if [[ "$mount_err" == *"allow_other"* ]]; then
                warn "FUSE allow_other issue detected (should not happen without -force_owner)"
                warn "Error: ${mount_err}"
            elif [[ "$mount_err" == *"Password"* || "$mount_err" == *"password"* ]]; then
                : # Wrong password - let caller handle silently
            elif [[ -n "$mount_err" ]]; then
                warn "Mount error: ${mount_err}"
            fi
            return 1
        }

    # Verify the mount actually works for this user
    if ! ls "$PLAIN_DIR" &>/dev/null; then
        fusermount -u "$PLAIN_DIR" 2>/dev/null || true
        rmdir "$PLAIN_DIR" 2>/dev/null || true
        warn "Mount succeeded but directory not accessible"
        return 1
    fi

    return 0
}

# ── Lock: unmount ─────────────────────────────────
do_lock() {
    info "Locking vault..."

    # Try graceful unmount first, then lazy if files are open
    if fusermount -u "$PLAIN_DIR" 2>/dev/null; then
        rmdir "$PLAIN_DIR" 2>/dev/null || true
        ok "Vault locked."
    elif fusermount -uz "$PLAIN_DIR" 2>/dev/null; then
        rmdir "$PLAIN_DIR" 2>/dev/null || true
        warn "Vault lazy-unmounted (some files were still open)."
        ok "Vault will fully lock once open files are closed."
    else
        die "Failed to unmount. Close all files/terminals using ${PLAIN_DIR} first.
      Check with: lsof +D ${PLAIN_DIR}"
    fi
}

# ── Show vault contents ──────────────────────────
show_contents() {
    echo ""
    echo -e "${G}${BOLD}  Vault contents:${RST}"
    echo -e "${DIM}  ─────────────────────────────────────${RST}"
    ls --color=always -lah "$PLAIN_DIR" 2>/dev/null | sed 's/^/  /'
    echo -e "${DIM}  ─────────────────────────────────────${RST}"
    echo -e "${DIM}  Path: ${PLAIN_DIR}${RST}"
    echo ""
}

# ── Show vault info ───────────────────────────────
show_info() {
    echo ""
    echo -e "${B}${BOLD}  Vault Information${RST}"
    echo -e "${DIM}  ─────────────────────────────────────${RST}"
    echo -e "  Owner:       ${W}${VAULT_USER}${RST} (uid ${VAULT_UID}, gid ${VAULT_GID})"
    echo -e "  Cipher dir:  ${DIM}${CIPHER_DIR}${RST}"
    echo -e "  Mount point: ${DIM}${PLAIN_DIR}${RST}"
    echo -e "  Mounted:     $(is_mounted && echo -e "${G}yes${RST}" || echo -e "${R}no${RST}")"

    # Cipher dir size
    local cipher_size
    cipher_size="$(du -sh "$CIPHER_DIR" 2>/dev/null | cut -f1)" || cipher_size="unknown"
    echo -e "  Encrypted:   ${cipher_size}"

    if is_mounted; then
        local plain_size
        plain_size="$(du -sh "$PLAIN_DIR" 2>/dev/null | cut -f1)" || plain_size="unknown"
        echo -e "  Decrypted:   ${plain_size}"
    fi

    # gocryptfs version
    local gcver
    gcver="$(gocryptfs -version 2>/dev/null | head -1)" || gcver="unknown"
    echo -e "  Engine:      ${DIM}${gcver}${RST}"
    echo -e "${DIM}  ─────────────────────────────────────${RST}"
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
    [[ ${#new_pass} -ge 8 ]]      || die "Passphrase must be at least 8 characters."

    # gocryptfs -passwd with -extpass for old, pipe for new
    # Secure temp files with restrictive permissions
    local tmp_old tmp_new
    tmp_old="$(mktemp /tmp/.fv-XXXXXX)"
    tmp_new="$(mktemp /tmp/.fv-XXXXXX)"
    chmod 600 "$tmp_old" "$tmp_new"

    printf '%s' "$old_pass" > "$tmp_old"
    printf '%s' "$new_pass" > "$tmp_new"

    # Trap to clean up temp files on any exit
    trap 'rm -f "$tmp_old" "$tmp_new" 2>/dev/null' EXIT

    if gocryptfs -passwd \
        -extpass "cat ${tmp_old}" \
        -passfile "$tmp_new" \
        "$CIPHER_DIR" 2>/dev/null; then
        rm -f "$tmp_old" "$tmp_new"
        trap - EXIT
        ok "Passphrase updated."
    else
        rm -f "$tmp_old" "$tmp_new"
        trap - EXIT
        die "Passphrase change failed - wrong current passphrase?"
    fi
}

# ── Export vault (tar backup of cipher dir) ───────
export_vault() {
    local backup_name="foldervault-backup-$(date +%Y%m%d-%H%M%S).tar.gz"
    local backup_path="${SCRIPT_DIR}/${backup_name}"

    info "Creating encrypted backup..."
    tar czf "$backup_path" -C "$SCRIPT_DIR" \
        "$(basename "$CIPHER_DIR")" \
        "$(basename "$OWNER_FILE")" 2>/dev/null \
        || die "Backup failed."
    chmod 600 "$backup_path"
    ok "Backup saved: ${backup_path}"
    echo -e "${DIM}  Size: $(du -h "$backup_path" | cut -f1)${RST}"
    echo -e "${DIM}  This is the encrypted data - safe to store anywhere.${RST}"
    echo -e "${DIM}  Restore by extracting alongside this script.${RST}"
}

# ── Settings menu ─────────────────────────────────
settings_menu() {
    while true; do
        echo ""
        echo -e "${B}${BOLD}  ┌── Vault Settings ──────────────────────┐${RST}"
        echo -e "${B}${BOLD}  |${RST}                                         ${B}${BOLD}|${RST}"
        echo -e "${B}${BOLD}  |${RST}  ${W}P${RST}  Change passphrase                 ${B}${BOLD}|${RST}"
        echo -e "${B}${BOLD}  |${RST}  ${W}I${RST}  Vault info                        ${B}${BOLD}|${RST}"
        echo -e "${B}${BOLD}  |${RST}  ${W}E${RST}  Export encrypted backup            ${B}${BOLD}|${RST}"
        echo -e "${B}${BOLD}  |${RST}  ${R}D${RST}  Destroy vault (permanent)          ${B}${BOLD}|${RST}"
        echo -e "${B}${BOLD}  |${RST}  ${W}B${RST}  Back                               ${B}${BOLD}|${RST}"
        echo -e "${B}${BOLD}  |${RST}                                         ${B}${BOLD}|${RST}"
        echo -e "${B}${BOLD}  └─────────────────────────────────────────┘${RST}"
        echo ""
        prompt "Choice:"
        read -r choice

        case "${choice^^}" in
            P)
                if is_mounted; then
                    info "Locking vault before passphrase change..."
                    do_lock
                fi
                change_passphrase
                ;;
            I)
                show_info
                ;;
            E)
                export_vault
                ;;
            D)
                echo ""
                warn "This will PERMANENTLY destroy the vault and ALL encrypted contents!"
                warn "There is no recovery. This is irreversible."
                echo ""
                prompt "Type 'DESTROY' to confirm:"
                read -r confirm
                if [[ "$confirm" == "DESTROY" ]]; then
                    if is_mounted; then
                        info "Unmounting vault..."
                        fusermount -u "$PLAIN_DIR" 2>/dev/null || true
                        rmdir "$PLAIN_DIR" 2>/dev/null || true
                    fi
                    rm -rf "$CIPHER_DIR" "$PLAIN_DIR" "$OWNER_FILE"
                    ok "Vault destroyed."
                    exit 0
                else
                    info "Cancelled."
                fi
                ;;
            B|"")
                return
                ;;
            *)
                warn "Unknown option."
                ;;
        esac
    done
}

# ══════════════════════════════════════════════════
#  MAIN
# ══════════════════════════════════════════════════
main() {
    # Handle --help before anything else
    case "${1:-}" in
        -h|--help)
            banner
            echo -e "  ${W}${BOLD}Usage:${RST}  $(basename "$0") [OPTION]"
            echo ""
            echo -e "  ${W}Options:${RST}"
            echo -e "    ${DIM}(none)${RST}       Interactive mode (create/unlock/lock/settings)"
            echo -e "    ${W}--lock${RST}       Lock vault and exit"
            echo -e "    ${W}--status${RST}     Show vault status"
            echo -e "    ${W}--diag${RST}       Run diagnostics"
            echo -e "    ${W}-h, --help${RST}   Show this help"
            echo ""
            echo -e "  ${W}How it works:${RST}"
            echo -e "    First run creates an encrypted vault in the current directory."
            echo -e "    Subsequent runs toggle lock/unlock. No sudo needed."
            echo -e "    Only the creating user can access decrypted files."
            echo -e "    Root and other users see nothing (FUSE owner-only mount)."
            echo ""
            echo -e "  ${W}Files created:${RST}"
            echo -e "    ${DIM}.foldervault.cipher/${RST}   Encrypted data (always on disk)"
            echo -e "    ${DIM}.foldervault.owner${RST}     Owner UID tracking"
            echo -e "    ${DIM}foldervault/${RST}           Decrypted mountpoint (only when unlocked)"
            echo ""
            exit 0
            ;;
        --lock)
            banner
            if is_mounted; then
                do_lock
            else
                info "Vault is already locked."
            fi
            exit 0
            ;;
        --status)
            banner
            local has_cipher=false
            [[ -d "$CIPHER_DIR" && -f "$CIPHER_DIR/gocryptfs.conf" ]] && has_cipher=true
            if ! $has_cipher; then
                echo -e "  ${DIM}No vault in this directory.${RST}"
            elif is_mounted; then
                echo -e "  ${G}${BOLD}Unlocked${RST}"
                echo -e "  ${DIM}${PLAIN_DIR}${RST}"
            else
                echo -e "  ${Y}${BOLD}Locked${RST}"
            fi
            exit 0
            ;;
        --diag)
            banner
            echo -e "  ${W}${BOLD}Diagnostics${RST}"
            echo -e "  ─────────────────────────────────────"
            echo -e "  User:         ${VAULT_USER} (uid ${VAULT_UID}, gid ${VAULT_GID})"
            echo -e "  Script dir:   ${SCRIPT_DIR}"
            echo -e "  Dir writable: $(test -w "$SCRIPT_DIR" && echo -e "${G}yes${RST}" || echo -e "${R}no${RST}")"
            echo -e "  gocryptfs:    $(command -v gocryptfs 2>/dev/null || echo "NOT FOUND")"
            echo -e "  Version:      $(gocryptfs -version 2>/dev/null | head -1 || echo "unknown")"
            echo -e "  fusermount:   $(command -v fusermount 2>/dev/null || echo "NOT FOUND")"
            echo -e "  /etc/fuse.conf user_allow_other: $(grep -q '^user_allow_other' /etc/fuse.conf 2>/dev/null && echo -e "${G}enabled${RST}" || echo -e "${DIM}disabled (not needed)${RST}")"
            echo -e "  Cipher dir:   $(test -d "$CIPHER_DIR" && echo "exists" || echo "none")"
            echo -e "  Mounted:      $(is_mounted && echo -e "${G}yes${RST}" || echo "no")"
            if [[ -d "$CIPHER_DIR" ]]; then
                echo -e "  Cipher owner: $(stat -c '%U:%G (%u:%g)' "$CIPHER_DIR" 2>/dev/null || echo "unknown")"
            fi
            echo -e "  ─────────────────────────────────────"
            exit 0
            ;;
    esac

    refuse_root
    check_deps
    banner

    local has_cipher=false
    [[ -d "$CIPHER_DIR" && -f "$CIPHER_DIR/gocryptfs.conf" ]] && has_cipher=true

    # ── CASE 1: No vault exists - first run ───────
    if ! $has_cipher; then
        check_writability

        echo -e "  ${W}No vault found in this directory.${RST}"
        echo -e "  ${DIM}A new encrypted folder will be created here.${RST}"
        echo -e "  ${DIM}No sudo required - you (${VAULT_USER}) will be the sole owner.${RST}"
        echo ""
        prompt "Create encrypted vault? [Y/n]:"
        read -r yn
        [[ "${yn^^}" == "N" ]] && { info "Aborted."; exit 0; }
        echo ""

        local pass confirm
        read_pass pass    "Set passphrase (min 8 chars)"
        read_pass confirm "Confirm passphrase"
        [[ "$pass" == "$confirm" ]] || die "Passphrases do not match."
        [[ -n "$pass" ]]           || die "Passphrase cannot be empty."
        [[ ${#pass} -ge 8 ]]      || die "Passphrase must be at least 8 characters."

        info "Initialising vault..."
        do_init "$pass"
        ok "Vault created."

        info "Mounting with user-level permissions..."
        do_unlock "$pass" || die "Mount failed after init."
        ok "Vault mounted."

        echo ""
        echo -e "${G}${BOLD}  Setup complete!${RST}"
        echo -e "${DIM}  ─────────────────────────────────────${RST}"
        echo -e "  Owner:     ${W}${VAULT_USER}${RST} (only you can access)"
        echo -e "  Vault:     ${PLAIN_DIR}"
        echo -e "  Sudo:      ${G}not required${RST}"
        echo -e "  Root sees: ${R}nothing${RST} (FUSE owner-only mount)"
        echo -e "${DIM}  ─────────────────────────────────────${RST}"
        echo ""
        echo -e "${DIM}  Add files to: ${PLAIN_DIR}${RST}"
        echo -e "${DIM}  Lock vault:   run this script again${RST}"
        echo ""
        exit 0
    fi

    # ── Verify caller is the vault owner ──────────
    verify_owner

    # ── CASE 2: Vault exists, LOCKED ──────────────
    if ! is_mounted; then
        echo -e "  ${Y}${BOLD}Locked vault detected${RST}"
        echo -e "  ${DIM}Owner: ${VAULT_USER}${RST}"
        echo ""

        local attempts=0 max_attempts=3
        while (( attempts < max_attempts )); do
            local pass
            read_pass pass "Passphrase"
            if do_unlock "$pass"; then
                ok "Vault unlocked."
                show_contents
                echo -e "${DIM}  Lock again: run this script${RST}"
                echo ""
                exit 0
            fi
            (( attempts++ ))
            local remaining=$(( max_attempts - attempts ))
            if (( remaining > 0 )); then
                warn "Wrong passphrase. ${remaining} attempt(s) remaining."
            else
                die "Too many failed attempts."
            fi
        done
        exit 1
    fi

    # ── CASE 3: Vault is UNLOCKED (mounted) ───────
    echo -e "  ${G}${BOLD}Vault is unlocked${RST}"
    echo -e "  ${DIM}${PLAIN_DIR}${RST}"
    echo ""
    show_contents
    echo -e "  ${W}L${RST}  Lock vault"
    echo -e "  ${W}S${RST}  Settings  ${DIM}(passphrase, info, backup, destroy)${RST}"
    echo -e "  ${W}Q${RST}  Quit (leave unlocked)"
    echo ""
    prompt "Choice [L/s/q]:"
    read -r choice
    case "${choice^^}" in
        S)    settings_menu ;;
        Q|"") info "Vault remains unlocked." ;;
        L|*)  do_lock ;;
    esac
    exit 0
}

main "$@"
