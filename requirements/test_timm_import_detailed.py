#!/usr/bin/env python3
"""
详细测试 timm 导入问题
逐步测试以定位崩溃点
"""

import os
import sys

print("=" * 80)
print("TIMM 导入详细测试")
print("=" * 80)
print()

# 步骤 1: 基础导入
print("[步骤 1] 导入基础库...")
try:
    import torch
    print(f"  ✓ torch {torch.__version__}")
except Exception as e:
    print(f"  ✗ torch 导入失败: {e}")
    sys.exit(1)

# 步骤 2: 尝试禁用 JIT
print("\n[步骤 2] 尝试禁用 PyTorch JIT...")
os.environ['PYTORCH_JIT'] = '0'
os.environ['TORCH_JIT'] = '0'
print("  设置环境变量: PYTORCH_JIT=0, TORCH_JIT=0")

# 步骤 3: 逐步导入 timm
print("\n[步骤 3] 逐步导入 timm...")

# 3.1 导入 timm 主模块
print("  3.1 导入 timm...", end=" ", flush=True)
try:
    import timm
    print(f"✓ 成功 (版本: {timm.__version__})")
except Exception as e:
    print(f"✗ 失败: {e}")
    sys.exit(1)

# 3.2 导入 timm.layers
print("  3.2 导入 timm.layers...", end=" ", flush=True)
try:
    from timm import layers
    print("✓ 成功")
except Exception as e:
    print(f"✗ 失败: {e}")
    sys.exit(1)

# 3.3 导入 timm.layers.activations_me（这是崩溃点）
print("  3.3 导入 timm.layers.activations_me...", end=" ", flush=True)
try:
    from timm.layers import activations_me
    print("✓ 成功")
except Exception as e:
    print(f"✗ 失败: {e}")
    import traceback
    traceback.print_exc()
    sys.exit(1)

print("\n" + "=" * 80)
print("所有测试通过！")
print("=" * 80)

