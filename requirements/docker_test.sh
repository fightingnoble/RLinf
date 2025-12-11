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
#   - 本地缓存: /cache/z30081742/rlinf/repos (挂载自 docker/torch-2.6/repos)
#   - 安装目标: embodied --model openvla --env maniskill_libero
# 
# 测试步骤：
#   1. 清理旧容器
#   2. 启动新容器（后台运行）
#   3. 运行 prepare 阶段（安装 Python 3.11 和系统依赖）
#   4. 运行 embodied 安装（openvla + maniskill_libero）
#   5. 检查依赖来源和下载情况
# 
# 预期结果：
#   🟢 latex2sympy2: 显示 [local-deps] using local repo（绿色）
#   🟢 openvla: 显示 [local-deps] using local repo（绿色）
#   🟢 dlimp_openvla: 显示 [local-deps] using local repo（绿色，子依赖）
#   🟢 ManiSkill: 显示 [local-deps] using local repo 或 Using local repository
#   🟢 LIBERO: 显示 Using local repository（clone_or_copy_repo）
#   🟢 ManiSkill assets: 从本地 assets 目录复制
#   🟢 flash-attn: 显示 [local-deps] using local wheel（如有）
#   🟡 远程回退：应为空或极少（黄色警告）
#   🔵 备份还原：安装结束显示 restoring ... backup（青色）
#   ✗ 仅允许从 PyPI 镜像下载 wheel 包
# 
# ============================================================

set -e


REPO_ROOT="/home/zhangchenguang/git_repo/RLinf"
CONTAINER_NAME="rlinf_local"
IMAGE_NAME="rlinf-zsh"
CACHE_DIR="/cache/z30081742/rlinf/repos"
CONTAINER_USER="appuser"
CONTAINER_HOME="/home/${CONTAINER_USER}"
CONTAINER_WORKDIR="${CONTAINER_HOME}/git_repo/RLinf"

echo "============================================================"
echo "  RLinf 端到端离线安装测试"
echo "============================================================"
echo ""

# ============================================================
# 步骤 1: 清理旧容器
# ============================================================
echo "[Step 1/5] 清理旧容器..."
cd "$REPO_ROOT"
docker stop "$CONTAINER_NAME" 2>/dev/null && docker rm "$CONTAINER_NAME" 2>/dev/null && echo "✓ 容器已清理" || echo "✓ 无需清理"
echo ""

# 清理项目目录下的生成文件和备份文件
cd /home/zhangchenguang/git_repo/RLinf
./requirements/install_local/restore.sh
rm -rf .venv uv.lock pyproject.toml.backup
find requirements -name "*.backup" -type f -delete


# ============================================================
# 步骤 2: 启动新容器并且清理环境
# ============================================================
echo "[Step 2/5] 启动新容器..."
docker run -d --gpus all \
  --shm-size 100g \
  --net=host \
  --name "$CONTAINER_NAME" \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -v "$REPO_ROOT:${CONTAINER_WORKDIR}" \
  -v "$REPO_ROOT/docker/torch-2.6/repos:$CACHE_DIR" \
  -e extrenal_repo="$CACHE_DIR" \
  -w "${CONTAINER_WORKDIR}" \
  "$IMAGE_NAME" sleep infinity

if [ $? -eq 0 ]; then
  echo "✓ 容器已启动: $CONTAINER_NAME"
else
  echo "✗ 容器启动失败"
  exit 1
fi
echo ""
# 确保容器内的 uv 缓存是干净的
docker exec "$CONTAINER_NAME" bash -c "cd ${CONTAINER_WORKDIR} && uv cache clean"
docker exec "$CONTAINER_NAME" bash -c "cd ${CONTAINER_WORKDIR} && rm -rf .venv uv.lock pyproject.toml.backup requirements/*.backup" && echo "Cleanup inside container successful"

# ============================================================
# 步骤 3: 运行 prepare 阶段
# ============================================================
# 准备本地安装所需的依赖
pip install gsutil
bash requirements/install_local/download.sh

echo "[Step 3/5] 运行 prepare 阶段（安装 Python 3.11）..."
docker exec "$CONTAINER_NAME" bash -c "
cd ${CONTAINER_WORKDIR}
sudo --preserve-env=extrenal_repo bash requirements/install.sh prepare --python /usr/bin/python3.11 
"
echo ""

# ============================================================
# 步骤 4: 运行 embodied 安装
# ============================================================
echo "[Step 4/5] 运行 embodied 安装..."
docker exec "$CONTAINER_NAME" bash -c "
cd ${CONTAINER_WORKDIR}
rm -rf .venv uv.lock pyproject.toml.backup
echo '========================================'
echo 'Embodied Installation'
echo '========================================'
echo 'Environment:'
echo '  extrenal_repo: '\$extrenal_repo
echo '  Python: /usr/bin/python3.11'
echo ''

sudo --preserve-env=extrenal_repo bash requirements/install.sh embodied --model openvla --env maniskill_libero --python /usr/bin/python3.11 2>&1 | tee /tmp/install_full.log
"

if [ $? -eq 0 ]; then
  echo ""
  echo "✓ 安装完成"
else
  echo ""
  echo "✗ 安装失败"
  exit 1
fi
echo ""

# ============================================================
# 步骤 5: 验证安装结果
# ============================================================
echo "[Step 5/5] 验证安装结果..."
echo ""

docker exec "$CONTAINER_NAME" bash -c "
cd ${CONTAINER_WORKDIR}

echo '============================================================'
echo '  关键依赖来源检查'
echo '============================================================'
echo ''

echo '【🟢 本地 Git 仓库使用】'
grep -E '\[local-deps\] using local repo' /tmp/install_full.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  ✓ /' || echo '  (未找到)'
echo ''

echo '【🟢 本地 Wheel 使用】'
grep -E '\[local-deps\] using local wheel' /tmp/install_full.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  ✓ /' || echo '  (未找到)'
echo ''

echo '【🟡 远程回退（应尽量为空）】'
grep -E '\[local-deps\] remote (fallback|wheel fallback)' /tmp/install_full.log | sed 's/\x1b\[[0-9;]*m//g' | sed 's/^/  ⚠ /' || echo '  ✓ 无远程回退'
echo ''

echo '【本地路径复制】'
grep 'Using local repository' /tmp/install_full.log | sed 's/^/  ✓ /' || echo '  (未找到)'
echo ''

echo '【ManiSkill Assets】'
grep 'ManiSkill assets' /tmp/install_full.log | sed 's/^/  /' || echo '  (未找到)'
echo ''

echo '【🔵 备份还原】'
grep -E '\[local-deps\] restoring' /tmp/install_full.log | sed 's/\x1b\[[0-9;]*m//g' | tail -5 | sed 's/^/  /' || echo '  (未找到)'
echo ''

echo '============================================================'
echo '  PyPI 下载统计'
echo '============================================================'
grep 'Downloading' /tmp/install_full.log | wc -l | xargs echo '  PyPI 包下载数量:'
echo ''

echo '============================================================'
echo '  安装的关键包版本'
echo '============================================================'
source .venv/bin/activate
pip show openvla dlimp mani-skill libero 2>/dev/null | grep -E '(Name|Version|Location):' | sed 's/^/  /'
"

echo ""
echo "============================================================"
echo "  测试完成"
echo "============================================================"
echo ""
echo "查看完整日志："
echo "  docker exec $CONTAINER_NAME cat /tmp/install_full.log"
echo ""
echo "进入容器调试："
echo "  docker exec -it $CONTAINER_NAME /bin/zsh"
echo ""
