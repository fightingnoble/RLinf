#!/bin/bash

# Get workspace directory (script is now in requirements/install_local/)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# SCRIPT_DIR is requirements/install_local/, need to go up two levels to project root
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOWNLOAD_DIR="${WORKSPACE}/docker/torch-2.6/repos"
WHEELS_DIR="${DOWNLOAD_DIR}/wheels"
ASSETS_DIR="${DOWNLOAD_DIR}/assets"

echo "========================================"
echo "Downloading dependencies to: $DOWNLOAD_DIR"
echo "========================================"

mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$WHEELS_DIR"
mkdir -p "$ASSETS_DIR"

# --- Git Repositories ---
echo ""
echo "=== Downloading Git Repositories ==="

# Format: "repo_url target_dir [branch]"
REPOS=(
    "https://github.com/RLinf/latex2sympy2.git latex2sympy2"
    "https://github.com/haosulab/ManiSkill.git ManiSkill"
    "https://github.com/RLinf/LIBERO.git LIBERO"
    "https://github.com/RLinf/BEHAVIOR-1K.git BEHAVIOR-1K RLinf/v3.7.1"
    "https://github.com/openvla/openvla.git openvla"
    "https://github.com/moojink/dlimp_openvla.git dlimp_openvla"
    "https://github.com/moojink/openvla-oft.git openvla-oft"
    "https://github.com/moojink/transformers-openvla-oft.git transformers-openvla-oft"
    "https://github.com/RLinf/openpi.git openpi"
    "https://github.com/NVIDIA/Megatron-LM.git Megatron-LM core_r0.13.0"
    "https://github.com/cython/cython.git cython"
)

for repo_info in "${REPOS[@]}"; do
    read -r url target_name branch <<< "$repo_info"
    target_path="${DOWNLOAD_DIR}/${target_name}"
    
    echo ""
    echo "[CLONE] Cloning $target_name..."
    if [ -d "$target_path" ]; then
        echo "  ✓ Already exists: $target_path"
        if [ -d "$target_path/.git" ]; then
            (cd "$target_path" && git fetch origin &>/dev/null && git reset --hard origin/"${branch:-main}" &>/dev/null)
            echo "  ✓ Updated existing repository."
        fi
    else
        if [ -n "$branch" ]; then
            git clone -b "$branch" "$url" "$target_path"
        else
            git clone "$url" "$target_path"
        fi
        if [ $? -eq 0 ]; then
            echo "  ✓ Cloned to: $target_path"
        else
            echo "  ✗ Failed to clone $url"
        fi
    fi
done

# --- Wheel Packages ---
echo ""
echo "=== Downloading Wheel Packages ==="

# Format: "wheel_url"
WHEELS=(
    "https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.5cxx11abiFALSE-cp310-cp310-linux_x86_64.whl"
    "https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.6cxx11abiFALSE-cp311-cp311-linux_x86_64.whl"
    "https://github.com/RLinf/apex/releases/download/25.09/apex-0.1-cp311-cp311-linux_x86_64.whl"
)

for wheel_url in "${WHEELS[@]}"; do
    filename=$(basename "$wheel_url")
    target_path="${WHEELS_DIR}/${filename}"
    
    echo ""
    echo "[DOWNLOAD] Downloading $filename..."
    if [ -f "$target_path" ]; then
        echo "  ✓ Already exists: $target_path"
    else
        wget -q --show-progress -O "$target_path" "$wheel_url"
        if [ $? -eq 0 ]; then
            echo "  ✓ Downloaded to: $target_path"
        else
            echo "  ✗ Failed to download $wheel_url"
        fi
    fi
done

# --- ManiSkill Assets ---
echo ""
echo "=== Downloading ManiSkill Assets ==="

# Create assets directory structure
ASSETS_MS_DIR="${ASSETS_DIR}/.maniskill/data"
ASSETS_SAPIEN_DIR="${ASSETS_DIR}/.sapien/physx/105.1-physx-5.3.1.patch0"
mkdir -p "$ASSETS_MS_DIR/tasks"
mkdir -p "$ASSETS_SAPIEN_DIR"

