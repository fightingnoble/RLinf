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

# Note: PROXY_HOST and SSH_KEY_EMAIL are optional
# If not set, Dockerfile will skip proxy configuration and SSH key generation


echo "=========================================="
echo "Building Docker image: $IMAGE_NAME"
echo "=========================================="

# Build Docker image with configurable arguments
# Only pass build args if they are set
BUILD_ARGS=(
  --build-arg HOST_UID="$HOST_UID"
  --build-arg HOST_GID="$HOST_GID"
)
[ -n "$PROXY_HOST" ] && BUILD_ARGS+=(--build-arg PROXY_HOST="$PROXY_HOST")
[ -n "$PROXY_PORT" ] && BUILD_ARGS+=(--build-arg PROXY_PORT="$PROXY_PORT")
[ -n "$SSH_KEY_EMAIL" ] && BUILD_ARGS+=(--build-arg SSH_KEY_EMAIL="$SSH_KEY_EMAIL")
[ -n "$NO_MIRROR" ] && BUILD_ARGS+=(--build-arg NO_MIRROR="$NO_MIRROR")
[ -n "$CUDA_VARIANT" ] && BUILD_ARGS+=(--build-arg CUDA_VARIANT="$CUDA_VARIANT")

docker build \
  "${BUILD_ARGS[@]}" \
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