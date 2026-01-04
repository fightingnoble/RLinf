# Docker Container Aliases Configuration

alias cdhome='cd /root'
alias gs='git status'
alias ll='ls -alF'
alias gpu_mem='nvidia-smi --query-gpu=memory.used,memory.total --format=csv,noheader,nounits'

# ===========================================
# Python Aliases
# ===========================================
alias python='python3'
alias pip='python3 -m pip'

# ===========================================
# Color Output Aliases
# ===========================================
alias grep='grep --color=auto'
alias fgrep='fgrep --color=auto'
alias egrep='egrep --color=auto'

# ===========================================
# Environment Variables
# ===========================================
export PATH="/opt/conda/bin:$PATH"
export EDITOR="vim"
export LANG=C.UTF-8
export PATH="/usr/local/bin:$PATH"

# ===========================================
# History Settings
# ===========================================
HISTSIZE=10000
SAVEHIST=10000
HISTFILE=~/.zsh_history

# ===========================================
# Completion Settings
# ===========================================
autoload -U compinit && compinit
zstyle ':completion:*' menu select
zstyle ':completion:*' matcher-list 'm:{a-zA-Z}={A-Za-z}'

# ===========================================
# Key Bindings
# ===========================================
bindkey '^[[A' history-search-backward
bindkey '^[[B' history-search-forward

