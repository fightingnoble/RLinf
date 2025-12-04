#!/bin/bash
set -e

# ================= 配置区域 =================
CUDA_VERSION="12.4.1"
DRIVER_VERSION="550.54.15"
RUNFILE_NAME="cuda_${CUDA_VERSION}_${DRIVER_VERSION}_linux.run"
DOWNLOAD_URL="https://developer.download.nvidia.com/compute/cuda/${CUDA_VERSION}/local_installers/${RUNFILE_NAME}"

# 宿主机驱动库的查找路径（按优先级）
HOST_LIB_DIRS=(
    "/usr/lib/x86_64-linux-gnu"
    "/usr/lib64"
    "/usr/local/cuda/lib64"
)

# 基础工作目录
WORK_DIR="$HOME/cuda-fake"
TOOLKIT_DIR="${WORK_DIR}/cuda-12.4"
COMPAT_DIR="${TOOLKIT_DIR}/compat"
SYMLINK_DIR="${WORK_DIR}/cuda"

# ===========================================

echo "=== 开始构建 CUDA ${CUDA_VERSION} 伪装环境 ==="
echo "工作目录: ${WORK_DIR}"

# 1. 准备工作目录
mkdir -p "${WORK_DIR}"
cd "${WORK_DIR}"

# 2. 下载 CUDA runfile
# 注意：虽然驱动最终会用宿主机的，但我们需要 12.4 的 CUDA Toolkit
#      (nvcc 编译器、libcudart、libcublas 等运行时库)
if [ -f "${RUNFILE_NAME}" ]; then
    echo "✓ 检测到本地已有安装包: ${RUNFILE_NAME}"
else
    echo "⬇️ 正在下载 CUDA ${CUDA_VERSION} 安装包..."
    echo "   (包含 CUDA Toolkit + Driver，我们只需要 Toolkit 部分)"
    wget -c "${DOWNLOAD_URL}"
fi

# 3. 安装 Toolkit (不含驱动)
# 这一步只安装开发工具和库，不安装驱动到内核
echo "📦 正在安装 CUDA Toolkit 到 ${TOOLKIT_DIR}..."
echo "   (nvcc, libcudart, libcublas, 头文件等，不含 Driver)"
# 如果目录已存在，先清理以防冲突
if [ -d "${TOOLKIT_DIR}" ]; then
    echo "  - 清理旧的 Toolkit 目录..."
    rm -rf "${TOOLKIT_DIR}"
fi

sh "${RUNFILE_NAME}" --silent --toolkit --toolkitpath="${TOOLKIT_DIR}" --override --no-man-page
echo "✓ Toolkit 安装完成"

# 4. 创建 cuda 软链接
echo "🔗 创建软链接: cuda -> cuda-12.4"
rm -f "${SYMLINK_DIR}"
ln -s "cuda-12.4" "${SYMLINK_DIR}"

# 5. 构建关键的 compat 目录 (核心伪装步骤)
# 这一步的目的：
#   - nvidia-container-toolkit 会检查 /usr/local/cuda-12.4/compat/*.550.54.15 是否存在
#   - 但实际运行时，我们需要加载宿主机真实的 530 驱动（与内核匹配）
#   - 解决方案：创建名为 *.550.54.15 的软链接，指向宿主机的 *.530.30.02
echo "🎭 正在构建 compat 伪装层 (驱动库软链接)..."
mkdir -p "${COMPAT_DIR}"

# 5.1 查找宿主机当前使用的驱动版本
echo "  - 正在探测宿主机驱动..."
HOST_DRIVER_VERSION=""
for lib_dir in "${HOST_LIB_DIRS[@]}"; do
    # 查找 libcuda.so.xxx.xx.xx
    found_driver=$(find "${lib_dir}" -name "libcuda.so.*" 2>/dev/null | head -n 1 | awk -F'so.' '{print $3}')
    if [ -n "${found_driver}" ]; then
        HOST_DRIVER_VERSION="${found_driver}"
        HOST_LIB_PATH="${lib_dir}"
        break
    fi
done

if [ -z "${HOST_DRIVER_VERSION}" ]; then
    echo "❌ 错误: 未能在宿主机找到 libcuda.so，无法确定驱动版本！"
    exit 1
fi

echo "  - 宿主机驱动版本: ${HOST_DRIVER_VERSION} (位于 ${HOST_LIB_PATH})"
echo "  - 目标伪装版本: ${DRIVER_VERSION}"

# 5.2 创建指向宿主机真实驱动的软链接（伪装文件名）
echo "  - 正在创建驱动库伪装链接..."

# 定义需要伪装的库列表 (这是 nvidia-container-toolkit 检查的列表)
# 这些库我们将指向宿主机的真实库
LIBS_TO_LINK=(
    "libcuda.so"
    "libcudadebugger.so"
    "libEGL_nvidia.so"
    "libEGL.so"
    "libGLESv1_CM_nvidia.so"
    "libGLESv2_nvidia.so"
    "libGLX_nvidia.so"
    "libglxserver_nvidia.so"
    "libnvcuvid.so"
    "libnvidia-allocator.so"
    "libnvidia-cfg.so"
    "libnvidia-eglcore.so"
    "libnvidia-encode.so"
    "libnvidia-fbc.so"
    "libnvidia-glcore.so"
    "libnvidia-glsi.so"
    "libnvidia-glvkspirv.so"
    "libnvidia-gtk2.so"
    "libnvidia-gtk3.so"
    "libnvidia-ml.so"
    "libnvidia-ngx.so"
    "libnvidia-nvvm.so"
    "libnvidia-opencl.so"
    "libnvidia-opticalflow.so"
    "libnvidia-ptxjitcompiler.so"
    "libnvidia-rtcore.so"
    "libnvidia-tls.so"
    "libnvidia-wayland-client.so"
    "libnvoptix.so"
    "libvdpau_nvidia.so"
)

