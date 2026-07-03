#!/usr/bin/env bash
#
# convert2base64.sh
# Converts any file into a self-contained bash script that embeds the file
# as base64 and rebuilds the original file when executed.
#
# Execution flow:
#   1. Takes source path from argument ($1) OR prompts if none given
#   2. Validates the file exists and reads its byte size
#   3. Encodes the file to base64 and writes a rebuild script next to it
#   4. Rebuild script, when run, decodes the data and verifies byte count
#
# Usage:
#   ./convert2base64.sh /path/to/source.file
#   ./convert2base64.sh            (interactive prompt)
#

set -euo pipefail

if [[ $# -ge 1 ]]; then
    # Non-interactive: path supplied as argument
    SRC="$1"
else
    # Interactive: prompt for path
    printf '> enter path to source file :\n   '
    read -r SRC
fi

# Trim surrounding whitespace/quotes a user might paste
SRC="${SRC#\"}"; SRC="${SRC%\"}"
SRC="${SRC#\'}"; SRC="${SRC%\'}"

if [[ -z "$SRC" ]]; then
    echo "> ERROR: no path entered" >&2
    exit 1
fi

if [[ ! -f "$SRC" ]]; then
    echo "> ERROR: source file '$SRC' not found" >&2
    exit 1
fi

BASENAME="$(basename "$SRC")"
OUT="${SRC}.sh"

# Portable byte size (Linux stat vs BSD/macOS stat)
if SIZE=$(stat -c%s "$SRC" 2>/dev/null); then :; else SIZE=$(stat -f%z "$SRC"); fi

echo "> Source file '$BASENAME' is $SIZE bytes"
echo "> creating '${BASENAME}.sh'"

# Build the rebuild script
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

# Verify byte count
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

# Absolute path of the output for the final message
OUT_ABS="$(cd "$(dirname "$OUT")" && pwd)/$(basename "$OUT")"

echo "> base64 rebuild script saved at '$OUT_ABS'"
echo "> execute the script in any directory to rebuild the source file there."
