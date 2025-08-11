
#!/bin/bash

# Complete Nerd Font Installation Script for BonsaiFetch
# Installs all necessary fonts and dependencies for perfect icon display
# Compatible with Ubuntu/Debian systems

set -e

# Colors
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
MAGENTA='\033[0;35m'
BOLD='\033[1m'
NC='\033[0m'

print_banner() {
    echo -e "${CYAN}"
    echo "╔═══════════════════════════════════╗"
    echo "║  Nerd Font Complete Installation  ║"
    echo "║  Fix Missing Icons in BonsaiFetch ║"
    echo "╚═══════════════════════════════════╝"
    echo -e "${NC}"
}

print_status() { echo -e "${GREEN}[✓]${NC} $1"; }
print_info() { echo -e "${BLUE}[ℹ]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[⚠]${NC} $1"; }
print_error() { echo -e "${RED}[✗]${NC} $1"; }
print_step() { echo -e "${MAGENTA}[STEP]${NC} $1"; }

# Check if running as root
check_root() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run as root (use sudo)"
        echo "Usage: sudo $0"
        exit 1
    fi
}

# Update system packages
update_system() {
    print_step "Updating system packages..."
    apt update -qq
    apt install -y wget curl unzip fontconfig
    print_status "System packages updated"
}

# Install font dependencies
install_font_dependencies() {
    print_step "Installing font management dependencies..."
    
    # Essential packages for font handling
    apt install -y \
        fontconfig \
        fonts-powerline \
        fonts-font-awesome \
        fonts-noto \
        fonts-noto-color-emoji \
        fonts-dejavu \
        fonts-liberation \
        ttf-mscorefonts-installer
    
    print_status "Font dependencies installed"
}

