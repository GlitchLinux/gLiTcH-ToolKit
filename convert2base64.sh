#!/usr/bin/env bash
#
# convert2base64.sh
# Converts a file (or a whole directory) into a self-contained bash script
# that embeds the data as base64 and rebuilds it when executed.
#
# Modes:
#   SINGLE FILE  -> <file>.sh          rebuilds that one file
#   DIRECTORY    -> <dirname>-Files.sh rebuilds every file (bulk mode)
#
# Usage:
#   ./convert2base64.sh /path/to/source.file
#   ./convert2base64.sh /path/to/directory
#   ./convert2base64.sh                        (interactive prompt)
#

set -euo pipefail

# ---- resolve input path (arg or prompt) -------------------------------------
if [[ $# -ge 1 ]]; then
    SRC="$1"
else
    printf '> enter path to source file or directory :\n   '
    read -r SRC
fi

# Trim surrounding whitespace/quotes a user might paste
SRC="${SRC#\"}"; SRC="${SRC%\"}"
SRC="${SRC#\'}"; SRC="${SRC%\'}"

if [[ -z "$SRC" ]]; then
    echo "> ERROR: no path entered" >&2
    exit 1
fi

# strip a trailing slash from directory paths (keeps basename clean)
[[ "$SRC" != "/" ]] && SRC="${SRC%/}"

# ---- helpers ----------------------------------------------------------------
# portable byte size
fsize() {
    local sz
    if sz=$(stat -c%s "$1" 2>/dev/null); then printf '%s' "$sz"; else stat -f%z "$1"; fi
}

# human-readable size from a byte count
human() {
    local b=$1
    if   (( b >= 1073741824 )); then awk -v b="$b" 'BEGIN{printf "%.2f GB", b/1073741824}'
    elif (( b >= 1048576   )); then awk -v b="$b" 'BEGIN{printf "%.2f MB", b/1048576}'
    elif (( b >= 1024      )); then awk -v b="$b" 'BEGIN{printf "%.2f KB", b/1024}'
    else printf '%s bytes' "$b"; fi
}

# =============================================================================
# BULK MODE  (directory) - fully recursive, preserves tree + symlinks
# =============================================================================
if [[ -d "$SRC" ]]; then
    DIRNAME="$(basename "$SRC")"
    if [[ "$SRC" == */* ]]; then
        OUT="${SRC%/*}/${DIRNAME}-Files.sh"
    else
        OUT="${DIRNAME}-Files.sh"   # relative dir in cwd
    fi

    # Enumerate the whole tree relative to $SRC.
    # Directories, symlinks and regular files are gathered separately so the
    # rebuild can recreate structure first, then files, then links.
    pushd "$SRC" >/dev/null

    mapfile -d '' DIRS  < <(find . -mindepth 1 -type d        -print0 | sort -z)
    mapfile -d '' LINKS < <(find . -mindepth 1 -type l        -print0 | sort -z)
    mapfile -d '' FILES < <(find . -mindepth 1 -type f        -print0 | sort -z)

    if [[ ${#FILES[@]} -eq 0 && ${#LINKS[@]} -eq 0 ]]; then
        popd >/dev/null
        echo "> ERROR: no files or symlinks found in directory '$SRC'" >&2
        exit 1
    fi

    TOTAL=0
    for f in "${FILES[@]}"; do TOTAL=$(( TOTAL + $(fsize "$f") )); done

    echo "> Directory '$DIRNAME' contains ${#FILES[@]} files, ${#LINKS[@]} symlinks, ${#DIRS[@]} subdirs ~ $(human "$TOTAL")"
    if command -v tree >/dev/null 2>&1; then
        echo "> tree:"
        tree -a --noreport "." | sed 's/^/    /'
    fi
    printf "> Convert all of '%s' (recursive) to '%s-Files.sh'? [N/y] " "$DIRNAME" "$DIRNAME"
    read -r ANS
    case "$ANS" in
        [Yy]*) ;;
        *) popd >/dev/null; echo "> aborted"; exit 0 ;;
    esac

    echo "> creating '$(basename "$OUT")'..."

    # ---- write recursive rebuild script ----
    {
        cat <<BULK_HEADER
#!/usr/bin/env bash
# Self-extracting base64 RECURSIVE rebuild script for directory: $DIRNAME
# Files: ${#FILES[@]}  Symlinks: ${#LINKS[@]}  Subdirs: ${#DIRS[@]}  Total: $(human "$TOTAL")
# Rebuilds the complete '$DIRNAME/' tree in the current working directory.
set -euo pipefail

FAIL=0
ROOT="$DIRNAME"
_fsize() { local s; if s=\$(stat -c%s "\$1" 2>/dev/null); then printf '%s' "\$s"; else stat -f%z "\$1"; fi; }

if [[ -e "\$ROOT" ]]; then
    if { true </dev/tty; } 2>/dev/null; then
        printf "> '%s' already exists here. Merge/overwrite into it? [y/N] " "\$ROOT"
        read -r a </dev/tty
    else
        a="y"   # non-interactive: proceed
    fi
    case "\$a" in [Yy]*) ;; *) echo "> aborted"; exit 1 ;; esac
fi

echo "> rebuilding tree '\$ROOT/' ..."
mkdir -p "\$ROOT"

_mkdir() { mkdir -p "\$ROOT/\$1"; }

_link() {
    # args: linkpath  target
    local lp="\$ROOT/\$1" tgt="\$2"
    mkdir -p "\$(dirname "\$lp")"
    ln -sfn "\$tgt" "\$lp"
    echo ">   LINK '\$1' -> '\$tgt'"
}

_file() {
    # args: relpath  expected_size  mode   (base64 on stdin)
    local rp="\$ROOT/\$1" expect="\$2" mode="\$3"
    mkdir -p "\$(dirname "\$rp")"
    base64 -d > "\$rp"
    local got; got=\$(_fsize "\$rp")
    [[ -n "\$mode" ]] && chmod "\$mode" "\$rp" 2>/dev/null || true
    if [[ "\$got" == "\$expect" ]]; then
        echo ">   OK  '\$1' (\$got bytes)"
    else
        echo ">   WARNING '\$1' size mismatch: got \$got expected \$expect - may be corrupt"
        FAIL=1
    fi
}
BULK_HEADER

        # recreate directories first (so empty dirs survive too)
        for d in "${DIRS[@]}"; do
            d="${d#./}"
            printf "_mkdir %q\n" "$d"
        done

        # symlinks: store link path + target verbatim
        for l in "${LINKS[@]}"; do
            rel="${l#./}"
            tgt="$(readlink "$l")"
            printf "_link %q %q\n" "$rel" "$tgt"
        done

        # files: one heredoc blob each, preserving relative path + exec mode
        for f in "${FILES[@]}"; do
            rel="${f#./}"
            fsz="$(fsize "$f")"
            if [[ -x "$f" ]]; then mode="755"; else mode="644"; fi
            printf "\n_file %q %s %s << 'B64_EOF'\n" "$rel" "$fsz" "$mode"
            base64 "$f"
            printf "B64_EOF\n"
        done

        cat <<'BULK_FOOTER'

if [[ "$FAIL" -eq 0 ]]; then
    echo "> recursive rebuild complete - all files verified OK"
else
    echo "> recursive rebuild finished WITH WARNINGS - one or more files may be corrupt"
    exit 2
fi
BULK_FOOTER
    } > "$OUT"

    popd >/dev/null
    chmod +x "$OUT"
    OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
    echo "> base64 recursive rebuild script saved at '$OUT_ABS'"
    echo "> execute the script in any directory to rebuild the full '$DIRNAME/' tree there."
    exit 0
fi

# =============================================================================
# SINGLE FILE MODE
# =============================================================================
if [[ ! -f "$SRC" ]]; then
    echo "> ERROR: source '$SRC' not found (not a file or directory)" >&2
    exit 1
fi

BASENAME="$(basename "$SRC")"
OUT="${SRC}.sh"
SIZE="$(fsize "$SRC")"

echo "> Source file '$BASENAME' is $SIZE bytes"
echo "> creating '${BASENAME}.sh'"

{
    cat <<REBUILD_HEADER
#!/usr/bin/env bash
# Self-extracting base64 rebuild script for: $BASENAME
# Original size: $SIZE bytes
set -euo pipefail

OUT_FILE="$BASENAME"
EXPECTED_SIZE=$SIZE

if [[ -e "\$OUT_FILE" ]]; then
    printf "> '%s' already exists. Overwrite? [y/N] " "\$OUT_FILE"
    read -r ANS
    case "\$ANS" in
        [Yy]*) ;;
        *) echo "> aborted"; exit 1 ;;
    esac
fi

echo "> rebuilding '\$OUT_FILE'..."
base64 -d <<'B64_DATA' > "\$OUT_FILE"
REBUILD_HEADER

    base64 "$SRC"

    cat <<'REBUILD_FOOTER'
B64_DATA

if ACTUAL=$(stat -c%s "$OUT_FILE" 2>/dev/null); then :; else ACTUAL=$(stat -f%z "$OUT_FILE"); fi

if [[ "$ACTUAL" -eq "$EXPECTED_SIZE" ]]; then
    echo "> rebuild complete: '$OUT_FILE' ($ACTUAL bytes) - byte count matches"
else
    echo "> WARNING: byte count mismatch!"
    echo ">   expected: $EXPECTED_SIZE bytes"
    echo ">   actual:   $ACTUAL bytes"
    echo ">   file rebuild may be corrupt."
    exit 2
fi
REBUILD_FOOTER
} > "$OUT"

chmod +x "$OUT"
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"
echo "> base64 rebuild script saved at '$OUT_ABS'"
echo "> execute the script in any directory to rebuild the source file there."
