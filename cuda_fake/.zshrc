# RLinf Docker Container Zsh Configuration
# This file is mounted into the container for enhanced shell experience

# RLinf Docker Container Zsh Configuration
# This file is mounted into the container at /root/.zshrc

# Auto-initialize environment on first run
INIT_FLAG="/root/.rlinf_docker_initialized"
if [ ! -f "$INIT_FLAG" ]; then
    echo "🔧 Initializing RLinf Docker environment..."
    if [ -f "/root/git_repo/RLinf/docker_init.sh" ]; then
        bash /root/git_repo/RLinf/docker_init.sh
        touch "$INIT_FLAG"
        echo "✓ Initialization completed. Restarting zsh..."
        exec /bin/zsh
    else
        echo "⚠️ docker_init.sh not found, continuing with basic setup..."
    fi
fi

# Oh My Zsh configuration (if available)
export ZSH="/root/.oh-my-zsh"
if [ -d "$ZSH" ]; then
    # Zsh plugins
    plugins=(
        git
        zsh-completions
        zsh-syntax-highlighting
        zsh-autosuggestions
        extract
        web-search
    )

    # Load Oh My Zsh
    source $ZSH/oh-my-zsh.sh
fi

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

# Environment variables
export PATH="/opt/conda/bin:$PATH"
export EDITOR="vim"
export LANG=C.UTF-8

# Git configuration
git config --global --add safe.directory '*'

# History settings
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=/root/.zsh_history

# Completion settings
autoload -U compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# Key bindings
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

# Color output for common commands
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

echo "🎉 Welcome to RLinf Docker Container!"
echo "💡 Useful commands:"
echo "  cdrl         - Go to RLinf workspace (/root/git_repo/RLinf)"
echo "  cdhome       - Go to home directory (/root)"
echo "  gs           - Git status"
echo "  ll           - Detailed file listing"
echo "  gpu_mem      - Show GPU memory usage"
echo "  proxy_en     - Enable proxy"
echo "  proxy_dis    - Disable proxy"
echo "  docker_init  - Manually run environment initialization"
echo ""

# Manual initialization command
alias docker_init='bash /root/git_repo/RLinf/docker_init.sh'
