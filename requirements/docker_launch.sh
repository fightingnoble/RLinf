#!/bin/bash

# Configuration
IMAGE_NAME="rlinf-zsh"
PROXY_HOST="${PROXY_HOST:-222.29.97.81}"
PROXY_PORT="${PROXY_PORT:-1080}"
SSH_KEY_EMAIL="${SSH_KEY_EMAIL:-zhangchg@stu.pku.edu.cn}"
CONTAINER_NAME="rlinf_local"

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "=========================================="
echo "Building Docker image: $IMAGE_NAME"
echo "=========================================="

# Build Docker image with configurable arguments
docker build \
  --build-arg PROXY_HOST="$PROXY_HOST" \
  --build-arg PROXY_PORT="$PROXY_PORT" \
  --build-arg SSH_KEY_EMAIL="$SSH_KEY_EMAIL" \
  -f "$REPO_ROOT/docker/Dockerfile.zsh" \
  -t "$IMAGE_NAME" \
  "$REPO_ROOT"

if [ $? -ne 0 ]; then
  echo "Error: Docker build failed!"
  exit 1
fi

echo ""
echo "=========================================="
echo "Starting container: $CONTAINER_NAME"
echo "=========================================="

# Remove existing container if it exists
if docker ps -a --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
  echo "Removing existing container: $CONTAINER_NAME"
  docker rm -f "$CONTAINER_NAME"
fi

# Run container
docker run -it --gpus all \
  --shm-size 100g \
  --net=host \
  --name "$CONTAINER_NAME" \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -v "$REPO_ROOT":/root/git_repo/RLinf \
  -w /root/git_repo/RLinf \
  "$IMAGE_NAME" /bin/zsh