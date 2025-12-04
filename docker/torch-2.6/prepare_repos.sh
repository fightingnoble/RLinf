#!/bin/bash

# Script to prepare repositories before Docker build
set -e

REPOS_DIR="./repos"
mkdir -p "$REPOS_DIR"

echo "Cloning repositories for Docker build..."

# Clone Megatron-LM
if [ ! -d "$REPOS_DIR/Megatron-LM" ]; then
    echo "Cloning Megatron-LM..."
    git clone --depth 1 -b core_r0.13.0 git@github.com:NVIDIA/Megatron-LM.git "$REPOS_DIR/Megatron-LM"
else
    echo "Megatron-LM already exists, skipping..."
fi

# Clone LIBERO
if [ ! -d "$REPOS_DIR/LIBERO" ]; then
    echo "Cloning LIBERO..."
    git clone --depth 1 -b master git@github.com:RLinf/LIBERO.git "$REPOS_DIR/LIBERO"
else
    echo "LIBERO already exists, skipping..."
fi

# Clone BEHAVIOR-1K (only needed for embodied-behavior build)
if [ ! -d "$REPOS_DIR/BEHAVIOR-1K" ]; then
    echo "Cloning BEHAVIOR-1K..."
    git clone --depth 1 -b RLinf/v3.7.1 git@github.com:RLinf/BEHAVIOR-1K.git "$REPOS_DIR/BEHAVIOR-1K"
else
    echo "BEHAVIOR-1K already exists, skipping..."
fi

# Clone OpenVLA
if [ ! -d "$REPOS_DIR/openvla" ]; then
    echo "Cloning OpenVLA..."
    git clone --depth 1 git@github.com:openvla/openvla.git "$REPOS_DIR/openvla"
else
    echo "OpenVLA already exists, skipping..."
fi

# Clone OpenVLA-OFT
if [ ! -d "$REPOS_DIR/openvla-oft" ]; then
    echo "Cloning OpenVLA-OFT..."
    git clone --depth 1 git@github.com:moojink/openvla-oft.git "$REPOS_DIR/openvla-oft"
else
    echo "OpenVLA-OFT already exists, skipping..."
fi

# Clone OpenPI
if [ ! -d "$REPOS_DIR/openpi" ]; then
    echo "Cloning OpenPI..."
    git clone --depth 1 git@github.com:RLinf/openpi.git "$REPOS_DIR/openpi"
else
    echo "OpenPI already exists, skipping..."
fi

# Clone ManiSkill
if [ ! -d "$REPOS_DIR/ManiSkill" ]; then
    echo "Cloning ManiSkill..."
    git clone --depth 1 git@github.com:haosulab/ManiSkill.git "$REPOS_DIR/ManiSkill"
else
    echo "ManiSkill already exists, skipping..."
fi

# Clone latex2sympy2
if [ ! -d "$REPOS_DIR/latex2sympy2" ]; then
    echo "Cloning latex2sympy2..."
    git clone --depth 1 git@github.com:RLinf/latex2sympy2.git "$REPOS_DIR/latex2sympy2"
else
    echo "latex2sympy2 already exists, skipping..."
fi

echo "All repositories prepared successfully!"

