#!/bin/bash

# Simple WSL tar backup creator
# Creates .tar from root filesystem for WSL import

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log_info() { echo -e "${GREEN}[INFO]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_step() { echo -e "${BLUE}[STEP]${NC} $1"; }

# Check root
if [[ $EUID -ne 0 ]]; then
    log_error "Run as root: sudo $0"
    exit 1
fi

echo -e "${GREEN}WSL Backup Creator${NC}"
echo "=================="

# Get distribution name
while [[ -z "$DISTRO_NAME" ]]; do
    read -p "Distribution name: " DISTRO_NAME
    if [[ ! "$DISTRO_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Use only letters, numbers, hyphens, underscores"
        DISTRO_NAME=""
    fi
done

# Get working directory
read -p "Working directory [/tmp]: " WORK_DIR
WORK_DIR=${WORK_DIR:-/tmp}

# Validate/create directory
if [[ ! -d "$WORK_DIR" ]]; then
    read -p "Create $WORK_DIR? (y/N): " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        mkdir -p "$WORK_DIR" || { log_error "Failed to create directory"; exit 1; }
    else
        exit 1
    fi
fi

if [[ ! -w "$WORK_DIR" ]]; then
    log_error "Directory not writable: $WORK_DIR"
    exit 1
fi

log_info "Using: $WORK_DIR"

# Files
TAR_FILE="$WORK_DIR/${DISTRO_NAME}.tar"
PS1_FILE="$WORK_DIR/install.ps1"
ZIP_FILE="$WORK_DIR/${DISTRO_NAME}-WSL-installer.zip"

# Check space
AVAILABLE=$(df "$WORK_DIR" --output=avail | tail -n1)
ESTIMATED=$(du -s / 2>/dev/null | awk '{print $1}' || echo "5000000")

if [[ $AVAILABLE -lt $ESTIMATED ]]; then
    log_error "Low space. Available: $((AVAILABLE/1024))MB, Need: ~$((ESTIMATED/1024))MB"
    read -p "Continue? (y/N): " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && exit 1
fi

# Create tar (ignore all errors)
log_step "Creating tar archive..."
timeout 3600 tar --create \
    --file="$TAR_FILE" \
    --exclude='/dev' \
    --exclude='/proc' \
    --exclude='/sys' \
    --exclude='/run' \
    --exclude='/mnt' \
    --exclude='/media' \
    --exclude='/tmp' \
    --exclude='/var/tmp' \
    --exclude='/var/cache' \
    --exclude='/var/log' \
    --exclude='/home/*/.cache' \
    --exclude='/root/.cache' \
    --exclude='/swapfile' \
    --exclude='/swap.img' \
    --exclude='lost+found' \
    --exclude='/boot/efi' \
    --exclude='/boot/grub' \
    --numeric-owner \
    --preserve-permissions \
    --ignore-failed-read \
    --one-file-system \
    -C / . &

TAR_PID=$!
echo "Tar running (PID: $TAR_PID)..."

# Monitor progress
while kill -0 $TAR_PID 2>/dev/null; do
    if [[ -f "$TAR_FILE" ]]; then
        SIZE=$(du -m "$TAR_FILE" 2>/dev/null | cut -f1 || echo "0")
        echo -ne "\rProgress: ${SIZE}MB..."
    fi
    sleep 5
done

wait $TAR_PID

if [[ ! -f "$TAR_FILE" ]]; then
    log_error "Tar creation failed"
    exit 1
fi

TAR_SIZE=$(du -m "$TAR_FILE" | cut -f1)
log_info "Tar created: ${TAR_SIZE}MB"

# Create PowerShell installer
log_step "Creating installer..."
cat > "$PS1_FILE" << 'EOF'
# WSL Distribution Installer
param([string]$InstallPath = "")

if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Error: Run as Administrator!" -ForegroundColor Red
    pause; exit 1
}

$DistroName = "DISTRO_NAME_PLACEHOLDER"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TarFile = Join-Path $ScriptDir "$DistroName.tar"

if ([string]::IsNullOrEmpty($InstallPath)) {
    $InstallPath = "C:\WSL\$DistroName"
}

Write-Host "Installing $DistroName to $InstallPath" -ForegroundColor Green

if (-not (Test-Path $TarFile)) {
    Write-Host "Error: $DistroName.tar not found!" -ForegroundColor Red
    pause; exit 1
}

New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
wsl --import "$DistroName" "$InstallPath" "$TarFile"

if ($LASTEXITCODE -eq 0) {
    Write-Host "SUCCESS! Launch with: wsl -d $DistroName" -ForegroundColor Green
} else {
    Write-Host "Import failed!" -ForegroundColor Red
}
pause
EOF

sed -i "s/DISTRO_NAME_PLACEHOLDER/$DISTRO_NAME/g" "$PS1_FILE"

# Create ZIP
log_step "Creating ZIP package..."
cd "$WORK_DIR"
zip -q "${DISTRO_NAME}-WSL-installer.zip" "${DISTRO_NAME}.tar" "install.ps1"

if [[ ! -f "$ZIP_FILE" ]]; then
    log_error "ZIP creation failed"
    exit 1
fi

ZIP_SIZE=$(du -m "$ZIP_FILE" | cut -f1)

# Copy to /home if using /tmp
if [[ "$WORK_DIR" == "/tmp" ]]; then
    cp "$ZIP_FILE" "/home/"
    FINAL_LOCATION="/home/${DISTRO_NAME}-WSL-installer.zip"
    log_info "Copied to /home"
else
    read -p "Copy to /home? (Y/n): " -n 1 -r
    echo
    if [[ -z "$REPLY" || $REPLY =~ ^[Yy]$ ]]; then
        cp "$ZIP_FILE" "/home/"
        FINAL_LOCATION="/home/${DISTRO_NAME}-WSL-installer.zip"
        log_info "Copied to /home"
    else
        FINAL_LOCATION="$ZIP_FILE"
    fi
fi

# Cleanup temp files
rm -f "$TAR_FILE" "$PS1_FILE"

echo
log_info "COMPLETE!"
echo "File: $FINAL_LOCATION"
echo "Size: ${ZIP_SIZE}MB"
echo
echo "Windows installation:"
echo "1. Extract ZIP"
echo "2. Right-click install.ps1 → Run with PowerShell (as Admin)"