# bridge_v2_real2sim dataset
BRIDGE_DATASET_URL="https://huggingface.co/datasets/haosulab/ManiSkill_bridge_v2_real2sim/resolve/main/bridge_v2_real2sim_dataset.zip"
BRIDGE_DATASET_TARGET="${ASSETS_MS_DIR}/tasks/bridge_v2_real2sim_dataset.zip"
if [ -d "${ASSETS_MS_DIR}/tasks/bridge_v2_real2sim_dataset" ]; then
    echo "[ASSETS] bridge_v2_real2sim dataset already exists, skipping download."
elif [ -f "$BRIDGE_DATASET_TARGET" ]; then
    echo "[ASSETS] bridge_v2_real2sim dataset zip already exists, extracting..."
    unzip -q "$BRIDGE_DATASET_TARGET" -d "${ASSETS_MS_DIR}/tasks" && rm "$BRIDGE_DATASET_TARGET"
    echo "  ✓ Extracted bridge_v2_real2sim dataset."
else
    echo "[ASSETS] Downloading bridge_v2_real2sim dataset..."
    wget -q --show-progress -O "$BRIDGE_DATASET_TARGET" "$BRIDGE_DATASET_URL"
    if [ $? -eq 0 ]; then
        unzip -q "$BRIDGE_DATASET_TARGET" -d "${ASSETS_MS_DIR}/tasks" && rm "$BRIDGE_DATASET_TARGET"
        echo "  ✓ Downloaded and extracted bridge_v2_real2sim dataset."
    else
        echo "  ✗ Failed to download bridge_v2_real2sim dataset"
    fi
fi

# WidowX250S robot assets
WIDOWX_URL="https://github.com/haosulab/ManiSkill-WidowX250S/archive/refs/tags/v0.2.0.zip"
WIDOWX_TARGET="${ASSETS_MS_DIR}/robots/widowx.zip"
mkdir -p "${ASSETS_MS_DIR}/robots"
if [ -d "${ASSETS_MS_DIR}/robots/widowx" ]; then
    echo "[ASSETS] WidowX250S assets already exist, skipping download."
elif [ -f "$WIDOWX_TARGET" ]; then
    echo "[ASSETS] WidowX250S zip already exists, extracting..."
    unzip -q "$WIDOWX_TARGET" -d "${ASSETS_MS_DIR}/robots" && \
    mv "${ASSETS_MS_DIR}/robots/ManiSkill-WidowX250S-0.2.0" "${ASSETS_MS_DIR}/robots/widowx" && \
    rm "$WIDOWX_TARGET"
    echo "  ✓ Extracted WidowX250S assets."
else
    echo "[ASSETS] Downloading WidowX250S assets..."
    wget -q --show-progress -O "$WIDOWX_TARGET" "$WIDOWX_URL"
    if [ $? -eq 0 ]; then
        unzip -q "$WIDOWX_TARGET" -d "${ASSETS_MS_DIR}/robots" && \
        mv "${ASSETS_MS_DIR}/robots/ManiSkill-WidowX250S-0.2.0" "${ASSETS_MS_DIR}/robots/widowx" && \
        rm "$WIDOWX_TARGET"
        echo "  ✓ Downloaded and extracted WidowX250S assets."
    else
        echo "  ✗ Failed to download WidowX250S assets"
    fi
fi

# SAPIEN PhysX assets
PHYSX_VERSION="105.1-physx-5.3.1.patch0"
PHYSX_URL="https://github.com/sapien-sim/physx-precompiled/releases/download/${PHYSX_VERSION}/linux-so.zip"
PHYSX_TARGET="${ASSETS_SAPIEN_DIR}/linux-so.zip"
if [ -d "$ASSETS_SAPIEN_DIR" ] && compgen -G "$ASSETS_SAPIEN_DIR/*.so" > /dev/null; then
    echo "[ASSETS] SAPIEN PhysX assets already exist, skipping download."
