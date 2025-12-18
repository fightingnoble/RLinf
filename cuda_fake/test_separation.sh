#!/bin/bash
# 测试分离式架构的脚本

echo "🧪 测试 RLinf Docker 分离式架构"
echo "=================================="

# 测试 1: 检查脚本存在性
echo ""
echo "1. 检查脚本存在性..."
scripts=("setup_cuda_drivers.sh" "setup_cuda_fake.sh" "launch_docker_custom.sh" "docker_init.sh" "check_drivers.sh")
for script in "${scripts[@]}"; do
    if [ -f "$script" ] && [ -x "$script" ]; then
        echo "   ✓ $script 存在且可执行"
    else
        echo "   ❌ $script 不存在或不可执行"
    fi
done

# 测试 2: 检查语法
echo ""
echo "2. 检查脚本语法..."
for script in "${scripts[@]}"; do
    if bash -n "$script" 2>/dev/null; then
        echo "   ✓ $script 语法正确"
    else
        echo "   ❌ $script 语法错误"
    fi
done

# 测试 3: 检查配置文件
echo ""
echo "3. 检查配置文件..."
configs=(".zshrc" ".proxy_env")
for config in "${configs[@]}"; do
    if [ -f "$config" ]; then
        echo "   ✓ $config 存在"
    else
        echo "   ❌ $config 不存在"
    fi
done

# 测试 4: 检查 CUDA 环境
echo ""
echo "4. 检查 CUDA 环境状态..."
WORK_DIR="$HOME/cuda-fake"
TOOLKIT_DIR="${WORK_DIR}/cuda-12.4"
COMPAT_DIR="${TOOLKIT_DIR}/compat"

if [ -d "${TOOLKIT_DIR}" ]; then
    echo "   ✓ CUDA Toolkit 目录存在: ${TOOLKIT_DIR}"
else
    echo "   ❌ CUDA Toolkit 目录不存在: ${TOOLKIT_DIR}"
fi

if [ -d "${COMPAT_DIR}" ] && [ "$(ls -A ${COMPAT_DIR})" ]; then
    echo "   ✓ CUDA 伪装层存在: ${COMPAT_DIR}"
    echo "   - 包含 $(ls -1 ${COMPAT_DIR} | wc -l) 个库文件"
else
    echo "   ❌ CUDA 伪装层不存在或为空: ${COMPAT_DIR}"
fi

# 测试 5: 验证分离逻辑
echo ""
echo "5. 验证分离逻辑..."

# 测试 setup_cuda_fake.sh 的环境检查（不实际启动容器）
echo "   - 测试环境检查逻辑..."
if bash -c "
    WORK_DIR=\"$WORK_DIR\"
    TOOLKIT_DIR=\"${TOOLKIT_DIR}\"
    COMPAT_DIR=\"${COMPAT_DIR}\"

    if [ ! -d \"\${TOOLKIT_DIR}\" ]; then
        echo '     ❌ TOOLKIT_DIR 检查失败'
        exit 1
    fi

    if [ ! -d \"\${COMPAT_DIR}\" ] || [ -z \"\$(ls -A \${COMPAT_DIR})\" ]; then
        echo '     ❌ COMPAT_DIR 检查失败'
        exit 1
    fi

    echo '     ✓ 环境检查逻辑正常'
" 2>/dev/null; then
    echo "   ✓ 环境检查逻辑正常"
else
    echo "   ❌ 环境检查逻辑异常"
fi

echo ""
echo "🎯 测试完成！"
echo ""
echo "使用说明："
echo "1. 如果 CUDA 环境未设置："
echo "   ./setup_cuda_drivers.sh"
echo ""
echo "2. 启动容器："
echo "   ./setup_cuda_fake.sh"
echo ""
echo "3. 检查驱动状态："
echo "   ./check_drivers.sh"
