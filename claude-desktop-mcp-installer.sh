#!/bin/bash

#############################################################################
# Claude Desktop + MCP SSH Server Combined Installer
# For Debian 12 KDE (and other Debian/Ubuntu systems)
# 
# This script:
# 1. Installs Claude Desktop
# 2. Sets up SSH keys
# 3. Configures MCP SSH server
# 4. Tests everything
#############################################################################

set -e

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
MAGENTA='\033[0;35m'
NC='\033[0m' # No Color

# Configuration
MCP_PACKAGE="@idletoaster/ssh-mcp-server@latest"
CONFIG_DIR="$HOME/.config/Claude"
CONFIG_FILE="$CONFIG_DIR/claude_desktop_config.json"
SSH_DIR="$HOME/.ssh"
SSH_KEY="$SSH_DIR/id_rsa"
TEMP_DIR="/tmp/claude-setup-$$"
CLAUDE_DEB_URL="https://github.com/aaddrick/claude-desktop-debian/releases/download/v1.1.6%2Bclaude0.14.10/claude-desktop_0.14.10_amd64.deb"
CLAUDE_DEB_FILE="claude-desktop_0.14.10_amd64.deb"

# Track progress
STEPS_COMPLETED=0
TOTAL_STEPS=11

#############################################################################
# Helper Functions
#############################################################################

print_header() {
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}$1${NC}"
    echo -e "${BLUE}================================================${NC}"
    echo ""
}

print_step() {
    STEPS_COMPLETED=$((STEPS_COMPLETED + 1))
    echo -e "${YELLOW}[STEP $STEPS_COMPLETED/$TOTAL_STEPS]${NC} $1"
}

print_success() {
    echo -e "${GREEN}✓ $1${NC}"
}

print_warning() {
    echo -e "${YELLOW}⚠ $1${NC}"
}

print_error() {
    echo -e "${RED}✗ $1${NC}"
}

print_info() {
    echo -e "${MAGENTA}ℹ $1${NC}"
}

#############################################################################
# STEP 1: Welcome and System Check
#############################################################################
print_header "Claude Desktop + MCP SSH Setup for Debian 12"
echo "This installer will:"
echo "  • Install Claude Desktop"
echo "  • Install Node.js and npm"
echo "  • Setup SSH keys"
echo "  • Configure MCP SSH server"
echo "  • Test connectivity"
echo ""

print_step "Checking system compatibility..."

if [ ! -f /etc/os-release ]; then
    print_error "Cannot determine OS"
    exit 1
fi

source /etc/os-release
if [[ "$ID" != "debian" && "$ID" != "ubuntu" ]]; then
    print_error "This script is for Debian/Ubuntu. You are on: $PRETTY_NAME"
    exit 1
fi

print_success "System: $PRETTY_NAME"
print_success "Ready to begin installation"
echo ""

# Ask for confirmation
read -p "Continue with installation? (y/n): " -n 1 -r
echo
if [[ ! $REPLY =~ ^[Yy]$ ]]; then
    print_error "Installation cancelled"
    exit 0
fi
echo ""

#############################################################################
# STEP 2: Create temp directory and update package lists
#############################################################################
print_step "Preparing system..."

mkdir -p "$TEMP_DIR"
print_success "Temp directory created: $TEMP_DIR"

print_info "Updating package lists..."
sudo apt update -y > /dev/null 2>&1
print_success "Package lists updated"
echo ""

#############################################################################
# STEP 3: Install Node.js and npm (required for MCP)
#############################################################################
print_step "Installing Node.js and npm..."

if command -v node &> /dev/null; then
    NODE_VERSION=$(node --version)
    print_warning "Node.js already installed: $NODE_VERSION"
else
    print_info "Installing Node.js..."
    sudo apt install -y nodejs npm > /dev/null 2>&1
    print_success "Node.js and npm installed"
fi

NODE_VERSION=$(node --version)
NPM_VERSION=$(npm --version)
print_success "Node.js: $NODE_VERSION"
print_success "npm: $NPM_VERSION"

NPX_PATH=$(which npx)
print_success "npx path: $NPX_PATH"
echo ""

