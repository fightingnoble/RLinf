#! /bin/bash

# Local download directory
# Assuming this script is sourced from requirements/install.sh
# SCRIPT_DIR is defined in install.sh as requirements/
WORKSPACE="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="${extrenal_repo:-${WORKSPACE}/docker/torch-2.6/repos}"

# Install system dependencies (apt-get)
install_system_deps() {
    echo "=== Checking System Dependencies ==="
    if ! command -v apt-get &> /dev/null; then
        echo "Skipping apt-get (not on Debian/Ubuntu)."
        return
    fi

    local sudo_cmd=""
    if [ "$EUID" -ne 0 ]; then
        sudo_cmd="sudo"
    fi

    echo "Updating apt..."
    $sudo_cmd apt-get update
    
    echo "Installing packages..."
    # List from Dockerfile
    $sudo_cmd apt-get install -y --no-install-recommends \
        git vim libibverbs-dev openssh-server sudo runit runit-systemd tmux \
        build-essential python3-dev cmake pkg-config iproute2 pciutils python3 python3-pip \
        wget unzip curl
    
    # Install Python 3.11 for embodied targets
    echo "Installing Python 3.11..."
    $sudo_cmd apt-get install -y --no-install-recommends \
        python3.11 python3.11-dev python3.11-venv python3.11-distutils
    
    # Set Python 3.11 as an alternative
    if command -v update-alternatives &> /dev/null; then
        $sudo_cmd update-alternatives --install /usr/bin/python python /usr/bin/python3.11 2
        echo "Python 3.11 installed and registered as alternative"
    fi
}

# Setup Python tools and Environment Variables
setup_build_env() {
    echo "=== Setting up Build Environment ==="
    
    # Pip Mirror (Session level)
    export PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.bfsu.edu.cn/pypi/web/simple}"
    
    # Upgrade core tools
    echo "Upgrading pip, setuptools, wheel, uv..."
    python3 -m pip install --upgrade pip setuptools wheel uv
    
    # Environment Variables from Dockerfile
    export HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"
    mkdir -p "$HF_HOME"
    
    # UV Settings
    export UV_DEFAULT_INDEX="${UV_DEFAULT_INDEX:-https://mirrors.bfsu.edu.cn/pypi/web/simple}"
    export UV_LINK_MODE="${UV_LINK_MODE:-symlink}"
    
    # UV Python Management Settings
    # Prevent uv from downloading managed Python versions from GitHub
    export UV_PYTHON_DOWNLOADS="${UV_PYTHON_DOWNLOADS:-never}"
    # Prefer system/conda python over managed ones
    export UV_PYTHON_PREFERENCE="${UV_PYTHON_PREFERENCE:-system}"
    
    # ManiSkill Settings
    # Skip download prompts (auto-confirm downloads)
    export MS_SKIP_ASSET_DOWNLOAD_PROMPT="${MS_SKIP_ASSET_DOWNLOAD_PROMPT:-1}"
    # Set asset directory (will be set per-venv if using venv)
    export MS_ASSET_DIR="${MS_ASSET_DIR:-$HOME/.maniskill}"
    # Disable network downloads if no network access (e.g., Docker with limited network)
    # Set MS_NO_NETWORK=1 to fail fast if assets are missing instead of attempting download
    export MS_NO_NETWORK="${MS_NO_NETWORK:-0}"
    
    echo "Environment variables exported:"
    echo "  PIP_INDEX_URL=$PIP_INDEX_URL"
    echo "  HF_HOME=$HF_HOME"
    echo "  UV_DEFAULT_INDEX=$UV_DEFAULT_INDEX"
    echo "  UV_LINK_MODE=$UV_LINK_MODE"
    echo "  UV_PYTHON_DOWNLOADS=$UV_PYTHON_DOWNLOADS"
    echo "  UV_PYTHON_PREFERENCE=$UV_PYTHON_PREFERENCE"
    echo "  MS_SKIP_ASSET_DOWNLOAD_PROMPT=$MS_SKIP_ASSET_DOWNLOAD_PROMPT"
    echo "  MS_ASSET_DIR=$MS_ASSET_DIR"
}

# Utility to mimic switch_env (optional installation)
install_switch_env() {
    local bin_dir="$HOME/.local/bin"
    mkdir -p "$bin_dir"
    local target="$bin_dir/switch_env"
    
    # Only install if not exists or force
    if [ ! -f "$target" ]; then
        echo "Creating switch_env utility at $target"
        cat <<'EOF' > "$target"
#!/bin/bash
# Local adaptation of switch_env
if [ -z "$1" ]; then
    echo "Usage: switch_env <path_to_venv_or_name>"
    exit 1
fi

TARGET_ENV="$1"

# Check if it's a direct path
if [ -d "$TARGET_ENV" ] && [ -f "$TARGET_ENV/bin/activate" ]; then
    source "$TARGET_ENV/bin/activate"
    return 0 2>/dev/null || exit 0
fi

# Check if it's in current directory
if [ -d "./$TARGET_ENV" ] && [ -f "./$TARGET_ENV/bin/activate" ]; then
    source "./$TARGET_ENV/bin/activate"
    return 0 2>/dev/null || exit 0
fi

echo "Could not find environment: $TARGET_ENV"
exit 1
EOF
        chmod +x "$target"
    fi
}

# Main entry point for env prep
prepare_docker_like_env() {
    install_system_deps
    setup_build_env
    install_switch_env
}

# Helper to add env vars to activate script (venv or conda)
add_env_var() {
    local name="$1"
    local value="$2"
    
    # Export in current session
    export "${name}=${value}"
    
    # Persist
    if [ "${USE_CURRENT_ENV:-0}" -eq 1 ]; then
        # Try to persist in conda if available
        # Check for conda-meta or etc/conda
        if [ -d "$VENV_DIR/conda-meta" ] || [ -d "$VENV_DIR/etc/conda" ]; then
            local act_dir="$VENV_DIR/etc/conda/activate.d"
            mkdir -p "$act_dir"
            local script_path="$act_dir/rlinf_vars.sh"
            echo "export ${name}=${value}" >> "$script_path"
            chmod +x "$script_path"
            echo "Added $name to Conda activation script: $script_path"
        else
            echo "Warning: Could not persist env var $name to activation script. Please manually export it." >&2
        fi
    else
        # Standard venv
        if [ -f "$VENV_DIR/bin/activate" ]; then
            echo "export ${name}=${value}" >> "$VENV_DIR/bin/activate"
        fi
    fi
}
