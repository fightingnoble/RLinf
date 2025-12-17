#!/usr/bin/env python3
"""
测试 timm 修复方案
"""

import os
import sys

# 方案 1: 在导入前禁用 JIT
print("=" * 80)
print("方案 1: 禁用 PyTorch JIT")
print("=" * 80)

# 必须在导入 torch 之前设置
os.environ['PYTORCH_JIT'] = '0'
os.environ['TORCH_JIT'] = '0'
os.environ['TORCH_DISABLE_JIT'] = '1'

print("设置环境变量:")
print("  PYTORCH_JIT=0")
print("  TORCH_JIT=0")
print("  TORCH_DISABLE_JIT=1")
print()

# 现在导入 torch
import torch
print(f"PyTorch 版本: {torch.__version__}")

# 尝试禁用 JIT
try:
    torch.jit._state.enable = False
    print("✓ 已禁用 torch.jit._state.enable")
except:
    print("⚠ 无法设置 torch.jit._state.enable")

print("\n尝试导入 timm...")
try:
    import timm
    print(f"✓ timm 导入成功！版本: {timm.__version__}")
    sys.exit(0)
except Exception as e:
    print(f"✗ timm 导入失败: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