#############################################################################
# STEP 4: Download Claude Desktop
#############################################################################
print_step "Downloading Claude Desktop..."

cd "$TEMP_DIR"
print_info "Downloading from: $CLAUDE_DEB_URL"

if wget -q "$CLAUDE_DEB_URL" 2>/dev/null; then
    print_success "Claude Desktop downloaded"
else
    print_error "Failed to download Claude Desktop"
    print_info "Trying alternative method..."
    curl -sL -o "$CLAUDE_DEB_FILE" "$CLAUDE_DEB_URL"
    if [ ! -f "$CLAUDE_DEB_FILE" ]; then
        print_error "Could not download Claude Desktop. Check your internet connection."
        exit 1
    fi
fi

if [ -f "$CLAUDE_DEB_FILE" ]; then
    FILESIZE=$(ls -lh "$CLAUDE_DEB_FILE" | awk '{print $5}')
    print_success "File ready: $CLAUDE_DEB_FILE ($FILESIZE)"
else
    print_error "Download verification failed"
    exit 1
fi
echo ""

#############################################################################
# STEP 5: Install Claude Desktop
#############################################################################
print_step "Installing Claude Desktop..."

print_info "Installing package..."
sudo dpkg -i "$CLAUDE_DEB_FILE" > /dev/null 2>&1 || true

print_info "Installing dependencies..."
sudo apt install -f -y > /dev/null 2>&1

print_success "Claude Desktop installed"
echo ""

#############################################################################
# STEP 6: Setup SSH Keys
#############################################################################
print_step "Setting up SSH keys..."

mkdir -p "$SSH_DIR"
chmod 700 "$SSH_DIR"
print_success "SSH directory ready: $SSH_DIR"

if [ ! -f "$SSH_KEY" ]; then
    print_info "Generating SSH key pair..."
    ssh-keygen -t rsa -b 4096 -f "$SSH_KEY" -N "" -C "$(whoami)@$(hostname)" > /dev/null 2>&1
    print_success "SSH key generated"
else
    print_warning "SSH key already exists"
fi

chmod 600 "$SSH_KEY"
chmod 644 "$SSH_KEY.pub"
print_success "SSH key permissions set correctly"
print_success "Private key: $SSH_KEY (600)"
print_success "Public key:  $SSH_KEY.pub (644)"
echo ""

#############################################################################
# STEP 7: Get SSH Connection Details
#############################################################################
print_step "Configure SSH server connection..."
echo ""

SSH_HOST="${SSH_HOST:-}"
SSH_PORT="${SSH_PORT:-22}"
SSH_USER="${SSH_USER:-}"

if [ -z "$SSH_HOST" ]; then
    read -p "Enter SSH host/IP address: " SSH_HOST
    echo ""
fi

if [ -z "$SSH_USER" ]; then
    read -p "Enter SSH username: " SSH_USER
    echo ""
fi

read -p "Enter SSH port (default 22): " SSH_PORT_INPUT
SSH_PORT="${SSH_PORT_INPUT:-22}"
echo ""

print_info "SSH Connection Configuration:"
echo "  Host: $SSH_HOST"
echo "  Port: $SSH_PORT"
echo "  User: $SSH_USER"
echo "  Key:  $SSH_KEY"
echo ""

#############################################################################
# STEP 8: Setup SSH Connection (Optional)
#############################################################################
print_step "Testing SSH connection..."

read -p "Test SSH connection now? (y/n): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    print_info "Testing connection to $SSH_USER@$SSH_HOST:$SSH_PORT..."
    
    if timeout 5 ssh -i "$SSH_KEY" -p "$SSH_PORT" -o StrictHostKeyChecking=no -o ConnectTimeout=5 "$SSH_USER@$SSH_HOST" "echo 'SSH test successful'" > /dev/null 2>&1; then
        print_success "SSH connection successful!"
    else
        print_warning "Could not connect. This might be expected if the server isn't set up yet."
        print_info "You can add your public key to the server later:"
        print_info "  ssh-copy-id -p $SSH_PORT $SSH_USER@$SSH_HOST"
    fi
else
    print_info "Skipping SSH test"
fi
echo ""

