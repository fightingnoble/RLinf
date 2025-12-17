#!/usr/bin/env python3
"""
测试 timm 导入问题
用于复现 Segmentation fault 问题
"""

import os
import sys
import traceback

print("=" * 80)
print("TIMM 导入测试")
print("=" * 80)
print()

# 显示环境信息
print("1. 环境信息：")
print(f"   Python 版本: {sys.version}")
print(f"   Python 路径: {sys.executable}")
print()

# 检查 PyTorch
print("2. PyTorch 信息：")
try:
    import torch
    print(f"   ✓ PyTorch 版本: {torch.__version__}")
    print(f"   ✓ CUDA 可用: {torch.cuda.is_available()}")
    if torch.cuda.is_available():
        print(f"   ✓ CUDA 版本: {torch.version.cuda}")
        print(f"   ✓ cuDNN 版本: {torch.backends.cudnn.version()}")
except Exception as e:
    print(f"   ✗ PyTorch 导入失败: {e}")
    sys.exit(1)
print()

# 检查 JIT 设置
print("3. PyTorch JIT 设置：")
print(f"   PYTORCH_JIT: {os.environ.get('PYTORCH_JIT', '未设置')}")
print(f"   TORCH_JIT: {os.environ.get('TORCH_JIT', '未设置')}")
try:
    print(f"   torch.jit._state.enable: {torch.jit._state.enable}")
except:
    pass
print()

# 尝试导入 timm
print("4. 尝试导入 timm：")
print("   " + "-" * 76)
try:
    print("   正在导入 timm...")
    import timm
    print(f"   ✓ timm 导入成功")
    print(f"   ✓ timm 版本: {timm.__version__}")
except SystemExit as e:
    print(f"   ✗ timm 导入导致 SystemExit: {e}")
    traceback.print_exc()
    sys.exit(1)
except KeyboardInterrupt:
    print(f"   ✗ timm 导入被中断")
    sys.exit(1)
except Exception as e:
    print(f"   ✗ timm 导入失败: {type(e).__name__}: {e}")
    traceback.print_exc()
    sys.exit(1)
print()

# 尝试导入 timm 的具体模块
print("5. 尝试导入 timm 子模块：")
print("   " + "-" * 76)
modules_to_test = [
    "timm.layers",
    "timm.layers.activations_me",  # 这是导致崩溃的模块
    "timm.models",
    "timm.models.vision_transformer",
]

for module_name in modules_to_test:
    try:
        print(f"   导入 {module_name}...", end=" ")
        __import__(module_name)
        print("✓ 成功")
    except SystemExit as e:
        print(f"✗ SystemExit: {e}")
        traceback.print_exc()
        break
    except KeyboardInterrupt:
        print("✗ 被中断")
        break
    except Exception as e:
        print(f"✗ 失败: {type(e).__name__}: {e}")
        traceback.print_exc()
        break
print()

# 尝试使用 torch.jit.script（这是导致崩溃的操作）
print("6. 测试 torch.jit.script（可能导致崩溃）：")
print("   " + "-" * 76)
try:
    import torch.nn as nn
    
    class SimpleModel(nn.Module):
        def forward(self, x):
            return x * 2
    
    model = SimpleModel()
    print("   尝试 torch.jit.script...", end=" ")
    scripted = torch.jit.script(model)
    print("✓ 成功")
except SystemExit as e:
    print(f"✗ SystemExit: {e}")
    traceback.print_exc()
except KeyboardInterrupt:
    print("✗ 被中断")
except Exception as e:
    print(f"✗ 失败: {type(e).__name__}: {e}")
    traceback.print_exc()
print()

print("=" * 80)
print("测试完成")
print("=" * 80)

