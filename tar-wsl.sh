#!/bin/bash

# Script to create WSL distribution package from running Debian system
# Creates: distro.tar, install.ps1, and distro-WSL-installer.zip

set -e  # Exit on any error - disabled for tar operations
set -o pipefail  # Make pipes fail if any command in pipe fails

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

log_step() {
    echo -e "${BLUE}[STEP]${NC} $1"
}

# Check if running as root
if [[ $EUID -ne 0 ]]; then
    log_error "This script must be run as root to access all system directories"
    log_info "Please run: sudo $0"
    exit 1
fi

# Prompt for WSL distribution name
while [[ -z "$DISTRO_NAME" ]]; do
    read -p "Enter WSL distribution name: " DISTRO_NAME
    if [[ ! "$DISTRO_NAME" =~ ^[a-zA-Z0-9_-]+$ ]]; then
        log_error "Invalid name. Use only letters, numbers, hyphens, and underscores."
        DISTRO_NAME=""
    fi
done

# Configuration
TEMP_DIR="/tmp/wsl-build-$$"
TAR_FILE="$TEMP_DIR/${DISTRO_NAME}.tar"
PS1_FILE="$TEMP_DIR/install.ps1"
ZIP_FILE="${DISTRO_NAME}-WSL-installer.zip"
FINAL_ZIP="/home/${ZIP_FILE}"

log_info "Creating WSL package for: $DISTRO_NAME"

# Check available space
AVAILABLE_SPACE=$(df /tmp --output=avail | tail -n1)
ESTIMATED_SIZE=$(du -s / 2>/dev/null | awk '{print $1}' || echo "5000000")

if [[ $AVAILABLE_SPACE -lt $((ESTIMATED_SIZE * 2)) ]]; then
    log_warn "Low space in /tmp. Available: $((AVAILABLE_SPACE/1024))MB, Estimated need: $((ESTIMATED_SIZE*2/1024))MB"
    read -p "Continue anyway? (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        exit 1
    fi
fi

# Create temporary directory
mkdir -p "$TEMP_DIR"

# Cleanup function
cleanup() {
    log_info "Cleaning up temporary files..."
    rm -rf "$TEMP_DIR"
}
trap cleanup EXIT

# Step 1: Create tar archive
log_step "1. Creating system tar archive (this may take several minutes)..."

tar --create \
    --file="$TAR_FILE" \
    --exclude='/dev/*' \
    --exclude='/proc/*' \
    --exclude='/sys/*' \
    --exclude='/run/*' \
    --exclude='/mnt/*' \
    --exclude='/media/*' \
    --exclude='/tmp/*' \
    --exclude='/var/tmp/*' \
    --exclude='/var/cache/apt/*' \
    --exclude='/var/lib/apt/lists/*' \
    --exclude='/var/log/*' \
    --exclude='/home/*/.cache' \
    --exclude='/root/.cache' \
    --exclude='/swapfile' \
    --exclude='/swap.img' \
    --exclude='/pagefile.sys' \
    --exclude='/hiberfil.sys' \
    --exclude='lost+found' \
    --exclude='/boot/efi' \
    --exclude='/boot/grub' \
    --exclude='*.log' \
    --exclude='*.tmp' \
    --exclude='/var/backups/*' \
    --exclude='/var/crash/*' \
    --exclude='/var/spool/*' \
    --numeric-owner \
    --preserve-permissions \
    --sparse \
    -C / .

TAR_SIZE_MB=$(du -m "$TAR_FILE" | cut -f1)
log_info "Tar archive created: ${TAR_SIZE_MB}MB"

# Step 2: Create PowerShell installation script
log_step "2. Creating PowerShell installation script..."

cat > "$PS1_FILE" << 'EOF'
# WSL Distribution Installer
# Run this script in PowerShell as Administrator

param(
    [string]$InstallPath = "",
    [switch]$Help
)

if ($Help) {
    Write-Host "WSL Distribution Installer" -ForegroundColor Green
    Write-Host ""
    Write-Host "Usage:"
    Write-Host "  .\install.ps1                    # Install to default location"
    Write-Host "  .\install.ps1 -InstallPath PATH  # Install to custom path"
    Write-Host ""
    Write-Host "This script must be run as Administrator."
    exit 0
}

# Check if running as administrator
if (-NOT ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Error: This script must be run as Administrator!" -ForegroundColor Red
    Write-Host "Right-click on PowerShell and select 'Run as administrator'" -ForegroundColor Yellow
    pause
    exit 1
}

$DistroName = "DISTRO_NAME_PLACEHOLDER"
$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$TarFile = Join-Path $ScriptDir "$DistroName.tar"

