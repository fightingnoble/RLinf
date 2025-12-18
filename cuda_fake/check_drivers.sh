#!/bin/bash
set -e

# ================= 配置区域 =================
# 这些配置与 setup_cuda_fake.sh 保持一致
DRIVER_VERSION="550.54.15"

# 宿主机驱动库的查找路径（按优先级）
HOST_LIB_DIRS=(
    "/usr/lib/x86_64-linux-gnu"
    "/usr/lib64"
    "/usr/local/cuda/lib64"
    "/usr/lib"
    "/usr/local/lib64"
    "/usr/local/lib"
    "/opt/cuda/lib64"
    "/opt/cuda/lib"
)

# 定义需要检查的库列表 (与 setup_cuda_fake.sh 中的 LIBS_TO_LINK 保持一致)
LIBS_TO_CHECK=(
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

# 额外需要检查的新库
EXTRA_NEW_LIBS=(
    "libnvidia-pkcs11.so"
    "libnvidia-pkcs11-openssl3.so"
    "libnvidia-gpucomp.so"
)

# ===========================================

echo "=== NVIDIA 驱动库检查工具 ==="
echo ""

# 1. 检查 NVIDIA 驱动是否安装
echo "1. 检查 NVIDIA 驱动状态..."
if command -v nvidia-smi &> /dev/null; then
    echo "✓ nvidia-smi 可用"
    nvidia-smi --query-gpu=driver_version --format=csv,noheader,nounits | head -n 1
else
    echo "❌ nvidia-smi 不可用，请检查 NVIDIA 驱动是否正确安装"
    exit 1
fi
echo ""

# 2. 查找宿主机驱动库位置
echo "2. 查找宿主机驱动库位置..."
HOST_DRIVER_VERSION=""
HOST_LIB_PATH=""
FOUND_LIBS_DIR=""

for lib_dir in "${HOST_LIB_DIRS[@]}"; do
    echo "  检查目录: ${lib_dir}"
    if [ -d "${lib_dir}" ]; then
        # 直接检查 libcuda.so.1 文件（这是主要的符号链接）
        cuda_lib="${lib_dir}/libcuda.so.1"
        if [ -f "${cuda_lib}" ] || [ -L "${cuda_lib}" ]; then
            # 获取实际指向的文件名
            real_file=$(readlink -f "${cuda_lib}")
            if [ -f "${real_file}" ]; then
                HOST_DRIVER_VERSION=$(basename "${real_file}" | awk -F'so.' '{print $2}')
                HOST_LIB_PATH="${lib_dir}"
                FOUND_LIBS_DIR="${lib_dir}"
                echo "  ✓ 找到驱动库目录: ${lib_dir}"
                echo "  ✓ 检测到驱动版本: ${HOST_DRIVER_VERSION}"
                break
            fi
        else
            echo "  - 未在 ${lib_dir} 找到 libcuda.so.1"
        fi
    else
        echo "  - 目录不存在: ${lib_dir}"
    fi
done

if [ -z "${HOST_DRIVER_VERSION}" ]; then
    echo ""
    echo "❌ 错误: 未能在任何标准目录找到 libcuda.so！"
    echo "   请检查 NVIDIA 驱动是否正确安装"
    echo ""
    echo "可能的解决方案："
    echo "1. 运行: sudo apt update && sudo apt install nvidia-driver-XXX (XXX 为你的 GPU 对应的版本)"
    echo "2. 或从 NVIDIA 官网下载对应版本的驱动安装"
    exit 1
fi

echo ""
echo "3. 检查具体驱动库文件..."

# 3. 检查所有需要的库文件
MISSING_LIBS=()
FOUND_LIBS=()

for lib in "${LIBS_TO_CHECK[@]}"; do
    real_file="${HOST_LIB_PATH}/${lib}.${HOST_DRIVER_VERSION}"
    if [ -f "${real_file}" ]; then
        FOUND_LIBS+=("${lib}")
        echo "✓ ${lib} (版本: ${HOST_DRIVER_VERSION})"
    else
        MISSING_LIBS+=("${lib}")
        echo "❌ ${lib} (版本: ${HOST_DRIVER_VERSION}) - 文件不存在"
    fi
done

echo ""
echo "4. 检查额外新库 (550.54.15 版本特有)..."

MISSING_EXTRA_LIBS=()
FOUND_EXTRA_LIBS=()

for lib in "${EXTRA_NEW_LIBS[@]}"; do
    # 这些库可能不存在于旧版本驱动中，这是正常的
    real_file="${HOST_LIB_PATH}/${lib}.${HOST_DRIVER_VERSION}"
    if [ -f "${real_file}" ]; then
        FOUND_EXTRA_LIBS+=("${lib}")
        echo "✓ ${lib} (版本: ${HOST_DRIVER_VERSION})"
    else
        MISSING_EXTRA_LIBS+=("${lib}")
        echo "⚠️ ${lib} (版本: ${HOST_DRIVER_VERSION}) - 不存在 (正常现象，新库)"
    fi
done

echo ""
echo "=== 检查结果汇总 ==="

echo "宿主机驱动版本: ${HOST_DRIVER_VERSION}"
echo "驱动库位置: ${HOST_LIB_PATH}"
echo "目标伪装版本: ${DRIVER_VERSION}"
echo ""

echo "基础库检查 (${#LIBS_TO_CHECK[@]} 个):"
echo "✓ 找到: ${#FOUND_LIBS[@]} 个"
echo "❌ 缺失: ${#MISSING_LIBS[@]} 个"

if [ ${#MISSING_LIBS[@]} -gt 0 ]; then
    echo ""
    echo "缺失的基础库列表:"
    for lib in "${MISSING_LIBS[@]}"; do
        echo "  - ${lib}"
    done
fi

echo ""
echo "额外新库检查 (${#EXTRA_NEW_LIBS[@]} 个):"
echo "✓ 找到: ${#FOUND_EXTRA_LIBS[@]} 个"
echo "⚠️ 缺失: ${#MISSING_EXTRA_LIBS[@]} 个 (这些库在旧版本驱动中通常不存在)"

# 4. 给出建议
echo ""
echo "=== 执行建议 ==="

if [ ${#MISSING_LIBS[@]} -eq 0 ]; then
    echo "✅ 所有必需的驱动库都存在！"
    echo "   可以安全运行 setup_cuda_fake.sh"
else
    echo "⚠️ 有 ${#MISSING_LIBS[@]} 个必需的驱动库缺失"
    echo ""
    echo "可能的解决方案:"
    echo "1. 检查是否安装了完整的 NVIDIA 驱动:"
    echo "   sudo apt update && sudo apt install nvidia-driver-${HOST_DRIVER_VERSION%%.*}xx"
    echo ""
    echo "2. 如果是手动安装的驱动，确保包含了所有库文件"
    echo ""
    echo "3. 检查库文件权限:"
    echo "   sudo chmod 755 ${HOST_LIB_PATH}/*.so.*"
    echo ""
    echo "4. 重新安装驱动或升级到更新的版本"
    echo ""
    echo "注意: setup_cuda_fake.sh 脚本会为缺失的库创建占位符，"
    echo "      但这可能影响某些 GPU 功能的使用"
fi

echo ""
echo "当前系统信息:"
echo "- 内核版本: $(uname -r)"
echo "- 架构: $(uname -m)"
if command -v lsb_release &> /dev/null; then
    echo "- 发行版: $(lsb_release -d | cut -f2)"
fi
