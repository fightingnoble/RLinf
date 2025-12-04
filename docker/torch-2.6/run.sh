#!/bin/bash

# Script to run Docker container with all necessary mounts
# Usage: ./run.sh [embodied|reason|embodied-behavior]

TARGET="${1:-embodied}"
IMAGE_TAG="rlinf:${TARGET}"
REPOS_DIR="$(pwd)/repos"

# Check if repos are prepared
if [ ! -d "$REPOS_DIR/Megatron-LM" ] || [ ! -d "$REPOS_DIR/LIBERO" ]; then
    echo "Error: Repositories not found. Please run ./prepare_repos.sh first."
    exit 1
fi

# Build common volume mounts
VOLUME_MOUNTS=(
    "-v $(pwd)/repos/Megatron-LM:/opt/Megatron-LM:ro"
    "-v $(pwd)/repos/LIBERO:/opt/libero:ro"
    "-v $(dirname $(dirname $(pwd))):/workspace/RLinf"
)

# Add BEHAVIOR-1K mount for embodied-behavior target
if [ "$TARGET" = "embodied-behavior" ]; then
    if [ ! -d "$REPOS_DIR/BEHAVIOR-1K" ]; then
        echo "Error: BEHAVIOR-1K repository not found. Please run ./prepare_repos.sh first."
        exit 1
    fi
    VOLUME_MOUNTS+=("-v $(pwd)/repos/BEHAVIOR-1K:/opt/BEHAVIOR-1K:ro")
fi

echo "Starting Docker container: $IMAGE_TAG"
echo "Mounts:"
for mount in "${VOLUME_MOUNTS[@]}"; do
    echo "  $mount"
done

docker run -it --rm \
    --gpus all \
    --shm-size 100g \
    --net=host \
    --name rlinf-${TARGET} \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
    "${VOLUME_MOUNTS[@]}" \
    -w /workspace/RLinf \
    "$IMAGE_TAG" \
    /bin/bash

