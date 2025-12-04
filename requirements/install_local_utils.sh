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
             (cd "$target_dir" && git checkout "$branch" 2>/dev/null || echo "Warning: Could not checkout branch $branch")
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

