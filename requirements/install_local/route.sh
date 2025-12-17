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
    uv pip install "$local_wheel"
}

# Detect CUDA tag for flash-attention wheel
# Flash-attention uses cu12 tag for all CUDA 12.x versions
# Priority: CUDA_VARIANT env var > system CUDA > default cu12
get_cuda_tag_for_flash_attn() {
    local cu_tag="cu12"  # Default to cu12 (most common)
    
    if [ -n "${CUDA_VARIANT:-}" ]; then
        # Extract CUDA major from CUDA_VARIANT (e.g., cuda124 -> 12, cuda121 -> 12)
        if [[ "$CUDA_VARIANT" =~ cuda12 ]]; then
            cu_tag="cu12"
        elif [[ "$CUDA_VARIANT" =~ cuda11 ]]; then
            cu_tag="cu11"
        fi
    else
        # Try to detect from system CUDA
        local system_cuda_major
        system_cuda_major=$(nvcc --version 2>/dev/null | grep -oP 'release \K[0-9]+' | head -1 || echo "")
        if [ -n "$system_cuda_major" ]; then
            if [ "$system_cuda_major" = "12" ]; then
                cu_tag="cu12"
            elif [ "$system_cuda_major" = "11" ]; then
                cu_tag="cu11"
            fi
        fi
    fi
    
    echo "$cu_tag"
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
        local ms_asset_dir="${target_dir}/.maniskill"
        mkdir -p "$ms_asset_dir"
        cp -r "$local_assets_dir/.maniskill"/* "$ms_asset_dir/"
        echo "[install] ✓ ManiSkill assets deployed to $ms_asset_dir"
        
        # Set MS_ASSET_DIR environment variable
        export MS_ASSET_DIR="$ms_asset_dir"
        
        # Persist MS_ASSET_DIR to virtual environment activate script
        local venv_dir="${target_dir}"
        if [ -f "${venv_dir}/bin/activate" ]; then
            # Remove old MS_ASSET_DIR setting if exists
            sed -i '/^export MS_ASSET_DIR=/d' "${venv_dir}/bin/activate"
            # Add new setting with absolute path
            local abs_ms_asset_dir
            if [[ "$ms_asset_dir" == /* ]]; then
                abs_ms_asset_dir="$ms_asset_dir"
            else
                abs_ms_asset_dir="$(cd "$(dirname "$ms_asset_dir")" && pwd)/$(basename "$ms_asset_dir")"
            fi
            echo "export MS_ASSET_DIR=\"${abs_ms_asset_dir}\"" >> "${venv_dir}/bin/activate"
            echo "[install] ✓ MS_ASSET_DIR=$abs_ms_asset_dir added to virtual environment: ${venv_dir}/bin/activate"
        else
            echo "[install] ⚠ Warning: Virtual environment activate script not found at ${venv_dir}/bin/activate"
        fi
        
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
