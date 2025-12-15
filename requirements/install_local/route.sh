#! /bin/bash

# Local download directory
# Assuming this script is sourced from requirements/install.sh
# SCRIPT_DIR is defined in install.sh as requirements/
# external_repo is set by docker_test.sh or defaults to repo-internal path
WORKSPACE="$(dirname "$SCRIPT_DIR")"


# Function to get local path for a git URL
get_local_git_path() {
    local git_url="$1"
    
    # Remove @branch or @tag suffix if present
    # This ensures basename works correctly on URLs like .../repo.git@main
    local clean_url="${git_url%%@*}"
    
    # Extract repository name using basename (simple and robust)
    # This handles https://..., git@..., and other formats automatically
    # It also strips the .git suffix if provided as the second argument
    local repo_name=$(basename "$clean_url" .git)
    
    if [ -z "$repo_name" ] || [ "$repo_name" = "/" ] || [ "$repo_name" = "." ]; then
        echo "$git_url"
        return
    fi
    
    # Check if local directory exists (flat structure)
    local local_path="${external_repo}/${repo_name}"
    if [ -d "$local_path" ]; then
        echo "file://${local_path}"
    else
        echo "$git_url"
    fi
}

# Helper to prefer local wheel for specific packages
install_local_wheel_if_exists() {
    local wheel_url="$1"
    local local_wheel=$(get_local_wheel_path "$wheel_url")
    pip install "$local_wheel"
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

#=======================ASSET HELPERS=======================

# Smart asset deployment: use local cache if available, otherwise call download_assets.sh
deploy_maniskill_assets() {
    local target_dir="${1:-$VENV_DIR}"
    local local_assets_dir=""
    
    # Check for local assets cache
    if [ -n "${external_repo}" ] && [ -d "${external_repo}/assets" ]; then
        local_assets_dir="${external_repo}/assets"
    fi
    
    # If local cache exists, copy directly and skip download_assets.sh
    if [ -n "$local_assets_dir" ] && [ -d "$local_assets_dir/.maniskill" ] && [ -d "$local_assets_dir/.sapien" ]; then
        echo "[install] Deploying ManiSkill assets from local cache: $local_assets_dir"
        
        # ManiSkill assets
        export MS_ASSET_DIR="${target_dir}/.maniskill"
        mkdir -p "$MS_ASSET_DIR"
        cp -r "$local_assets_dir/.maniskill"/* "$MS_ASSET_DIR/"
        echo "[install] ✓ ManiSkill assets deployed"
        
        # SAPIEN PhysX assets
        export PHYSX_VERSION=105.1-physx-5.3.1.patch0
        export PHYSX_DIR="${target_dir}/.sapien/physx/${PHYSX_VERSION}"
        mkdir -p "$PHYSX_DIR"
        cp -r "$local_assets_dir/.sapien/physx/${PHYSX_VERSION}"/* "$PHYSX_DIR/"
        echo "[install] ✓ SAPIEN PhysX assets deployed"
        
        return 0
    else
        # Fallback: call download_assets.sh (network path, no --local-dir in v1.0)
        echo "[install] Local assets not found, using download_assets.sh (network)"
        bash $SCRIPT_DIR/embodied/download_assets.sh --assets maniskill --dir "$target_dir"
    fi
}

deploy_openpi_assets() {
    local target_dir="${1:-$VENV_DIR}"
    local local_assets_dir=""
    
    # Check for local assets cache
    if [ -n "${external_repo}" ] && [ -d "${external_repo}/assets" ]; then
        local_assets_dir="${external_repo}/assets"
    fi
    
    # If local cache exists, copy directly and skip download_assets.sh
    local local_tokenizer="${local_assets_dir}/.cache/openpi/big_vision/paligemma_tokenizer.model"
    if [ -n "$local_assets_dir" ] && [ -f "$local_tokenizer" ]; then
        echo "[install] Deploying OpenPI tokenizer from local cache: $local_assets_dir"
        
        export TOKENIZER_DIR="${target_dir}/.cache/openpi/big_vision/"
        mkdir -p "$TOKENIZER_DIR"
        cp "$local_tokenizer" "$TOKENIZER_DIR/"
        echo "[install] ✓ OpenPI tokenizer deployed"
        
        return 0
    else
        # Fallback: call download_assets.sh (network path, no --local-dir in v1.0)
        echo "[install] Local tokenizer not found, using download_assets.sh (network)"
        bash $SCRIPT_DIR/embodied/download_assets.sh --assets openpi --dir "$target_dir"
    fi
}