elif [ -f "$PHYSX_TARGET" ]; then
    echo "[ASSETS] SAPIEN PhysX zip already exists, extracting..."
    unzip -q "$PHYSX_TARGET" -d "$ASSETS_SAPIEN_DIR" && rm "$PHYSX_TARGET"
    echo "  ✓ Extracted SAPIEN PhysX assets."
else
    echo "[ASSETS] Downloading SAPIEN PhysX assets..."
    wget -q --show-progress -O "$PHYSX_TARGET" "$PHYSX_URL"
    if [ $? -eq 0 ]; then
        unzip -q "$PHYSX_TARGET" -d "$ASSETS_SAPIEN_DIR" && rm "$PHYSX_TARGET"
        echo "  ✓ Downloaded and extracted SAPIEN PhysX assets."
    else
        echo "  ✗ Failed to download SAPIEN PhysX assets"
    fi
fi

# --- OpenPI Assets ---
echo ""
echo "=== Downloading OpenPI Assets ==="

# OpenPI tokenizer
OPENPI_TOKENIZER_DIR="${ASSETS_DIR}/.cache/openpi/big_vision"
OPENPI_TOKENIZER_FILE="${OPENPI_TOKENIZER_DIR}/paligemma_tokenizer.model"
mkdir -p "$OPENPI_TOKENIZER_DIR"

if [ -f "$OPENPI_TOKENIZER_FILE" ]; then
    echo "[ASSETS] OpenPI tokenizer already exists, skipping download."
else
    echo "[ASSETS] Downloading OpenPI tokenizer..."
    echo "NOTE: This requires gsutil. If not available, download manually from:"
    echo "  gs://big_vision/paligemma_tokenizer.model"
    echo "  and place it at: $OPENPI_TOKENIZER_FILE"
    
    if command -v gsutil &> /dev/null; then
        gsutil -m cp gs://big_vision/paligemma_tokenizer.model "$OPENPI_TOKENIZER_DIR/"
        if [ $? -eq 0 ]; then
            echo "  ✓ Downloaded OpenPI tokenizer."
        else
            echo "  ✗ Failed to download OpenPI tokenizer (gsutil error)"
        fi
    else
        echo "  ⚠ gsutil not found, skipping OpenPI tokenizer download."
        echo "  Please install gsutil or download manually if needed."
    fi
fi

echo ""
echo "========================================"
echo "Dependency download process completed."
echo "========================================"

# ============================================================
# Legacy / Utility Functions (Currently Unused)
# Transferred from install_local_utils.sh
# ============================================================

# Apply git URL replacements by on-demand lookup (single file processing)
# Note: Requires get_local_git_path function (not present in this script)
#
# apply_git_url_replacements_ondemand() {
#     local target_file="$1"
#
#     if [ ! -f "$target_file" ]; then
#         return 0
#     fi
#
#     local temp_file
#     temp_file=$(mktemp)
#     # Define regex pattern to match git URLs, excluding quotes and whitespace
#     local git_url_pattern="git\+https://[^[:space:]\"']+"
#
#     while IFS= read -r line || [ -n "$line" ]; do
#         # Check for git URL
#         if [[ "$line" =~ $git_url_pattern ]]; then
#             local git_url
#             git_url=$(echo "$line" | grep -oE "$git_url_pattern")
#             local clean_url="${git_url#git+}"
#             local local_path
#             local_path=$(get_local_git_path "$clean_url")
#             if [[ "$local_path" == file://* ]]; then
#                 # Escape special chars in git_url for sed (specifically +)
#                 local escaped_git_url=$(echo "$git_url" | sed 's/[+]/\\&/g')
#                 # Replace URL, handling optional @tag suffix
#                 line=$(echo "$line" | sed -E "s|${escaped_git_url}(@[^[:space:]\"']*)?|${local_path}|g")
#             fi
#         fi
#         echo "$line" >> "$temp_file"
#     done < "$target_file"
#     mv "$temp_file" "$target_file"
# }
