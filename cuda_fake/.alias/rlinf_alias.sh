# ===========================================
# RLinf Specific Aliases and Functions
# ===========================================
alias cdrl='cd /root/git_repo/RLinf'

# ===========================================
# link_assets function - Link RLinf assets
# ===========================================
link_assets() {
    if [ -d /opt/assets/.maniskill ]; then
        if [ -d ~/.maniskill ]; then
            rm -rf ~/.maniskill
        fi
        ln -s /opt/assets/.maniskill ~/.maniskill
    fi
    if [ -d /opt/assets/.sapien ]; then
        if [ -d ~/.sapien ]; then
            rm -rf ~/.sapien
        fi
        ln -s /opt/assets/.sapien ~/.sapien
    fi
    mkdir -p ~/.cache
    if [ -d /opt/assets/.cache/openpi ]; then
        if [ -d ~/.cache/openpi ]; then
            rm -rf ~/.cache/openpi
        fi
        ln -s /opt/assets/.cache/openpi ~/.cache/openpi
    fi
}
