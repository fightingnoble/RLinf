#!/bin/bash
# ============================================================
# 端到端离线安装测试脚本
# ============================================================
# 
# 测试目标：验证 RLinf 在 Docker 容器中使用本地缓存的离线安装
# 
# 测试环境：
#   - Docker 镜像: rlinf-zsh (基于 nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04)
#   - Python 版本: 3.11 (通过 prepare 阶段安装)
#   - 本地缓存: 由 config.local.sh 中的 CACHE_DIR 配置（挂载自 docker/torch-2.6/repos）
#   - 安装目标: embodied --model openvla --env maniskill_libero
# 
# 支持 Docker / 本地双模式，核心安装逻辑在 requirements/install_local_wrap.sh
# ============================================================

set -e

# Get script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# Load local configuration if exists
if [ -f "$SCRIPT_DIR/config.local.sh" ]; then
  source "$SCRIPT_DIR/config.local.sh"
fi

# Configuration (with defaults if not in config.local.sh)
CONTAINER_NAME="rlinf_local"
IMAGE_NAME="rlinf-zsh"
# CACHE_DIR must be set in config.local.sh (宿主机路径)
if [ -z "$CACHE_DIR" ]; then
  echo "Error: CACHE_DIR must be set in config.local.sh"
  echo "Please create requirements/config.local.sh based on config.local.sh.example"
  exit 1
fi
# CONTAINER_CACHE_DIR: 容器内挂载点（默认 /cache/repos）
CONTAINER_CACHE_DIR="${CONTAINER_CACHE_DIR:-/cache/repos}"
# REPO_ROOT is already set above from script directory or config.local.sh
CONTAINER_USER="appuser"
CONTAINER_HOME="/home/${CONTAINER_USER}"
CONTAINER_WORKDIR="${CONTAINER_HOME}/git_repo/RLinf"
MODE="docker"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --mode)
      MODE="$2"
      shift 2
      ;;
    --mode=*)
      MODE="${1#*=}"
      shift
      ;;
    *)
      echo "未知参数: $1"
      exit 1
      ;;
  esac
done

echo "============================================================"
echo "  RLinf 端到端离线安装测试"
echo "============================================================"
echo ""

# ============================================================
# 步骤 1: 检查本地下载
# ============================================================
echo "[Step 1] 检查本地下载..."
pip install gsutil
bash requirements/install_local/download.sh
echo ""

# ============================================================
# 步骤 2: 清理项目目录
# ============================================================
echo "[Step 2] 清理项目目录..."
cd "$REPO_ROOT"
./requirements/install_local/restore.sh
rm -rf .venv uv.lock pyproject.toml.backup
find requirements -name "*.backup" -type f -delete
echo ""

# ============================================================
# 步骤 3: 根据模式设置环境并执行安装
# ============================================================
if [ "$MODE" = "docker" ]; then

  echo "[Docker] 清理旧容器..."
  cd "$REPO_ROOT"
  docker stop "$CONTAINER_NAME" 2>/dev/null && docker rm "$CONTAINER_NAME" 2>/dev/null && echo "✓ 容器已清理" || echo "✓ 无需清理"
  echo ""

  echo "[Step 3] Docker 模式：构建镜像并启动容器..."
  bash requirements/docker_launch.sh

  docker run -d --gpus all \
    --shm-size 100g \
    --net=host \
    --name "$CONTAINER_NAME" \
    -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
    -v "$REPO_ROOT:${CONTAINER_WORKDIR}" \
    -v "$CACHE_DIR:$CONTAINER_CACHE_DIR" \
    -e external_repo="$CONTAINER_CACHE_DIR" \
    -w "${CONTAINER_WORKDIR}" \
    "$IMAGE_NAME" sleep infinity

  if [ $? -eq 0 ]; then
    echo "✓ 容器已启动: $CONTAINER_NAME"
  else
    echo "✗ 容器启动失败"
    exit 1
  fi
  echo ""

  echo "[Step 4] 在容器内执行安装与验证..."
  docker exec "$CONTAINER_NAME" bash -lc "cd ${CONTAINER_WORKDIR} && bash requirements/install_local_wrap.sh"
else
  echo "[Step 3] 本地模式：设置环境..."
  export external_repo="$CACHE_DIR"
  cd "$REPO_ROOT"

  echo "[Step 4] 本地执行安装与验证..."
  bash requirements/install_local_wrap.sh
fi

echo ""
echo "============================================================"
echo "  测试完成"
echo "============================================================"
echo ""
if [ "$MODE" = "docker" ]; then
  echo "查看完整日志："
  echo "  docker exec $CONTAINER_NAME cat /tmp/install_full.log"
  echo ""
  echo "进入容器调试："
  echo "  docker exec -it $CONTAINER_NAME /bin/zsh"
  echo ""
else
  echo "查看完整日志："
  echo "  cat /tmp/install_full.log"
  echo ""
fi
