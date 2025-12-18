#!/bin/bash
# Docker Container Initialization Script for RLinf
# This script installs oh-my-zsh and plugins if not already present

set -e

echo "🔧 RLinf Docker Container Initialization"
echo "========================================"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Check if oh-my-zsh is already installed
if [ -d "/root/.oh-my-zsh" ]; then
    echo -e "${GREEN}✓ Oh My Zsh is already installed${NC}"
else
    echo -e "${BLUE}📦 Installing Oh My Zsh...${NC}"

    # Install oh-my-zsh with proxy support
    if [ -n "$https_proxy" ] || [ -n "$http_proxy" ]; then
        echo -e "${YELLOW}🌐 Using proxy for installation${NC}"
        PROXY_ENV=""
        if [ -n "$https_proxy" ]; then
            PROXY_ENV="$PROXY_ENV https_proxy=$https_proxy"
        fi
        if [ -n "$http_proxy" ]; then
            PROXY_ENV="$PROXY_ENV http_proxy=$http_proxy"
        fi

        # Install with proxy
        env $PROXY_ENV sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended || {
            echo -e "${RED}❌ Oh My Zsh installation failed, continuing without it${NC}"
        }
    else
        # Install without proxy
        sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended || {
            echo -e "${RED}❌ Oh My Zsh installation failed, continuing without it${NC}"
        }
    fi

    # Verify installation
    if [ -d "/root/.oh-my-zsh" ]; then
        echo -e "${GREEN}✓ Oh My Zsh installed successfully${NC}"
    else
        echo -e "${YELLOW}⚠️ Oh My Zsh installation may have failed${NC}"
    fi
fi

# Install zsh plugins
echo -e "${BLUE}🔌 Installing Zsh plugins...${NC}"

ZSH_CUSTOM="${ZSH_CUSTOM:-/root/.oh-my-zsh/custom}"
PLUGINS_DIR="$ZSH_CUSTOM/plugins"

# Create plugins directory if it doesn't exist
mkdir -p "$PLUGINS_DIR"

# Function to install plugin with proxy support
install_plugin() {
    local plugin_name=$1
    local repo_url=$2
    local plugin_dir="$PLUGINS_DIR/$plugin_name"

    if [ -d "$plugin_dir" ]; then
        echo -e "${GREEN}✓ $plugin_name is already installed${NC}"
        return 0
    fi

    echo -e "${BLUE}📥 Installing $plugin_name...${NC}"

    if [ -n "$https_proxy" ] || [ -n "$http_proxy" ]; then
        # Use proxy for git clone
        if [ -n "$https_proxy" ]; then
            git config --global http.proxy "$https_proxy"
            git config --global https.proxy "$https_proxy"
        fi

        if git clone "$repo_url" "$plugin_dir" 2>/dev/null; then
            echo -e "${GREEN}✓ $plugin_name installed successfully${NC}"
        else
            echo -e "${RED}❌ Failed to install $plugin_name${NC}"
        fi

        # Reset git proxy
        git config --global --unset http.proxy
        git config --global --unset https.proxy
    else
        # Clone without proxy
        if git clone "$repo_url" "$plugin_dir" 2>/dev/null; then
            echo -e "${GREEN}✓ $plugin_name installed successfully${NC}"
        else
            echo -e "${RED}❌ Failed to install $plugin_name${NC}"
        fi
    fi
}

# Install plugins
install_plugin "zsh-completions" "https://github.com/zsh-users/zsh-completions"
install_plugin "zsh-syntax-highlighting" "https://github.com/zsh-users/zsh-syntax-highlighting"
install_plugin "zsh-autosuggestions" "https://github.com/zsh-users/zsh-autosuggestions"

# Install additional useful plugins if desired
install_plugin "extract" "https://github.com/zsh-users/zsh-extract"  # for extract alias
install_plugin "web-search" "https://github.com/zsh-users/zsh-web-search"  # for web search aliases

echo -e "${BLUE}🔧 Configuring Zsh...${NC}"

# Ensure zshrc has the correct plugin configuration
ZSHRC="/root/.zshrc"
if [ -f "$ZSHRC" ]; then
    # Check if plugins line exists and update it
    if grep -q "^plugins=(" "$ZSHRC"; then
        # Update existing plugins line
        sed -i 's/^plugins=(.*)/plugins=(git zsh-completions zsh-syntax-highlighting zsh-autosuggestions extract web-search)/' "$ZSHRC"
        echo -e "${GREEN}✓ Updated plugins in .zshrc${NC}"
    else
        # Add plugins line if it doesn't exist
        echo "" >> "$ZSHRC"
        echo "# Zsh plugins" >> "$ZSHRC"
        echo "plugins=(git zsh-completions zsh-syntax-highlighting zsh-autosuggestions extract web-search)" >> "$ZSHRC"
        echo -e "${GREEN}✓ Added plugins to .zshrc${NC}"
    fi
else
    echo -e "${YELLOW}⚠️ .zshrc not found, creating basic configuration${NC}"
    cat > "$ZSHRC" << 'EOF'
# Basic Zsh configuration for RLinf Docker container
export ZSH="/root/.oh-my-zsh"

# Zsh plugins
plugins=(git zsh-completions zsh-syntax-highlighting zsh-autosuggestions extract web-search)

# Load Oh My Zsh if available
if [ -f $ZSH/oh-my-zsh.sh ]; then
    source $ZSH/oh-my-zsh.sh
fi

# Environment variables
export PATH="/opt/conda/bin:$PATH"
export EDITOR="vim"
export LANG=C.UTF-8

# Git configuration
git config --global --add safe.directory '*'

# Proxy aliases
alias proxy_en='export https_proxy="http://222.29.97.81:1080";export http_proxy="http://222.29.97.81:1080";git config --global http.proxy "http://222.29.97.81:1080";git config --global https.proxy "http://222.29.97.81:1080"'
alias proxy_dis='unset https_proxy;unset http_proxy;git config --global --unset http.proxy;git config --global --unset https.proxy'

# RLinf specific aliases
alias cdrl='cd /root/git_repo/RLinf'
alias cdhome='cd /root'
alias gs='git status'
alias ll='ls -alF'
alias gpu_mem='nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits'

# Python aliases
alias python='python3'
alias pip='python3 -m pip'

echo "🎉 Welcome to RLinf Docker Container!"
echo "💡 Useful commands:"
echo "  cdrl     - Go to RLinf workspace (/root/git_repo/RLinf)"
echo "  cdhome   - Go to home directory (/root)"
echo "  gs       - Git status"
echo "  ll       - Detailed file listing"
echo "  gpu_mem  - Show GPU memory usage"
echo "  proxy_en - Enable proxy"
echo "  proxy_dis- Disable proxy"
echo ""
EOF
    echo -e "${GREEN}✓ Created basic .zshrc configuration${NC}"
fi

# Set correct permissions
chmod 755 /root/.zshrc 2>/dev/null || true

echo ""
echo -e "${GREEN}🎉 Docker container initialization completed!${NC}"
echo ""
echo "Installed components:"
echo "  ✓ Oh My Zsh"
echo "  ✓ zsh-completions plugin"
echo "  ✓ zsh-syntax-highlighting plugin"
echo "  ✓ zsh-autosuggestions plugin"
echo "  ✓ extract plugin"
echo "  ✓ web-search plugin"
echo ""
echo "To start using zsh with all features, run:"
echo "  exec /bin/zsh"
echo ""
echo "Or simply exit and restart the container."

