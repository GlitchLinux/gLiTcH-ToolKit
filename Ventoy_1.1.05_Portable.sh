#!/bin/bash

# Ventoy version
VENTOY_VERSION="1.1.05"

# Download URL
DOWNLOAD_URL="https://sourceforge.net/projects/ventoy/files/v${VENTOY_VERSION}/ventoy-${VENTOY_VERSION}-linux.tar.gz/download"

# Temporary directory
TMP_DIR="/tmp/ventoy"
TAR_FILE="${TMP_DIR}/ventoy.tar.gz"
EXTRACT_DIR="${TMP_DIR}/ventoy-${VENTOY_VERSION}"

# Cleanup previous runs
rm -rf "${TMP_DIR}"
mkdir -p "${TMP_DIR}"

# Download Ventoy
echo "Downloading Ventoy ${VENTOY_VERSION}..."
if ! wget -O "${TAR_FILE}" "${DOWNLOAD_URL}"; then
    echo "Failed to download Ventoy"
    exit 1
fi

# Extract the archive
echo "Extracting Ventoy..."
if ! tar -xzf "${TAR_FILE}" -C "${TMP_DIR}"; then
    echo "Failed to extract Ventoy"
    exit 1
fi

# Determine system architecture
ARCH=$(uname -m)
case "$ARCH" in
    x86_64) GUI_BIN="VentoyGUI.x86_64" ;;
    i686|i386) GUI_BIN="VentoyGUI.i386" ;;
    aarch64|arm64) GUI_BIN="VentoyGUI.aarch64" ;;
    mips64) GUI_BIN="VentoyGUI.mips64el" ;;
    *) echo "Unsupported architecture: $ARCH"; exit 1 ;;
esac

# Find the GUI binary
GUI_PATH="${EXTRACT_DIR}/tool/${ARCH}/${GUI_BIN}"
if [ ! -f "${GUI_PATH}" ]; then
    GUI_PATH="${EXTRACT_DIR}/${GUI_BIN}"
    if [ ! -f "${GUI_PATH}" ]; then
        echo "Could not find Ventoy GUI for architecture $ARCH"
        echo "You can try running the shell script instead:"
        echo "cd ${EXTRACT_DIR} && ./Ventoy2Disk.sh"
        exit 1
    fi
fi

# Make the binary executable
chmod +x "${GUI_PATH}"

# Run Ventoy GUI
echo "Starting Ventoy GUI..."
"${GUI_PATH}"

# Alternative: Run the shell script version
# cd "${EXTRACT_DIR}" && ./Ventoy2Disk.sh
