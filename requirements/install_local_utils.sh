#! /bin/bash

# Local download directory
# Assuming this script is sourced from requirements/install.sh
# SCRIPT_DIR is defined in install.sh as requirements/
WORKSPACE="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="${WORKSPACE}/docker/torch-2.6/repos"

# Function to get local path for a git URL
get_local_git_path() {
    local git_url="$1"
    local repo_name=""
    
    # Extract repository name from various URL formats
    if [[ "$git_url" =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
        local repo="${BASH_REMATCH[2]}"
        # Remove .git suffix if present
        repo="${repo%.git}"
        repo_name="${repo}"
    fi
    
    if [ -z "$repo_name" ]; then
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
    
    # Create temporary file with local paths
    > "$output_file"
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ @[[:space:]]*git\+https?:// ]]; then
            # Extract the git URL
            local git_url=$(echo "$line" | sed -E 's/.*@[[:space:]]*git\+([^[:space:]]+).*/\1/')
            local local_path=$(get_local_git_path "$git_url")
            # Replace git URL with local path
            local new_line=$(echo "$line" | sed -E "s|@[[:space:]]*git\+[^[:space:]]+|@ git+${local_path}|")
            echo "$new_line" >> "$output_file"
        elif [[ "$line" =~ @[[:space:]]*https?://.*\.whl ]]; then
            # Handle Wheel URL
            local wheel_url=$(echo "$line" | sed -E 's/.*@[[:space:]]*(https?:\/\/[^[:space:]]+).*/\1/')
            local local_path=$(get_local_wheel_path "$wheel_url")
            
            if [[ "$local_path" != "$wheel_url" ]]; then
                # Replace with file:// path
                local new_line=$(echo "$line" | sed -E "s|@[[:space:]]*https?://[^[:space:]]+|@ file://${local_path}|")
                echo "$new_line" >> "$output_file"
            else
                echo "$line" >> "$output_file"
            fi
        else
            # Not a git dependency, keep as is
            echo "$line" >> "$output_file"
        fi
    done < "$input_file"
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
    
    # Find and replace each git URL
    while IFS= read -r line; do
        if [[ "$line" =~ git\+https://github\.com/([^/]+)/([^/\"\']+) ]]; then
            local org="${BASH_REMATCH[1]}"
            local repo="${BASH_REMATCH[2]}"
            repo="${repo%.git}"  # Remove .git if present
            repo="${repo%\"}"    # Remove trailing quote if present
            repo="${repo%\'}"    # Remove trailing quote if present
            local git_url="https://github.com/${org}/${repo}.git"
            local local_path=$(get_local_git_path "$git_url")
            
            if [[ "$local_path" != "$git_url" ]]; then
                # Escape special characters for sed
                local escaped_git=$(echo "$git_url" | sed 's/[[\.*^$()+?{|]/\\&/g')
                local escaped_local=$(echo "$local_path" | sed 's/[[\.*^$()+?{|]/\\&/g')
                # Replace in file
                sed -i "s|git\+${escaped_git}|git+${escaped_local}|g" "$output_file"
            fi
        fi
    done < <(grep -E "git\+https://github\.com" "$output_file" || true)
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
    fi

    # Use different commands based on environment type
    if [ "${USE_CURRENT_ENV:-0}" -eq 1 ]; then
        # Conda/current env mode: use uv pip install instead of uv sync
        # Parse --extra arguments and convert to pip install syntax
        local extras=""
        local skip_next=0
        for arg in "${args[@]}"; do
            if [ "$skip_next" -eq 1 ]; then
                extras="${extras},${arg}"
                skip_next=0
            elif [ "$arg" = "--extra" ]; then
                skip_next=1
            fi
        done
        
        # Build install target
        local install_target="."
        if [ -n "$extras" ]; then
            # Remove leading comma
            extras="${extras#,}"
            install_target=".[${extras}]"
        fi
        
        cd "${WORKSPACE}"
        UV_TORCH_BACKEND=auto uv pip install -e "${install_target}"
    else
        # Standard venv mode: use uv sync
        UV_TORCH_BACKEND=auto uv sync "${args[@]}"
    fi

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
    
    echo "Environment variables exported:"
    echo "  PIP_INDEX_URL=$PIP_INDEX_URL"
    echo "  HF_HOME=$HF_HOME"
    echo "  UV_DEFAULT_INDEX=$UV_DEFAULT_INDEX"
    echo "  UV_LINK_MODE=$UV_LINK_MODE"
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
