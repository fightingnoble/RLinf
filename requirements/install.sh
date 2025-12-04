#! /bin/bash

TARGET="${1:-"openvla"}"
EMBODIED_TARGET=("openvla" "openvla-oft" "openpi")

# Get workspace directory (assuming script is in requirements/ subdirectory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/.." && pwd)"
DOWNLOAD_DIR="${WORKSPACE}/../download"

echo "Workspace: $WORKSPACE"
echo "Download directory: $DOWNLOAD_DIR"
if [ -d "$DOWNLOAD_DIR" ]; then
    echo "Download directory exists, will check for local repositories"
else
    echo "Download directory does not exist, will use remote repositories"
fi

# Function to get local path for a git URL
# Returns local path if exists, otherwise returns original URL
get_local_git_path() {
    local git_url="$1"
    local repo_name=""
    
    # Extract repository name from various URL formats
    if [[ "$git_url" =~ github\.com[:/]([^/]+)/([^/]+) ]]; then
        local org="${BASH_REMATCH[1]}"
        local repo="${BASH_REMATCH[2]}"
        # Remove .git suffix if present
        repo="${repo%.git}"
        repo_name="${org}/${repo}"
    fi
    
    if [ -z "$repo_name" ]; then
        echo "$git_url"
        return
    fi
    
    # Check if local directory exists
    local local_path="${DOWNLOAD_DIR}/${repo_name}"
    if [ -d "$local_path" ]; then
        echo "Found local repository: ${local_path}" >&2
        echo "file://${local_path}"
    else
        echo "Using remote repository: ${git_url}" >&2
        echo "$git_url"
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
        elif [[ "$line" =~ @[[:space:]]*git\+file:// ]]; then
            # Already a local path, keep as is
            echo "$line" >> "$output_file"
        else
            # Not a git dependency, keep as is
            echo "$line" >> "$output_file"
        fi
    done < "$input_file"
}

# Function to clone or copy from local
clone_or_copy_repo() {
    local git_url="$1"
    local target_dir="$2"
    local branch="${3:-}"
    
    local local_path=$(get_local_git_path "$git_url")
    
    if [[ "$local_path" =~ ^file:// ]]; then
        # Remove file:// prefix
        local_path="${local_path#file://}"
        echo "Using local repository: $local_path -> $target_dir"
        if [ -d "$target_dir" ]; then
            echo "Target directory already exists: $target_dir, skipping copy"
            # Still try to checkout branch if specified
            if [ -n "$branch" ] && [ -d "$target_dir/.git" ]; then
                cd "$target_dir" && git checkout "$branch" 2>/dev/null || echo "Warning: Could not checkout branch $branch" && cd -
            fi
        else
            mkdir -p "$(dirname "$target_dir")"
            # Use cp -a to preserve attributes and links
            cp -a "$local_path" "$target_dir"
            if [ -n "$branch" ] && [ -d "$target_dir/.git" ]; then
                cd "$target_dir" && git checkout "$branch" 2>/dev/null || echo "Warning: Could not checkout branch $branch" && cd -
            fi
        fi
    else
        # Use git clone
        echo "Cloning from remote: $git_url -> $target_dir"
        if [ -n "$branch" ]; then
            git clone -b "$branch" "$git_url" "$target_dir"
        else
            git clone "$git_url" "$target_dir"
        fi
    fi
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
            # Escape special characters for sed
            local escaped_git=$(echo "$git_url" | sed 's/[[\.*^$()+?{|]/\\&/g')
            local escaped_local=$(echo "$local_path" | sed 's/[[\.*^$()+?{|]/\\&/g')
            # Replace in file
            sed -i.tmp "s|git\+${escaped_git}|git+${escaped_local}|g" "$output_file"
            rm -f "${output_file}.tmp"
        fi
    done < <(grep -E "git\+https://github\.com" "$output_file" || true)
}

# Get the remaining args
while [ "$#" -gt 0 ]; do
    case "$2" in
        --enable-behavior)
            ENABLE_BEHAVIOR="true"
            shift
            ;;
        --test-build)
            TEST_BUILD="true"
            shift
            ;;
        *)
            break
            ;;
    esac
done

PYTHON_VERSION="3.11.10"
if [ "$ENABLE_BEHAVIOR" = "true" ]; then
    PYTHON_VERSION="3.10"
fi

# Behavior check
if [ "$ENABLE_BEHAVIOR" = "true" ] && [[ "$TARGET" != "openvla-oft" ]]; then
    echo "--enable-behavior can only be used with the openvla-oft target."
    exit 1
fi

# Common dependencies
# Activate existing conda environment
# Initialize conda for bash script
eval "$(conda shell.bash hook)"
conda activate rad_zhangchg

# Handle pyproject.toml with local git repositories
PYPROJECT_BACKUP="${WORKSPACE}/pyproject.toml.backup"
if [ -f "${WORKSPACE}/pyproject.toml" ]; then
    # Create backup
    cp "${WORKSPACE}/pyproject.toml" "$PYPROJECT_BACKUP"
    # Create modified version with local paths
    TEMP_PYPROJECT=$(mktemp)
    create_local_pyproject "${WORKSPACE}/pyproject.toml" "$TEMP_PYPROJECT"
    cp "$TEMP_PYPROJECT" "${WORKSPACE}/pyproject.toml"
    rm -f "$TEMP_PYPROJECT"
fi

UV_TORCH_BACKEND=auto uv sync

# Restore original pyproject.toml if backup exists
if [ -f "$PYPROJECT_BACKUP" ]; then
    mv "$PYPROJECT_BACKUP" "${WORKSPACE}/pyproject.toml"
fi

if [[ " ${EMBODIED_TARGET[*]} " == *" $TARGET "* ]]; then
    # Handle pyproject.toml with local git repositories for embodied extra
    if [ -f "${WORKSPACE}/pyproject.toml" ]; then
        cp "${WORKSPACE}/pyproject.toml" "$PYPROJECT_BACKUP"
        TEMP_PYPROJECT=$(mktemp)
        create_local_pyproject "${WORKSPACE}/pyproject.toml" "$TEMP_PYPROJECT"
        cp "$TEMP_PYPROJECT" "${WORKSPACE}/pyproject.toml"
        rm -f "$TEMP_PYPROJECT"
    fi
    uv sync --extra embodied
    if [ -f "$PYPROJECT_BACKUP" ]; then
        mv "$PYPROJECT_BACKUP" "${WORKSPACE}/pyproject.toml"
    fi
    uv pip uninstall pynvml
    bash requirements/install_embodied_deps.sh # Must be run after the above command
    mkdir -p /opt && clone_or_copy_repo "https://github.com/RLinf/LIBERO.git" "/opt/libero"
    mkdir -p $CONDA_PREFIX/etc/conda/activate.d
    echo "export PYTHONPATH=/opt/libero:\$PYTHONPATH" >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
    echo "export NVIDIA_DRIVER_CAPABILITIES=all" >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
    echo "export VK_DRIVER_FILES=/etc/vulkan/icd.d/nvidia_icd.json" >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
    echo "export VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json" >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
    chmod +x $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
fi

if [ "$TARGET" = "openvla" ]; then
    TEMP_REQ=$(mktemp)
    create_local_requirements "requirements/openvla.txt" "$TEMP_REQ"
    UV_TORCH_BACKEND=auto uv pip install -r "$TEMP_REQ" --no-build-isolation
    rm -f "$TEMP_REQ"
elif [ "$TARGET" = "openvla-oft" ]; then
    TEMP_REQ=$(mktemp)
    create_local_requirements "requirements/openvla_oft.txt" "$TEMP_REQ"
    UV_TORCH_BACKEND=auto uv pip install -r "$TEMP_REQ" --no-build-isolation
    rm -f "$TEMP_REQ"
    if [ "$ENABLE_BEHAVIOR" = "true" ]; then
        clone_or_copy_repo "https://github.com/RLinf/BEHAVIOR-1K.git" "/opt/BEHAVIOR-1K" "RLinf/v3.7.1"
        cd /opt/BEHAVIOR-1K && ./setup.sh --omnigibson --bddl --joylo --confirm-no-conda --accept-nvidia-eula && cd -
        uv pip uninstall flash-attn
        uv pip install https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.5cxx11abiFALSE-cp310-cp310-linux_x86_64.whl
        uv pip install ml_dtypes==0.5.3 protobuf==3.20.3
        pip install click==8.2.1
        cd && uv pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 && cd -
    fi
elif [ "$TARGET" = "openpi" ]; then
    TEMP_REQ=$(mktemp)
    create_local_requirements "requirements/openpi.txt" "$TEMP_REQ"
    UV_TORCH_BACKEND=auto GIT_LFS_SKIP_SMUDGE=1 uv pip install -r "$TEMP_REQ"
    rm -f "$TEMP_REQ"
    PYTHON_VER=$(python -c "import sys; print(f'{sys.version_info.major}.{sys.version_info.minor}')")
    cp -r $CONDA_PREFIX/lib/python${PYTHON_VER}/site-packages/openpi/models_pytorch/transformers_replace/* $CONDA_PREFIX/lib/python${PYTHON_VER}/site-packages/transformers/
    export TOKENIZER_DIR=~/.cache/openpi/big_vision/ && mkdir -p $TOKENIZER_DIR && gsutil -m cp -r gs://big_vision/paligemma_tokenizer.model $TOKENIZER_DIR
elif [ "$TARGET" = "reason" ]; then
    # Handle pyproject.toml with local git repositories for sglang-vllm extra
    if [ -f "${WORKSPACE}/pyproject.toml" ]; then
        cp "${WORKSPACE}/pyproject.toml" "$PYPROJECT_BACKUP"
        TEMP_PYPROJECT=$(mktemp)
        create_local_pyproject "${WORKSPACE}/pyproject.toml" "$TEMP_PYPROJECT"
        cp "$TEMP_PYPROJECT" "${WORKSPACE}/pyproject.toml"
        rm -f "$TEMP_PYPROJECT"
    fi
    uv sync --extra sglang-vllm
    if [ -f "$PYPROJECT_BACKUP" ]; then
        mv "$PYPROJECT_BACKUP" "${WORKSPACE}/pyproject.toml"
    fi
    uv pip uninstall pynvml
    mkdir -p /opt && clone_or_copy_repo "https://github.com/NVIDIA/Megatron-LM.git" "/opt/Megatron-LM" "core_r0.13.0"
    if [ "$TEST_BUILD" != "true" ]; then
        TEMP_REQ=$(mktemp)
        create_local_requirements "requirements/megatron.txt" "$TEMP_REQ"
        APEX_CPP_EXT=1 APEX_CUDA_EXT=1 NVCC_APPEND_FLAGS="--threads 24" APEX_PARALLEL_BUILD=24 uv pip install -r "$TEMP_REQ" --no-build-isolation
        rm -f "$TEMP_REQ"
    fi
    mkdir -p $CONDA_PREFIX/etc/conda/activate.d
    echo "export PYTHONPATH=/opt/Megatron-LM:\$PYTHONPATH" >> $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
    chmod +x $CONDA_PREFIX/etc/conda/activate.d/env_vars.sh
else
    echo "Unknown target: $TARGET. Supported targets are: openvla, openvla-oft, openpi, reason."
    exit 1
fi