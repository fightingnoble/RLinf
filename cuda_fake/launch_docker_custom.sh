#!/bin/bash
set -e

# ================= RLinf Docker 启动脚本 =================
# 此脚本用于启动配置完整的 RLinf Docker 容器
# CUDA 驱动伪装环境需要在运行前通过 setup_cuda_drivers.sh 准备好

# 配置区域
WORK_DIR="$HOME/cuda-fake"
TOOLKIT_DIR="${WORK_DIR}/cuda-12.4"
COMPAT_DIR="${TOOLKIT_DIR}/compat"

# ===========================================

echo "=== RLinf Docker 容器启动 ==="

# 检查 CUDA 伪装环境是否已准备好
echo "🔍 检查 CUDA 伪装环境..."
if [ ! -d "${TOOLKIT_DIR}" ]; then
    echo "❌ 错误: CUDA 伪装环境未设置！"
    echo ""
    echo "请先运行以下命令设置 CUDA 环境："
    echo "  ./setup_cuda_drivers.sh"
    echo ""
    echo "或者如果您已经设置过但在不同位置，请检查 WORK_DIR 变量。"
    exit 1
fi

if [ ! -d "${COMPAT_DIR}" ] || [ -z "$(ls -A ${COMPAT_DIR})" ]; then
    echo "❌ 错误: CUDA 驱动伪装层未构建！"
    echo ""
    echo "请重新运行驱动设置："
    echo "  ./setup_cuda_drivers.sh"
    exit 1
fi

echo "✅ CUDA 伪装环境检查通过"

# ================= 启动 Docker 容器 =================
echo ""
echo "🚀 正在启动 Docker 容器..."

# 获取用户ID和组ID，用于权限映射
USER_ID=$(id -u)
GROUP_ID=$(id -g)

# 检查是否可以访问代理相关的环境变量或配置文件
if [ -f "$(pwd)/.proxy_env" ]; then
    echo "  - 检测到代理配置文件: $(pwd)/.proxy_env"
    PROXY_VARS="-e BASH_ENV=/root/.proxy_env"
fi

docker run -it --gpus all \
  --shm-size 100g \
  --net=host \
  --name rlinf \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -e NVIDIA_DISABLE_REQUIRE=true \
  -e USER=root \
  -e HOME=/root \
  $PROXY_VARS \
  -v $(pwd):/root/git_repo/RLinf \
  -v /tmp:/tmp \
  -v /var/run/docker.sock:/var/run/docker.sock \
  -v $(pwd)/.zshrc:/root/.zshrc:ro \
  -v $(pwd)/.proxy_env:/root/.proxy_env:ro \
  -w /root/git_repo/RLinf \
   -v ~/cuda-fake/cuda:/usr/local/cuda:ro \
   -v ~/cuda-fake/cuda-12.4:/usr/local/cuda-12.4:ro \
   -v ~/cuda-fake/ldcache/ld.so.conf:/etc/ld.so.conf.d/cuda-fake.conf:ro \
   -v ~/cuda-fake/cuda/lib64:/usr/local/cuda/lib64:ro \
  docker.1ms.run/rlinf/rlinf:agentic-rlinf0.1-torch2.6.0-openvla-openvlaoft-pi0 \
  /bin/bash -c "
    echo '🎯 RLinf Docker 容器启动成功！'
    echo ''

    # 第一阶段：以 root 身份执行初始化脚本
    echo '🔧 执行初始化脚本...'
    if [ -f '/root/git_repo/RLinf/docker_init_from_dockerfile.sh' ]; then
        bash /root/git_repo/RLinf/docker_init_from_dockerfile.sh
    else
        echo '⚠️  docker_init_from_dockerfile.sh 未找到，跳过初始化'
    fi
    echo '✅ 初始化完成'
    echo ''

    # 第二阶段：切换到普通用户并启动 zsh
    echo '🚀 切换到用户环境...'
    APP_USER=\${APP_USER:-appuser}

    # 验证用户存在
    if ! id -u \${APP_USER} > /dev/null 2>&1; then
        echo '❌ 用户 \${APP_USER} 不存在，无法切换身份'
        echo '💡 请检查 docker_init_from_dockerfile.sh 是否正确执行'
        exit 1
    fi

    echo '💡 常用命令:'
    echo '  cdrl     - 进入 RLinf 工作目录'
    echo '  gs       - Git 状态'
    echo '  ll       - 详细文件列表'
    echo '  proxy_en - 启用代理'
    echo '  gpu_mem  - GPU 内存使用'
    echo ''

    # 切换到用户并启动 zsh
    exec su - \${APP_USER} -c 'cd /root/git_repo/RLinf && exec /bin/zsh'
  "