# Set default install path if not provided
if ([string]::IsNullOrEmpty($InstallPath)) {
    $InstallPath = "C:\WSL\$DistroName"
}

Write-Host "WSL Distribution Installer" -ForegroundColor Green
Write-Host "=========================" -ForegroundColor Green
Write-Host "Distribution: $DistroName" -ForegroundColor Cyan
Write-Host "Install Path: $InstallPath" -ForegroundColor Cyan
Write-Host "Tar File: $TarFile" -ForegroundColor Cyan
Write-Host ""

# Check if tar file exists
if (-not (Test-Path $TarFile)) {
    Write-Host "Error: Cannot find $DistroName.tar in the same directory as this script!" -ForegroundColor Red
    Write-Host "Expected location: $TarFile" -ForegroundColor Yellow
    pause
    exit 1
}

# Check if WSL is enabled
try {
    $wslOutput = wsl --status 2>&1
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Error: WSL is not properly installed or enabled!" -ForegroundColor Red
        Write-Host "Please install WSL first: https://docs.microsoft.com/en-us/windows/wsl/install" -ForegroundColor Yellow
        pause
        exit 1
    }
} catch {
    Write-Host "Error: WSL command not found!" -ForegroundColor Red
    pause
    exit 1
}

# Create installation directory
Write-Host "Creating installation directory..." -ForegroundColor Yellow
try {
    New-Item -ItemType Directory -Force -Path $InstallPath | Out-Null
    Write-Host "Directory created: $InstallPath" -ForegroundColor Green
} catch {
    Write-Host "Error: Failed to create directory $InstallPath" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    pause
    exit 1
}

# Import the distribution
Write-Host "Importing WSL distribution (this may take a few minutes)..." -ForegroundColor Yellow
try {
    $importCmd = "wsl --import `"$DistroName`" `"$InstallPath`" `"$TarFile`""
    Write-Host "Running: $importCmd" -ForegroundColor Gray
    
    Invoke-Expression $importCmd
    
    if ($LASTEXITCODE -eq 0) {
        Write-Host ""
        Write-Host "SUCCESS: WSL distribution '$DistroName' imported successfully!" -ForegroundColor Green
        Write-Host ""
        Write-Host "Next steps:" -ForegroundColor Cyan
        Write-Host "1. Launch your distribution: wsl -d $DistroName" -ForegroundColor White
        Write-Host "2. Create a user account: adduser yourusername" -ForegroundColor White
        Write-Host "3. Add user to sudo: usermod -aG sudo yourusername" -ForegroundColor White
        Write-Host "4. Set as default user: Create /etc/wsl.conf with [user] default=yourusername" -ForegroundColor White
        Write-Host "5. Update packages: apt update && apt upgrade" -ForegroundColor White
    } else {
        throw "WSL import command failed with exit code $LASTEXITCODE"
    }
} catch {
    Write-Host "Error: Failed to import WSL distribution!" -ForegroundColor Red
    Write-Host $_.Exception.Message -ForegroundColor Red
    pause
    exit 1
}

Write-Host ""
Write-Host "Installation completed successfully!" -ForegroundColor Green
pause
EOF

# Replace placeholder with actual distro name
sed -i "s/DISTRO_NAME_PLACEHOLDER/$DISTRO_NAME/g" "$PS1_FILE"

log_info "PowerShell script created"

# Step 3: Create ZIP package
log_step "3. Creating ZIP installer package..."

cd "$TEMP_DIR"
zip -q "$ZIP_FILE" "${DISTRO_NAME}.tar" "install.ps1"

if [[ ! -f "$ZIP_FILE" ]]; then
    log_error "Failed to create ZIP file"
    exit 1
fi

ZIP_SIZE_MB=$(du -m "$ZIP_FILE" | cut -f1)
log_info "ZIP package created: ${ZIP_SIZE_MB}MB"

# Step 4: Move to final location and cleanup
log_step "4. Moving to final location and cleaning up..."

mv "$ZIP_FILE" "$FINAL_ZIP"
FINAL_SIZE_MB=$(du -m "$FINAL_ZIP" | cut -f1)

# Final output
echo
log_info "WSL installer package created successfully!"
echo -e "${GREEN}File:${NC} $FINAL_LOCATION"
echo -e "${GREEN}Size:${NC} ${FINAL_SIZE_MB}MB"
echo
log_info "Package contents:"
echo "  - ${DISTRO_NAME}.tar (WSL distribution)"
echo "  - install.ps1 (PowerShell installer)"
echo
log_info "To install on Windows:"
echo "  1. Extract the ZIP file"
echo "  2. Right-click install.ps1 → Run with PowerShell (as Administrator)"
echo "  3. Follow the installation prompts"
