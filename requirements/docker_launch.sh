#!/bin/bash
set -e

# 仅负责构建镜像，启动与测试由 docker_test.sh 完成

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load local configuration if exists
if [ -f "$SCRIPT_DIR/config.local.sh" ]; then
  source "$SCRIPT_DIR/config.local.sh"
fi

# Configuration (with defaults if not in config.local.sh)
IMAGE_NAME="rlinf-zsh"
PROXY_HOST="${PROXY_HOST:-}"
PROXY_PORT="${PROXY_PORT:-1080}"
SSH_KEY_EMAIL="${SSH_KEY_EMAIL:-}"
HOST_UID="${HOST_UID:-$(id -u)}"
HOST_GID="${HOST_GID:-$(id -g)}"
NO_MIRROR="${NO_MIRROR:-}"

# Validate required config
if [ -z "$PROXY_HOST" ] || [ -z "$SSH_KEY_EMAIL" ]; then
  echo "Error: PROXY_HOST and SSH_KEY_EMAIL must be set."
  echo "Please create requirements/config.local.sh based on config.local.sh.example"
  exit 1
fi

# Setup cache directory for offline test simulation
CACHE_MOUNT=""
CACHE_ENV=""
if [ -z "$CACHE_DIR" ]; then
  echo "Error: CACHE_DIR must be set in config.local.sh"
  echo "Please create requirements/config.local.sh based on config.local.sh.example"
  exit 1
fi
TARGET_CACHE_DIR="$CACHE_DIR"
if [ -d "$REPO_ROOT/docker/torch-2.6/repos" ]; then
    CACHE_MOUNT="-v $REPO_ROOT/docker/torch-2.6/repos:$TARGET_CACHE_DIR"
    CACHE_ENV="-e external_repo=$TARGET_CACHE_DIR"
    echo "Mounting repos to: $TARGET_CACHE_DIR"
fi

echo "=========================================="
echo "Building Docker image: $IMAGE_NAME"
echo "=========================================="

# Build Docker image with configurable arguments
docker build \
  --build-arg PROXY_HOST="$PROXY_HOST" \
  --build-arg PROXY_PORT="$PROXY_PORT" \
  --build-arg SSH_KEY_EMAIL="$SSH_KEY_EMAIL" \
  --build-arg HOST_UID="$HOST_UID" \
  --build-arg HOST_GID="$HOST_GID" \
  ${NO_MIRROR:+--build-arg NO_MIRROR=$NO_MIRROR} \
  -f "$REPO_ROOT/docker/Dockerfile.zsh" \
  -t "$IMAGE_NAME" \
  "$REPO_ROOT"

if [ $? -ne 0 ]; then
  echo "Error: Docker build failed!"
  exit 1
fi

echo ""
echo "=========================================="
echo "Image build finished: $IMAGE_NAME"
echo "=========================================="
echo "下一步：运行 requirements/docker_test.sh 启动容器并执行离线安装测试。"