#############################################################################
# STEP 9: Create MCP Configuration
#############################################################################
print_step "Creating MCP configuration..."

mkdir -p "$CONFIG_DIR"
chmod 755 "$CONFIG_DIR"
print_success "Config directory ready: $CONFIG_DIR"

if [ -f "$CONFIG_FILE" ]; then
    print_warning "Config file already exists. Creating backup..."
    cp "$CONFIG_FILE" "$CONFIG_FILE.backup.$(date +%s)"
    print_success "Backup created"
fi

cat > "$CONFIG_FILE" << EOF
{
  "mcpServers": {
    "ssh-server": {
      "command": "$NPX_PATH",
      "args": [
        "-y",
        "$MCP_PACKAGE"
      ],
      "env": {
        "SSH_HOST": "$SSH_HOST",
        "SSH_PORT": "$SSH_PORT",
        "SSH_USER": "$SSH_USER",
        "SSH_PRIVATE_KEY_PATH": "$SSH_KEY"
      }
    }
  }
}
EOF

print_success "MCP configuration created"

# Verify JSON
if python3 -m json.tool "$CONFIG_FILE" > /dev/null 2>&1; then
    print_success "Configuration is valid JSON"
else
    print_error "Configuration file is not valid JSON"
    exit 1
fi
echo ""

#############################################################################
# STEP 10: Display Summary
#############################################################################
print_step "Installation Summary"
echo ""
echo -e "${GREEN}✓ Claude Desktop installed${NC}"
echo -e "${GREEN}✓ Node.js and npm ready${NC}"
echo -e "${GREEN}✓ SSH keys configured${NC}"
echo -e "${GREEN}✓ MCP SSH server configured${NC}"
echo ""

print_info "MCP Configuration:"
cat "$CONFIG_FILE" | python3 -m json.tool 2>/dev/null || cat "$CONFIG_FILE"
echo ""

#############################################################################
# STEP 11: Next Steps
#############################################################################
print_step "Next Steps"
echo ""
echo "1. Close Claude Desktop completely (if running)"
echo "   ${YELLOW}pkill -9 claude${NC}"
echo ""
echo "2. Start Claude Desktop from your applications menu"
echo ""
echo "3. Wait a moment for the MCP server to connect"
echo ""
echo "4. You should see 'ssh-server' available in Claude's tools"
echo ""

#############################################################################
# Helpful Commands
#############################################################################
echo ""
print_header "Useful Commands"
echo ""
echo "Check Claude Desktop status:"
echo "  ${YELLOW}ps aux | grep -i claude${NC}"
echo ""
echo "Kill Claude completely:"
echo "  ${YELLOW}pkill -9 claude${NC}"
echo ""
echo "Test SSH connection manually:"
echo "  ${YELLOW}ssh -i $SSH_KEY -p $SSH_PORT $SSH_USER@$SSH_HOST${NC}"
echo ""
echo "Add your SSH key to a server:"
echo "  ${YELLOW}ssh-copy-id -i $SSH_KEY -p $SSH_PORT $SSH_USER@$SSH_HOST${NC}"
echo ""
echo "View current MCP configuration:"
echo "  ${YELLOW}cat $CONFIG_FILE${NC}"
echo ""
echo "Check Claude logs:"
echo "  ${YELLOW}tail -50 ~/.config/Claude/logs/main.log${NC}"
echo ""
echo "Check MCP server logs:"
echo "  ${YELLOW}tail -50 ~/.config/Claude/logs/mcp-server-ssh-server.log${NC}"
echo ""

#############################################################################
# Cleanup
#############################################################################
print_header "Cleaning Up"
print_info "Removing temporary files..."
cd ~
rm -rf "$TEMP_DIR"
print_success "Cleanup complete"
echo ""

#############################################################################
# Final Message
#############################################################################
echo -e "${GREEN}╔════════════════════════════════════════╗${NC}"
echo -e "${GREEN}║  Installation Complete! 🎉             ║${NC}"
echo -e "${GREEN}║                                        ║${NC}"
echo -e "${GREEN}║  Claude Desktop + MCP SSH Ready        ║${NC}"
echo -e "${GREEN}╚════════════════════════════════════════╝${NC}"
echo ""
