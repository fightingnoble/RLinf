#! /bin/bash

# Local download directory
# Assuming this script is sourced from requirements/install.sh
# SCRIPT_DIR is defined in install.sh as requirements/
WORKSPACE="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="${extrenal_repo:-${WORKSPACE}/docker/torch-2.6/repos}"

# Function to get local path for a git URL
get_local_git_path() {
    local git_url="$1"
    
    # Extract repository name using basename (simple and robust)
    # This handles https://..., git@..., and other formats automatically
    # It also strips the .git suffix if provided as the second argument
    local repo_name=$(basename "$git_url" .git)
    
    if [ -z "$repo_name" ] || [ "$repo_name" = "/" ] || [ "$repo_name" = "." ]; then
        echo "$git_url"
        return
    fi
    
    # Check if local directory exists (flat structure)
    local local_path="${DOWNLOAD_DIR}/${repo_name}"
    if [ -d "$local_path" ]; then
        echo "file://${local_path}"
    else
        echo "$git_url"
    fi
}

# Function to get local path for a wheel URL
get_local_wheel_path() {
    local wheel_url="$1"
    local filename=$(basename "$wheel_url")
    
    # Check if local wheel exists
    local local_path="${DOWNLOAD_DIR}/wheels/${filename}"
    if [ -f "$local_path" ]; then
        echo "${local_path}"
    else
        echo "$wheel_url"
    fi
}

# Function to create a modified requirements file with local paths
create_local_requirements() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ]; then
        echo "Error: Requirements file not found: $input_file"
        return 1
    fi
    
    # Copy original file
    cp "$input_file" "$output_file"
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then return; fi
    
    # Iterate over local git repos and replace in file
    for repo_path in "$DOWNLOAD_DIR"/*; do
        if [ -d "$repo_path" ] && [ "$(basename "$repo_path")" != "wheels" ]; then
            local repo_name=$(basename "$repo_path")
            local local_url="file://${repo_path}"
            
            # Replace git+https://.../repo_name.git or git+https://.../repo_name
            sed -i -E "s|git\+https://github\.com/[^/]+/${repo_name}(\.git)?|git+${local_url}|g" "$output_file"
        fi
    done
    
    # Handle wheels (keep existing logic or simplify?)
    # Keeping existing wheel logic for now as it's specific
    local temp_file=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ @[[:space:]]*https?://.*\.whl ]]; then
            local wheel_url=$(echo "$line" | sed -E 's/.*@[[:space:]]*(https?:\/\/[^[:space:]]+).*/\1/')
            local local_path=$(get_local_wheel_path "$wheel_url")
            
            if [[ "$local_path" != "$wheel_url" ]]; then
                local new_line=$(echo "$line" | sed -E "s|@[[:space:]]*https?://[^[:space:]]+|@ file://${local_path}|")
                echo "$new_line" >> "$temp_file"
            else
                echo "$line" >> "$temp_file"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$output_file"
    mv "$temp_file" "$output_file"
}

