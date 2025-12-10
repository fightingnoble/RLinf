# Patch requirement file (backup + local replacements)
patch_requirement_file() {
    local req_file="$1"
    if [ ! -f "$req_file" ]; then
        return 1
    fi
    cp "$req_file" "${req_file}.backup"
    apply_git_url_replacements_ondemand "$req_file"
    apply_wheel_url_replacements "$req_file"
    return 0
}

# Patch a list of requirement files once at startup
patch_all_requirements_for_install() {
    local files=("$@")
    if [ "${#files[@]}" -eq 0 ]; then
        return 0
    fi
    local patched=0
    for f in "${files[@]}"; do
        if patch_requirement_file "$f"; then
            patched=1
            echo "[local-deps]   - Patched requirements: $f"
        fi
    done
    if [ "$patched" -eq 1 ]; then
        echo "[local-deps] Requirements patched"
    fi
}

# Restore requirement files from backup
restore_all_requirements() {
    local files=("$@")
    if [ "${#files[@]}" -eq 0 ]; then
        return 0
    fi
    local restored=0
    for f in "${files[@]}"; do
        if [ -f "${f}.backup" ]; then
            echo -e "\033[36m[local-deps] restoring requirements backup ${f}.backup -> ${f}\033[0m"
            mv "${f}.backup" "$f"
            restored=$((restored + 1))
        fi
    done
    if [ "$restored" -gt 0 ]; then
        echo "[local-deps]   - Restored $restored requirements file(s)"
    fi
}
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

