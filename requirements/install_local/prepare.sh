#! /bin/bash

# Local download directory
# Assuming this script is sourced from requirements/install.sh
# SCRIPT_DIR is defined in install.sh as requirements/
# external_repo is set by docker_test.sh or defaults to repo-internal path
WORKSPACE="$(dirname "$SCRIPT_DIR")"

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
        python3-venv \
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

    # Load local configuration if exists (config.local.sh is in requirements/ directory)
    # SCRIPT_DIR is defined in install.sh as requirements/
    if [ -n "${SCRIPT_DIR:-}" ]; then
        if [ -f "${SCRIPT_DIR}/config.local.sh" ]; then
            source "${SCRIPT_DIR}/config.local.sh"
        elif [ -f "${SCRIPT_DIR}/../config.local.sh" ]; then
            source "${SCRIPT_DIR}/../config.local.sh"
        fi
    fi

    # Align external_repo with CACHE_DIR if only CACHE_DIR is provided
    if [ -z "${external_repo:-}" ] && [ -n "${CACHE_DIR:-}" ]; then
        export external_repo="$CACHE_DIR"
    fi

    # Determine Python command based on PYTHON_VERSION (set by install.sh)
    if [ -n "${PYTHON_VERSION:-}" ]; then
        if [[ "$PYTHON_VERSION" == *"/"* ]]; then
            # PYTHON_VERSION is a path
            PYTHON_CMD="$PYTHON_VERSION"
        else
            # PYTHON_VERSION is a version number, extract major.minor (e.g., 3.11 from 3.11.14)
            local py_major_minor
            py_major_minor=$(echo "$PYTHON_VERSION" | grep -oE '^[0-9]+\.[0-9]+')
            PYTHON_CMD="python${py_major_minor}"
        fi

        echo "Using Python: $PYTHON_CMD (version: $PYTHON_VERSION)"

        # Verify Python command exists
        if ! command -v "$PYTHON_CMD" &> /dev/null; then
            echo "Error: Python command '$PYTHON_CMD' not found" >&2
            echo "Available Python versions:" >&2
            ls -1 /usr/bin/python* 2>/dev/null || echo "  None found in /usr/bin" >&2
            exit 1
        fi

        # Display actual Python version
        echo "Python version check: $("$PYTHON_CMD" --version 2>&1)"
        export PYTHON_CMD  # Export for use in other functions
    else
        # Fallback to python3 if PYTHON_VERSION not set
        PYTHON_CMD="python3"
        echo "PYTHON_VERSION not set, using default python3"
        export PYTHON_CMD
    fi

    # CUDA variant configuration for PyTorch installation
    # Supported values: cuda124 (default), cuda121
    # Note: CUDA 12.1 uses PyTorch cu118 (no cu121 available)
    export CUDA_VARIANT="${CUDA_VARIANT:-cuda124}"
    
    # Determine PyTorch CUDA index based on CUDA variant
    case "$CUDA_VARIANT" in
        cuda124)
            TORCH_CUDA_TAG="cu124"
            PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu124"
            ;;
        cuda121)
            # PyTorch doesn't have cu121, use cu118 for CUDA 12.1 compatibility
            TORCH_CUDA_TAG="cu118"
            PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu118"
            ;;
        *)
            echo "Warning: Unknown CUDA_VARIANT '$CUDA_VARIANT', defaulting to cuda124"
            TORCH_CUDA_TAG="cu124"
            PYTORCH_INDEX_URL="https://download.pytorch.org/whl/cu124"
            ;;
    esac
    
    export TORCH_CUDA_TAG
    export PYTORCH_INDEX_URL
    echo "CUDA variant: $CUDA_VARIANT (PyTorch tag: $TORCH_CUDA_TAG)"
    
    # Pip Mirror (Session level)
    # Can be overridden by config.local.sh
    export PIP_INDEX_URL="${PIP_INDEX_URL:-https://mirrors.bfsu.edu.cn/pypi/web/simple}"
    
    # UV configuration for PyTorch installation
    export UV_EXTRA_INDEX_URL="$PYTORCH_INDEX_URL"
    export UV_INDEX_STRATEGY="unsafe-best-match"

    # Upgrade core tools using the selected Python
    echo "Upgrading pip, setuptools, wheel, uv..."
    "$PYTHON_CMD" -m pip install --upgrade pip setuptools wheel uv
    
    # Environment Variables from Dockerfile
    export HF_HOME="${HF_HOME:-$HOME/.cache/huggingface}"
    mkdir -p "$HF_HOME"
    
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