cd "${COMPAT_DIR}"
LINK_COUNT=0
MISSING_LIBS=()

for lib in "${LIBS_TO_LINK[@]}"; do
    # 宿主机真实文件：libname.so.HOST_VER
    REAL_FILE="${HOST_LIB_PATH}/${lib}.${HOST_DRIVER_VERSION}"
    # 伪装目标文件：libname.so.FAKE_VER
    FAKE_TARGET="${lib}.${DRIVER_VERSION}"
    
    if [ -f "${REAL_FILE}" ]; then
        ln -sf "${REAL_FILE}" "${FAKE_TARGET}"
        LINK_COUNT=$((LINK_COUNT + 1))
    else
        # 如果宿主机没有这个库，加入缺失列表，稍后用空文件占位
        MISSING_LIBS+=("${lib}")
    fi
done
echo "  ✓ 已链接 ${LINK_COUNT} 个真实驱动库"

# 5.3 创建空文件占位符 (处理宿主机缺失但 550 需要的库)
# 比如 libnvidia-pkcs11 等新库
echo "  - 处理缺失库与新版特有库 (创建空占位符)..."

# 显式添加 550 特有的新库
EXTRA_NEW_LIBS=(
    "libnvidia-pkcs11.so"
    "libnvidia-pkcs11-openssl3.so"
    "libnvidia-gpucomp.so"
)

# 合并所有需要占位的库
ALL_STUBS=("${MISSING_LIBS[@]}" "${EXTRA_NEW_LIBS[@]}")

STUB_COUNT=0
for lib in "${ALL_STUBS[@]}"; do
    FAKE_TARGET="${lib}.${DRIVER_VERSION}"
    # 创建一个指向自己的 0 字节文件或直接 touch
    # 为了模拟之前成功的结构：创建一个 .host_ver 的空文件，然后软链过去
    STUB_FILE="${lib}.${HOST_DRIVER_VERSION}"
    touch "${STUB_FILE}"
    chmod +x "${STUB_FILE}"
    ln -sf "${STUB_FILE}" "${FAKE_TARGET}"
    STUB_COUNT=$((STUB_COUNT + 1))
done
echo "  ✓ 已创建 ${STUB_COUNT} 个占位符文件"


# 6. 配置 ldcache (可选增强)
echo "🔧 配置 ldcache..."
mkdir -p "${WORK_DIR}/ldcache"
echo "/usr/local/cuda/lib64" > "${WORK_DIR}/ldcache/ld.so.conf"
echo "/usr/local/cuda/lib64/stubs" >> "${WORK_DIR}/ldcache/ld.so.conf"

# ================= 结束 =================
echo ""
echo "✅✅✅ 构建成功！ ✅✅✅"
echo ""
echo "请使用以下参数启动 Docker 容器："
echo "----------------------------------------------------------------"
echo "docker run --gpus all \\"
echo "  -e NVIDIA_DISABLE_REQUIRE=true \\"
echo "  -v ${WORK_DIR}/cuda:/usr/local/cuda:ro \\"
echo "  -v ${WORK_DIR}/cuda-12.4:/usr/local/cuda-12.4:ro \\"
echo "  your-image-name"
echo "----------------------------------------------------------------"
echo ""
echo "工作原理说明："
echo "├─ CUDA Toolkit 12.4 (nvcc, libcudart 等) ← 来自下载的 runfile"
echo "│  用于：编译、API 调用、数学库"
echo "│"
echo "├─ Driver 库 (libcuda.so 等) ← 软链接到宿主机 ${HOST_DRIVER_VERSION}"
echo "│  用于：GPU 指令、内核通信"
echo "│"
echo "└─ nvidia-container-toolkit 检查 → 看到 *.550.54.15 文件存在 ✓"
echo "   PyTorch 运行时 → 实际加载的是 *.${HOST_DRIVER_VERSION} ✓"
echo ""
echo "环境变量说明："
echo "1. NVIDIA_DISABLE_REQUIRE=true : 禁用 nvidia-container-toolkit 的版本检查"
echo "2. 挂载 /usr/local/cuda : 提供 CUDA 12.4 Toolkit (编译器和库)"
echo "3. 挂载 /usr/local/cuda-12.4/compat : 提供驱动库软链接 (伪装层)"
echo ""

docker run -it --gpus all \
  --shm-size 100g \
  --net=host \
  --name rlinf \
  -e NVIDIA_DRIVER_CAPABILITIES=compute,utility,graphics \
  -e NVIDIA_DISABLE_REQUIRE=true \
  -v $(pwd):/root/git_repo/RLinf \
  -w /root/git_repo/RLinf \
   -v ~/cuda-fake/cuda:/usr/local/cuda:ro \
   -v ~/cuda-fake/cuda-12.4:/usr/local/cuda-12.4:ro \
   -v ~/cuda-fake/ldcache/ld.so.conf:/etc/ld.so.conf.d/cuda-fake.conf:ro \
   -v ~/cuda-fake/cuda/lib64:/usr/local/cuda/lib64:ro \
  docker.1ms.run/rlinf/rlinf:agentic-rlinf0.1-torch2.6.0-openvla-openvlaoft-pi0 /bin/bash