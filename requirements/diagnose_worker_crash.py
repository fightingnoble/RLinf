#!/usr/bin/env python3
"""
诊断脚本：检查 Ray worker 崩溃的可能原因
运行方式：python requirements/diagnose_worker_crash.py
"""

import sys
import os

def check_cuda():
    """检查 CUDA 环境"""
    print("=" * 80)
    print("CUDA 环境检查")
    print("=" * 80)
    try:
        import torch
        print(f"✓ PyTorch 版本: {torch.__version__}")
        print(f"✓ CUDA 可用: {torch.cuda.is_available()}")
        if torch.cuda.is_available():
            print(f"✓ CUDA 版本: {torch.version.cuda}")
            print(f"✓ GPU 数量: {torch.cuda.device_count()}")
            for i in range(torch.cuda.device_count()):
                print(f"  - GPU {i}: {torch.cuda.get_device_name(i)}")
                print(f"    内存: {torch.cuda.get_device_properties(i).total_memory / 1024**3:.2f} GB")
        else:
            print("✗ CUDA 不可用！")
            return False
    except ImportError as e:
        print(f"✗ PyTorch 导入失败: {e}")
        return False
    except Exception as e:
        print(f"✗ CUDA 检查失败: {e}")
        return False
    return True

def check_flash_attention():
    """检查 Flash Attention"""
    print("\n" + "=" * 80)
    print("Flash Attention 检查")
    print("=" * 80)
    try:
        import flash_attn
        print(f"✓ Flash Attention 版本: {flash_attn.__version__}")
        
        # 尝试导入关键模块
        from flash_attn import flash_attn_func
        print("✓ flash_attn_func 导入成功")
        
        # 检查 CUDA 扩展
        try:
            import flash_attn_2_cuda
            print("✓ flash_attn_2_cuda 扩展可用")
        except ImportError as e:
            print(f"✗ flash_attn_2_cuda 扩展不可用: {e}")
            return False
            
    except ImportError as e:
        print(f"✗ Flash Attention 导入失败: {e}")
        print("  提示: 确保 flash-attention 已正确安装")
        return False
    except Exception as e:
        print(f"✗ Flash Attention 检查失败: {e}")
        return False
    return True

def check_system_resources():
    """检查系统资源"""
    print("\n" + "=" * 80)
    print("系统资源检查")
    print("=" * 80)
    try:
        import psutil
        process = psutil.Process()
        mem_info = process.memory_info()
        print(f"✓ 当前进程 RSS 内存: {mem_info.rss / 1024**3:.2f} GB")
        print(f"✓ 当前进程 VMS 内存: {mem_info.vms / 1024**3:.2f} GB")
        
        sys_mem = psutil.virtual_memory()
        print(f"✓ 系统总内存: {sys_mem.total / 1024**3:.2f} GB")
        print(f"✓ 系统可用内存: {sys_mem.available / 1024**3:.2f} GB")
        print(f"✓ 系统内存使用率: {sys_mem.percent}%")
        
        if sys_mem.percent > 90:
            print("⚠ 警告: 系统内存使用率超过 90%，可能导致 OOM")
            return False
            
    except ImportError:
        print("⚠ psutil 未安装，跳过系统内存检查")
        print("  安装: pip install psutil")
    except Exception as e:
        print(f"✗ 系统资源检查失败: {e}")
        return False
    return True

def check_ray():
    """检查 Ray 环境"""
    print("\n" + "=" * 80)
    print("Ray 环境检查")
    print("=" * 80)
    try:
        import ray
        print(f"✓ Ray 版本: {ray.__version__}")
        if ray.is_initialized():
            print("✓ Ray 已初始化")
            print(f"  - 地址: {ray.get_runtime_context().gcs_address}")
        else:
            print("ℹ Ray 未初始化（这是正常的，如果只是检查环境）")
    except ImportError as e:
        print(f"✗ Ray 导入失败: {e}")
        return False
    except Exception as e:
        print(f"✗ Ray 检查失败: {e}")
        return False
    return True

def check_environment_variables():
    """检查环境变量"""
    print("\n" + "=" * 80)
    print("环境变量检查")
    print("=" * 80)
    important_vars = [
        "LOCAL_RANK", "RANK", "WORLD_SIZE",
        "CUDA_VISIBLE_DEVICES", "MASTER_ADDR", "MASTER_PORT"
    ]
    for var in important_vars:
        value = os.environ.get(var, "未设置")
        print(f"  {var}: {value}")

def check_model_imports():
    """检查模型相关导入"""
    print("\n" + "=" * 80)
    print("模型相关导入检查")
    print("=" * 80)
    try:
        from rlinf.models import get_model
        print("✓ get_model 导入成功")
    except ImportError as e:
        print(f"✗ get_model 导入失败: {e}")
        return False
    except Exception as e:
        print(f"✗ 模型导入检查失败: {e}")
        return False
    return True

def main():
    """主函数"""
    print("\n" + "=" * 80)
    print("Ray Worker 崩溃诊断工具")
    print("=" * 80)
    print()
    
    results = []
    
    results.append(("CUDA 环境", check_cuda()))
    results.append(("Flash Attention", check_flash_attention()))
    results.append(("系统资源", check_system_resources()))
    results.append(("Ray 环境", check_ray()))
    results.append(("模型导入", check_model_imports()))
    check_environment_variables()
    
    print("\n" + "=" * 80)
    print("诊断总结")
    print("=" * 80)
    all_passed = True
    for name, passed in results:
        status = "✓ 通过" if passed else "✗ 失败"
        print(f"{name}: {status}")
        if not passed:
            all_passed = False
    
    if all_passed:
        print("\n✓ 所有检查通过！")
        print("如果仍然出现崩溃，请检查:")
        print("  1. 模型文件是否存在且完整")
        print("  2. 配置文件中的路径是否正确")
        print("  3. 查看完整的 Ray worker 日志: find /tmp/ray -name '*.log'")
    else:
        print("\n✗ 部分检查失败，请根据上述信息修复问题")
    
    print("=" * 80)
    return 0 if all_passed else 1

if __name__ == "__main__":
    sys.exit(main())

