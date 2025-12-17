#!/bin/bash
# 检查依赖冲突的脚本

set -e

echo "=========================================="
echo "依赖冲突检查报告"
echo "=========================================="
echo

# 激活虚拟环境（如果在容器内）
if [ -f ".venv/bin/activate" ]; then
    source .venv/bin/activate
fi

echo "1. pip check 结果："
echo "----------------------------------------"
pip check 2>&1 || true
echo

echo "2. 关键包版本："
echo "----------------------------------------"
echo "PyTorch 相关："
pip show torch torchvision torchaudio 2>/dev/null | grep -E "(Name|Version)" || true
echo

echo "OpenVLA 相关："
pip show openvla 2>/dev/null | grep -E "(Name|Version|Requires)" || true
echo

echo "TIMM 相关："
pip show timm 2>/dev/null | grep -E "(Name|Version|Requires)" || true
echo

echo "3. 冲突的包版本详情："
echo "----------------------------------------"
echo "protobuf:"
pip show protobuf 2>/dev/null | grep -E "(Name|Version)" || true
echo "  - opentelemetry-proto 需要: protobuf<7.0,>=5.0"
echo "  - 当前版本: $(pip show protobuf 2>/dev/null | grep Version | awk '{print $2}' || echo '未知')"
echo

echo "wrapt:"
pip show wrapt 2>/dev/null | grep -E "(Name|Version)" || true
echo "  - swanlab 需要: wrapt>=1.17.0"
echo "  - 当前版本: $(pip show wrapt 2>/dev/null | grep Version | awk '{print $2}' || echo '未知')"
echo

echo "typeguard:"
pip show typeguard 2>/dev/null | grep -E "(Name|Version)" || true
echo "  - tyro 需要: typeguard>=4.0.0"
echo "  - 当前版本: $(pip show typeguard 2>/dev/null | grep Version | awk '{print $2}' || echo '未知')"
echo

echo "4. PyTorch 版本冲突："
echo "----------------------------------------"
echo "openvla 需要: torch==2.2.0, torchvision==0.17.0, torchaudio==2.2.0"
echo "当前安装:"
pip show torch torchvision torchaudio 2>/dev/null | grep -E "(Name|Version)" || true
echo "  - 注意: 通过 override-dependencies 强制使用 torch 2.6.0"
echo

echo "5. 测试 timm 导入（可能崩溃）："
echo "----------------------------------------"
timeout 5 python -c "import timm; print(f'timm {timm.__version__} 导入成功')" 2>&1 || echo "✗ timm 导入失败或崩溃"
echo

echo "=========================================="
echo "检查完成"
echo "=========================================="

