#! /bin/bash

# Local download directory
# Assuming this script is sourced from requirements/install.sh
# SCRIPT_DIR is defined in install.sh as requirements/
WORKSPACE="$(dirname "$SCRIPT_DIR")"
DOWNLOAD_DIR="${extrenal_repo:-${WORKSPACE}/docker/torch-2.6/repos}"


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

# Unified URL replacement function with debug logging
apply_url_replacements() {
    local target_file="$1"
    local repos_mapping="$2"
    
    if [ ! -f "$target_file" ]; then
        return 0
    fi

    local file_basename=$(basename "$target_file")
    
    # 1. Git URL Replacements with logging
    if [ -n "$repos_mapping" ]; then
        while IFS='|' read -r repo_name repo_path; do
            local local_url="file://${repo_path}"
            # Check if this repo is referenced in the file
            if grep -q "github\.com/[^/]*/${repo_name}" "$target_file" 2>/dev/null; then
                sed -i -E "s|git\+https://github\.com/[^/]+/${repo_name}(\.git)?(@[^[:space:]\"']*)?|${local_url}|g" "$target_file"
                echo -e "\033[32m[local-deps] using local repo ${repo_name} -> ${repo_path} in ${file_basename}\033[0m"
            fi
        done <<< "$repos_mapping"
    fi
    
    # Check for any remaining remote git URLs (fallback)
    if grep -q "git+https://" "$target_file" 2>/dev/null; then
        while IFS= read -r line; do
            if [[ "$line" =~ git\+https://github\.com/([^/]+)/([^/\.]+) ]]; then
                local org="${BASH_REMATCH[1]}"
                local repo="${BASH_REMATCH[2]}"
                echo -e "\033[33m[local-deps] remote fallback for repo ${repo} (not in local cache) in ${file_basename}\033[0m"
            fi
        done < <(grep "git+https://" "$target_file")
    fi

    # 2. Wheel URL Replacements with logging
    local temp_file
    temp_file=$(mktemp)
    while IFS= read -r line || [ -n "$line" ]; do
        if [[ "$line" =~ @[[:space:]]*https?://.*\.whl ]]; then
            local wheel_url
            wheel_url=$(echo "$line" | sed -E 's/.*@[[:space:]]*(https?:\/\/[^[:space:]]+).*/\1/')
            local local_path
            local_path=$(get_local_wheel_path "$wheel_url")
            if [[ "$local_path" != "$wheel_url" ]]; then
                # Use file:// protocol for local wheels
                echo "$line" | sed -E "s|@[[:space:]]*https?://[^[:space:]]+|@ file://${local_path}|" >> "$temp_file"
                echo -e "\033[32m[local-deps] using local wheel ${local_path} in ${file_basename}\033[0m"
            else
                echo "$line" >> "$temp_file"
                echo -e "\033[33m[local-deps] remote wheel fallback ${wheel_url} in ${file_basename}\033[0m"
            fi
        else
            echo "$line" >> "$temp_file"
        fi
    done < "$target_file"
    mv "$temp_file" "$target_file"
}

patch_all_files_for_install() {
    echo "=============================================="
    echo "[local-deps] Patching requirements and pyprojects"
    echo "=============================================="
    
    local repos_mapping
    repos_mapping=$(collect_local_repos)
    
    local files_to_patch=()

    # 1. Main pyproject.toml
    if [ -f "${WORKSPACE}/pyproject.toml" ]; then
        files_to_patch+=("${WORKSPACE}/pyproject.toml")
    fi

    # 2. requirements/*.txt
    while IFS= read -r txt; do
        files_to_patch+=("$txt")
    done < <(find "$SCRIPT_DIR" -name "*.txt")

    # 3. Local repos pyproject.toml
    if [ -d "$DOWNLOAD_DIR" ]; then
        while IFS= read -r pyproject; do
            files_to_patch+=("$pyproject")
        done < <(find "$DOWNLOAD_DIR" -maxdepth 2 -name "pyproject.toml")
    fi

    local patched_count=0
    for f in "${files_to_patch[@]}"; do
        # Backup if not exists
        if [ ! -f "${f}.backup" ]; then
            cp "$f" "${f}.backup"
        fi
        
        apply_url_replacements "$f" "$repos_mapping"
        
        # Save patched version for debugging
        cp "$f" "${f}.patched"
        
        patched_count=$((patched_count + 1))
    done
    
    echo "[local-deps] Patched $patched_count files."

    # Remove uv.lock to force re-resolution
    if [ -f "${WORKSPACE}/uv.lock" ]; then
        echo "[local-deps] Removing uv.lock"
        rm -f "${WORKSPACE}/uv.lock"
    fi
    echo "=============================================="
}

restore_all_backups() {
    echo ""
    echo "[local-deps] Restoring original files..."
    local restored_count=0
    
    local search_dirs=("$SCRIPT_DIR")
    if [ -d "$DOWNLOAD_DIR" ]; then search_dirs+=("$DOWNLOAD_DIR"); fi
    
    # Restore root pyproject
    if [ -f "${WORKSPACE}/pyproject.toml.backup" ]; then
        echo -e "\033[36m[local-deps] restoring main pyproject backup ${WORKSPACE}/pyproject.toml.backup -> ${WORKSPACE}/pyproject.toml\033[0m"
        mv "${WORKSPACE}/pyproject.toml.backup" "${WORKSPACE}/pyproject.toml"
        restored_count=$((restored_count + 1))
    fi
    
    # Restore others
    for search_dir in "${search_dirs[@]}"; do
        while IFS= read -r backup; do
            local original="${backup%.backup}"
            echo -e "\033[36m[local-deps] restoring backup ${backup} -> ${original}\033[0m"
            mv "$backup" "$original"
            restored_count=$((restored_count + 1))
        done < <(find "$search_dir" -name "*.backup" 2>/dev/null)
    done
    
    if [ "$restored_count" -gt 0 ]; then
        echo "[local-deps] Restored $restored_count file(s)."
    fi
    echo "[local-deps] Restore complete."
}