# Function to create a modified pyproject.toml with local paths
create_local_pyproject() {
    local input_file="$1"
    local output_file="$2"
    
    if [ ! -f "$input_file" ]; then
        echo "Error: pyproject.toml not found: $input_file"
        return 1
    fi
    
    # Copy original file
    cp "$input_file" "$output_file"
    
    if [ ! -d "$DOWNLOAD_DIR" ]; then return; fi
    
    # Iterate over local git repos and replace in file
    # This matches git+https://github.com/ORG/REPO.git or .../REPO
    for repo_path in "$DOWNLOAD_DIR"/*; do
        if [ -d "$repo_path" ] && [ "$(basename "$repo_path")" != "wheels" ]; then
            local repo_name=$(basename "$repo_path")
            local local_url="file://${repo_path}"
            
            sed -i -E "s|git\+https://github\.com/[^/]+/${repo_name}(\.git)?|git+${local_url}|g" "$output_file"
        fi
    done
}

# Wrapper for uv sync to use local deps
uv_sync_wrapper() {
    local args=("$@")
    # Handle pyproject.toml with local git repositories
    local PYPROJECT_BACKUP="${WORKSPACE}/pyproject.toml.backup"
    if [ -f "${WORKSPACE}/pyproject.toml" ]; then
        # Create backup
        cp "${WORKSPACE}/pyproject.toml" "$PYPROJECT_BACKUP"
        # Create modified version with local paths
        local TEMP_PYPROJECT=$(mktemp)
        create_local_pyproject "${WORKSPACE}/pyproject.toml" "$TEMP_PYPROJECT"
        cp "$TEMP_PYPROJECT" "${WORKSPACE}/pyproject.toml"
        rm -f "$TEMP_PYPROJECT"
        
        # Debug: Show what was replaced
        echo "=== Local path replacements in pyproject.toml ==="
        grep -E "git\+file://" "${WORKSPACE}/pyproject.toml" || echo "No local git paths found"
        echo "=================================================="
    fi
    
    # Remove lock file to force uv to re-resolve dependencies with new URLs
    if [ -f "${WORKSPACE}/uv.lock" ]; then
        echo "Removing uv.lock to force dependency re-resolution..."
        rm -f "${WORKSPACE}/uv.lock"
    fi

    UV_TORCH_BACKEND=auto uv sync "${args[@]}"

    # Restore original pyproject.toml if backup exists
    if [ -f "$PYPROJECT_BACKUP" ]; then
        mv "$PYPROJECT_BACKUP" "${WORKSPACE}/pyproject.toml"
    fi
}

# Function to clone or copy from local
clone_or_copy_repo() {
    local git_url="$1"
    local target_dir="$2"
    local branch="${3:-}"
    local depth="${4:-}"
    
    local local_path=$(get_local_git_path "$git_url")
    local_path="${local_path#file://}"
    
    if [[ "$local_path" == "/"* ]]; then
        # Local path
        echo "Using local repository: $local_path -> $target_dir"
        if [ ! -d "$target_dir" ]; then
             mkdir -p "$(dirname "$target_dir")"
             # Use cp -a to preserve attributes
             cp -a "$local_path" "$target_dir"
        fi
        # Try to checkout branch if specified
        if [ -n "$branch" ] && [ -d "$target_dir/.git" ]; then
             (cd "$target_dir" && git checkout "$branch" 2>/dev/null || echo "Warning: Could not checkout branch $branch" && cd - >/dev/null)
        fi
    else
        # Remote clone
        if [ ! -d "$target_dir" ]; then
            local clone_cmd="git clone"
            if [ -n "$branch" ]; then clone_cmd="$clone_cmd -b $branch"; fi
            if [ -n "$depth" ]; then clone_cmd="$clone_cmd --depth $depth"; fi
            echo "Cloning from remote: $git_url -> $target_dir"
            $clone_cmd "$git_url" "$target_dir"
        fi
    fi
}

# Wrapper to install pip requirements with local paths
uv_pip_install_wrapper() {
    local req_file="$1"
    shift
    local args=("$@")
    
    local TEMP_REQ=$(mktemp)
    create_local_requirements "$req_file" "$TEMP_REQ"
    
    # Special Apex handling for reason target
    if [[ "$req_file" == *"megatron.txt"* ]]; then
        local APEX_WHEEL_URL="https://github.com/RLinf/apex/releases/download/25.09/apex-0.1-cp311-cp311-linux_x86_64.whl"
        local LOCAL_APEX=$(get_local_wheel_path "$APEX_WHEEL_URL")
        if [[ "$LOCAL_APEX" != "$APEX_WHEEL_URL" ]]; then
             sed -i "s|apex @ .*|apex @ file://${LOCAL_APEX}|" "$TEMP_REQ"
        fi
    fi

    UV_TORCH_BACKEND=auto uv pip install -r "$TEMP_REQ" "${args[@]}"
    rm -f "$TEMP_REQ"
}

# Helper to prefer local wheel for specific packages
install_local_wheel_if_exists() {
    local wheel_url="$1"
    local local_wheel=$(get_local_wheel_path "$wheel_url")
    uv pip install "$local_wheel"
}

# --- Dockerfile Compatibility Layer ---

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
    
    echo "Environment variables exported:"
    echo "  PIP_INDEX_URL=$PIP_INDEX_URL"
    echo "  HF_HOME=$HF_HOME"
    echo "  UV_DEFAULT_INDEX=$UV_DEFAULT_INDEX"
    echo "  UV_LINK_MODE=$UV_LINK_MODE"
    echo "  UV_PYTHON_DOWNLOADS=$UV_PYTHON_DOWNLOADS"
    echo "  UV_PYTHON_PREFERENCE=$UV_PYTHON_PREFERENCE"
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