# Download and install CaskaydiaCove Nerd Font
install_caskaydia_cove() {
    print_step "Installing CaskaydiaCove Nerd Font (primary font for BonsaiFetch)..."
    
    # Create fonts directory
    mkdir -p /usr/local/share/fonts/nerdfonts
    
    # Download CaskaydiaCove Nerd Font
    cd /tmp
    wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/CascadiaCode.zip" -O CascadiaCode.zip
    
    # Extract and install
    unzip -q CascadiaCode.zip -d CascadiaCode/
    cp CascadiaCode/*.ttf /usr/local/share/fonts/nerdfonts/
    
    # Cleanup
    rm -rf CascadiaCode/ CascadiaCode.zip
    
    print_status "CaskaydiaCove Nerd Font installed"
}

# Install additional essential Nerd Fonts
install_additional_nerdfonts() {
    print_step "Installing additional Nerd Fonts for maximum compatibility..."
    
    cd /tmp

    wget http://ftp.us.debian.org/debian/pool/main/f/fonts-firacode/fonts-firacode_6.2-3_all.deb
    sudo dpkg --force-all -i fonts-firacode_6.2-3_all.deb 
    sudo apt install -f -y
    
    # JetBrainsMono Nerd Font (excellent for terminals)
    print_info "Installing JetBrainsMono Nerd Font..."
    wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/JetBrainsMono.zip" -O JetBrainsMono.zip
    unzip -q JetBrainsMono.zip -d JetBrainsMono/
    cp JetBrainsMono/*.ttf /usr/local/share/fonts/nerdfonts/ 2>/dev/null || true
    rm -rf JetBrainsMono/ JetBrainsMono.zip
    
    # FiraCode Nerd Font (popular coding font)
    print_info "Installing FiraCode Nerd Font..."
    wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/FiraCode.zip" -O FiraCode.zip
    unzip -q FiraCode.zip -d FiraCode/
    cp FiraCode/*.ttf /usr/local/share/fonts/nerdfonts/ 2>/dev/null || true
    rm -rf FiraCode/ FiraCode.zip
    
    # Hack Nerd Font (great fallback)
    print_info "Installing Hack Nerd Font..."
    wget -q "https://github.com/ryanoasis/nerd-fonts/releases/download/v3.1.1/Hack.zip" -O Hack.zip
    unzip -q Hack.zip -d Hack/
    cp Hack/*.ttf /usr/local/share/fonts/nerdfonts/ 2>/dev/null || true
    rm -rf Hack/ Hack.zip
    
    print_status "Additional Nerd Fonts installed"
}

# Install system emoji fonts
install_emoji_fonts() {
    print_step "Installing emoji and symbol fonts..."
    
    # Install comprehensive emoji support
    apt install -y \
        fonts-noto-color-emoji \
        fonts-symbola \
        fonts-ancient-scripts \
        fonts-dejavu-core \
        fonts-dejavu-extra
    
    print_status "Emoji and symbol fonts installed"
}

# Update font cache
update_font_cache() {
    print_step "Updating system font cache..."
    
    # Rebuild font cache for all users
    fc-cache -f -v >/dev/null 2>&1
    
    # Update font cache for current user if running in user session
    if [[ -n "$SUDO_USER" ]]; then
        sudo -u "$SUDO_USER" fc-cache -f -v >/dev/null 2>&1
    fi
    
    print_status "Font cache updated"
}

# Test installed fonts
test_fonts() {
    print_step "Testing installed fonts and icons..."
    
    echo ""
    print_info "Available Nerd Fonts:"
    fc-list | grep -i "nerd\|cascadia\|caskaydia\|jetbrains\|fira\|hack" | cut -d: -f2 | sort | uniq | head -10
    
    echo ""
    print_info "Testing BonsaiFetch icons:"
    echo "󰇅 󰅐 󰍛 󰋊 󰩟 󰏖 󰓡 - hostname, uptime, GPU, disk, network, packages, RAM"
    
    echo ""
    print_info "Testing system icons:"
    echo "     - OS, kernel, CPU, shell, terminal"
    
    echo ""
    print_info "Testing additional symbols:"
    echo "← → ↑ ↓ ✓ ✗ ★ ☆ ♦ ♠ ♣ ♥"
    
    print_status "Font testing complete"
}

# Configure terminal recommendations
show_terminal_config() {
    echo ""
    print_step "Terminal Configuration Recommendations"
    echo ""
    
    print_info "To ensure all icons display properly:"
    echo ""
    echo "1. 🎯 SET TERMINAL FONT:"
    echo "   In your terminal preferences, set font to one of:"
    echo "   • CaskaydiaCove Nerd Font (recommended for BonsaiFetch)"
    echo "   • JetBrainsMono Nerd Font"
    echo "   • FiraCode Nerd Font"
    echo "   • Hack Nerd Font"
    echo ""
    
    echo "2. 📐 TERMINAL SETTINGS:"
    echo "   • Font size: 11-14pt recommended"
    echo "   • Enable: Allow bold text"
    echo "   • Ensure: UTF-8 encoding"
    echo ""
    
    echo "3. 🔧 FOR SPECIFIC TERMINALS:"
    echo ""
    echo "   GNOME Terminal:"
    echo "   gnome-terminal → Preferences → Profiles → Edit → Text"
    echo "   → Custom font → CaskaydiaCove Nerd Font Regular"
    echo ""
    
    echo "   Terminator:"
    echo "   Right-click → Preferences → Profiles → General → Font"
    echo "   → CaskaydiaCove Nerd Font Regular"
    echo ""
    
    echo "   Xfce Terminal:"
    echo "   Edit → Preferences → Appearance → Font"
    echo "   → CaskaydiaCove Nerd Font Regular"
    echo ""
    
    echo "   VS Code Integrated Terminal:"
    echo "   Settings → Terminal › Integrated: Font Family"
    echo "   → 'CaskaydiaCove Nerd Font', monospace"
    echo ""
    
    echo "4. 🔄 AFTER CHANGING FONT:"
    echo "   • Close and reopen terminal"
    echo "   • Test icons: echo \"󰇅 󰅐 󰍛 󰋊 󰩟 󰏖\""
    echo "   • Run BonsaiFetch test again"
}

# Create font test script
create_font_test() {
    print_step "Creating font test script..."
    
    cat > "/usr/local/bin/test-nerd-fonts" << 'FONT_TEST'
#!/bin/bash

echo "╔════════════════════════════════════════════════════════════╗"
echo "║                  Nerd Font Icon Test                      ║"
echo "╚════════════════════════════════════════════════════════════╝"
echo ""

echo "🎯 BonsaiFetch Essential Icons:"
echo "󰇅 󰅐 󰍛 󰋊 󰩟 󰏖 󰓡 - hostname, uptime, GPU, disk, network, packages, RAM"
echo ""

echo "🖥️  System Icons:"
echo "     - OS, kernel, CPU, shell, terminal"
echo ""

echo "🔧 Additional Icons:"
echo "          - load, processes, sensors, battery, display"
echo ""

echo "✨ Decorative:"
echo "← → ↑ ↓ ✓ ✗ ★ ☆ ♦ ♠ ♣ ♥ ○ ● ◆ ◇ ▪ ▫ ■ □"
echo ""

echo "📊 Box Drawing:"
echo "╭─╮ ├─┤ ╰─╯ ┌─┐ └─┘ ╔═╗ ╚═╝"
echo ""

if fc-list | grep -qi "nerd\|cascadia"; then
    echo "✅ Nerd Font detected - icons should display properly"
else
    echo "❌ No Nerd Font detected - please install fonts"
fi

echo ""
echo "Current terminal font info:"
echo "TERM: $TERM"
echo ""
echo "Run this test after changing your terminal font to verify icon display."
FONT_TEST

    chmod +x "/usr/local/bin/test-nerd-fonts"
    print_status "Font test script created: test-nerd-fonts"
}

# Main installation process
main() {
    print_banner
    
    check_root
    
    echo -e "${YELLOW}🎨 This script will install comprehensive Nerd Font support for BonsaiFetch${NC}"
    echo ""
    echo "What will be installed:"
    echo "• CaskaydiaCove Nerd Font (primary)"
    echo "• JetBrainsMono Nerd Font"  
    echo "• FiraCode Nerd Font"
    echo "• Hack Nerd Font"
    echo "• Emoji and symbol fonts"
    echo "• Font management tools"
    echo ""
    
    read -p "Continue with font installation? [Y/n]: " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Nn]$ ]]; then
        print_info "Installation cancelled"
        exit 0
    fi
    
    echo ""
    print_info "🚀 Starting comprehensive font installation..."
    echo ""
    
    # Installation steps
    update_system
    install_font_dependencies
    install_caskaydia_cove
    install_additional_nerdfonts
    install_emoji_fonts
    update_font_cache
    create_font_test
    
    # Show results
    echo ""
    print_status "🎉 Font installation completed successfully!"
    echo ""
    
    test_fonts
    show_terminal_config
    
    echo ""
    print_info "🔄 NEXT STEPS:"
    echo ""
    echo "1. Configure your terminal font (see recommendations above)"
    echo "2. Close and reopen your terminal"
    echo "3. Test fonts: test-nerd-fonts"
    echo "4. Re-run BonsaiFetch icon test"
    echo "5. Enjoy perfect BonsaiFetch display!"
    echo ""
    
    print_warning "⚠️  You MUST restart your terminal and set the font before icons will work!"
    echo ""
}

# Run the main function
main "$@"
