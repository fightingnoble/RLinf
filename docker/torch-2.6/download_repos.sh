#!/bin/bash

# Get workspace directory (assuming script is in docker/torch-26 subdirectory)
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORKSPACE="$(cd "$SCRIPT_DIR/../.." && pwd)"
DOWNLOAD_DIR="${WORKSPACE}/docker/torch-2.6/repos"
WHEELS_DIR="${DOWNLOAD_DIR}/wheels"

echo "========================================"
echo "Downloading dependencies to: $DOWNLOAD_DIR"
echo "========================================"

mkdir -p "$DOWNLOAD_DIR"
mkdir -p "$WHEELS_DIR"

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
    "https://github.com/moojink/openvla-oft.git openvla-oft"
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

echo ""
echo "========================================"
echo "Dependency download process completed."
echo "========================================"