# Collect all local repos mapping: repo_name -> local_path
# Output format: one "repo_name|local_path" per line
collect_local_repos() {
    if [ ! -d "$DOWNLOAD_DIR" ]; then
        return 0
    fi
    
    for repo_path in "$DOWNLOAD_DIR"/*; do
        if [ -d "$repo_path" ] && [ "$(basename "$repo_path")" != "wheels" ] && [ "$(basename "$repo_path")" != "assets" ]; then
            local repo_name=$(basename "$repo_path")
            echo "${repo_name}|${repo_path}"
        fi
    done
}

# Apply git URL replacements to a file using pre-collected repos mapping
# Args: target_file, repos_mapping (output from collect_local_repos)
apply_git_url_replacements() {
    local target_file="$1"
    local repos_mapping="$2"
    
    if [ ! -f "$target_file" ]; then
        return 0
    fi
    
    if [ -z "$repos_mapping" ]; then
        return 0
    fi
    
    # Apply each repo's replacement
    while IFS='|' read -r repo_name repo_path; do
        local local_url="file://${repo_path}"
        if grep -qE "git\+https://github\.com/.*/${repo_name}(\.git)?(@[^\"']*)?" "$target_file"; then
            echo -e "\033[32m[local-deps] using local repo ${repo_name} -> ${repo_path} in ${target_file}\033[0m"
            sed -i -E "s|git\+https://github\.com/[^/]+/${repo_name}(\.git)?(@[^\"']*)?|${local_url}|g" "$target_file"
        else
            echo -e "\033[33m[local-deps] remote fallback for repo ${repo_name} (not referenced) in ${target_file}\033[0m"
        fi
    done <<< "$repos_mapping"
}

# Apply git URL replacements by on-demand lookup (single file processing)
apply_git_url_replacements_ondemand() {
    local target_file="$1"

    if [ ! -f "$target_file" ]; then
        return 0
    fi

    local temp_file
    temp_file=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ git\+https://[^[:space:]]+ ]]; then
            local git_url
            git_url=$(echo "$line" | grep -oE 'git\+https://[^[:space:]]+')
            local clean_url="${git_url#git+}"
            local local_path
            local_path=$(get_local_git_path "$clean_url")
            if [[ "$local_path" == file://* ]]; then
                echo -e "\033[32m[local-deps] using local repo ${local_path} in ${target_file}\033[0m"
                # Escape special chars in git_url for sed
                local escaped_git_url=$(echo "$git_url" | sed 's/[+]/\\&/g')
                line=$(echo "$line" | sed -E "s|${escaped_git_url}(@[^[:space:]]*)?|git+${local_path}|g")
            else
                echo -e "\033[33m[local-deps] remote fallback for ${clean_url} in ${target_file}\033[0m"
            fi
        fi
        echo "$line" >> "$temp_file"
    done < "$target_file"
    mv "$temp_file" "$target_file"
}

# Apply wheel URL replacements in-place for a target file
apply_wheel_url_replacements() {
    local target_file="$1"

    if [ ! -f "$target_file" ]; then
        return 0
    fi

    local temp_file
    temp_file=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ @[[:space:]]*https?://.*\.whl ]]; then
            local wheel_url
            wheel_url=$(echo "$line" | sed -E 's/.*@[[:space:]]*(https?:\/\/[^[:space:]]+).*/\1/')
            local local_path
            local_path=$(get_local_wheel_path "$wheel_url")
            if [[ "$local_path" != "$wheel_url" ]]; then
                echo -e "\033[32m[local-deps] using local wheel ${local_path} in ${target_file}\033[0m"
                echo "$line" | sed -E "s|@[[:space:]]*https?://[^[:space:]]+|@ file://${local_path}|" >> "$temp_file"
            else
                echo -e "\033[33m[local-deps] remote wheel fallback ${wheel_url} in ${target_file}\033[0m"
                echo "$line" >> "$temp_file"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$target_file"
    mv "$temp_file" "$target_file"
}

# Function to create a modified pyproject.toml with local paths
create_local_pyproject() {
    local input_file="$1"
    local output_file="$2"

    if [ ! -f "$input_file" ]; then
        echo "Error: pyproject.toml not found: $input_file" >&2
        return 1
    fi

    cp "$input_file" "$output_file"
    apply_git_url_replacements_ondemand "$output_file"
}

# Unified initialization: patch all pyproject.toml files and remove lock file
# Should be called ONCE at the beginning of install.sh
patch_all_pyprojects_for_install() {
    echo "=============================================="
    echo "[local-deps] Initializing local dependencies"
    echo "=============================================="
    
    # Collect repos mapping ONCE
    local repos_mapping
    repos_mapping=$(collect_local_repos)
    
    if [ -z "$repos_mapping" ]; then
        echo "[local-deps] No local repos found"
        echo "[local-deps] Initialization complete"
        echo "=============================================="
        echo ""
        return 0
    fi
    
    local patched_any=0
    
    # 1. Patch local repos
    if [ -n "${DOWNLOAD_DIR:-}" ] && [ -d "$DOWNLOAD_DIR" ]; then
        echo "[local-deps] Patching local repos..."
        while IFS= read -r pyproject; do
            if ! grep -q "git+https://" "$pyproject" 2>/dev/null; then
                continue
            fi
            
            local repo_name
            repo_name=$(basename "$(dirname "$pyproject")")
            cp "$pyproject" "${pyproject}.backup"
            apply_git_url_replacements "$pyproject" "$repos_mapping"
            echo "[local-deps]   - Patched $repo_name"
            patched_any=1
        done < <(find "$DOWNLOAD_DIR" -maxdepth 2 -name "pyproject.toml")
    fi
    
    # 2. Patch main project
    if [ -f "${WORKSPACE}/pyproject.toml" ]; then
        echo "[local-deps] Patching main pyproject.toml..."
        if grep -q "git+https://" "${WORKSPACE}/pyproject.toml" 2>/dev/null; then
            cp "${WORKSPACE}/pyproject.toml" "${WORKSPACE}/pyproject.toml.backup"
            apply_git_url_replacements "${WORKSPACE}/pyproject.toml" "$repos_mapping"
            echo "[local-deps]   - Patched main project"
            patched_any=1
        fi
    fi
    
    # 3. Remove lock and show debug info if anything was patched
    if [ "$patched_any" -eq 1 ]; then
        if [ -f "${WORKSPACE}/uv.lock" ]; then
            echo "[local-deps]   - Removing uv.lock to force dependency re-resolution"
            rm -f "${WORKSPACE}/uv.lock"
        fi
        
        if [ -f "${WORKSPACE}/pyproject.toml" ]; then
            echo ""
            echo "=== Local path replacements in main pyproject.toml ==="
            grep -E "file://" "${WORKSPACE}/pyproject.toml" | head -n 10 || echo "No local file:// paths found"
            local total_count
            total_count=$(grep -c "file://" "${WORKSPACE}/pyproject.toml" 2>/dev/null || echo "0")
            if [ "$total_count" -gt 10 ]; then
                echo "... and $((total_count - 10)) more"
            fi
            echo "======================================================="
        fi
    fi
    
    echo "[local-deps] Initialization complete"
    echo "=============================================="
    echo ""
}

# Restore all backed up pyproject.toml files
# Should be called at the end of install.sh
restore_all_pyprojects() {
    echo ""
    echo "[local-deps] Restoring original pyproject.toml files..."
    
    # Restore main project
    if [ -f "${WORKSPACE}/pyproject.toml.backup" ]; then
        echo -e "\033[36m[local-deps] restoring main pyproject backup ${WORKSPACE}/pyproject.toml.backup -> ${WORKSPACE}/pyproject.toml\033[0m"
        mv "${WORKSPACE}/pyproject.toml.backup" "${WORKSPACE}/pyproject.toml"
        echo "[local-deps]   - Restored main pyproject.toml"
    fi
    
    # Restore local repos
    if [ -d "$DOWNLOAD_DIR" ]; then
        local restored_count=0
        find "$DOWNLOAD_DIR" -maxdepth 2 -name "pyproject.toml.backup" | while read -r backup; do
            local original="${backup%.backup}"
            echo -e "\033[36m[local-deps] restoring repo pyproject backup ${backup} -> ${original}\033[0m"
            mv "$backup" "$original"
            restored_count=$((restored_count + 1))
        done
        if [ "$restored_count" -gt 0 ]; then
            echo "[local-deps]   - Restored $restored_count repo pyproject.toml file(s)"
        fi
    fi
    
    echo "[local-deps] Restore complete"
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

