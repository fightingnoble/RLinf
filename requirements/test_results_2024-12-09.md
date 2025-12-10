# RLinf 端到端离线安装测试报告

**测试日期**: 2024-12-09  
**测试环境**: Docker 容器 (nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04)  
**安装目标**: embodied --model openvla --env maniskill_libero  
**Python 版本**: 3.11.0rc1

---

## 测试流程

### 1. 环境准备

```bash
# 清理旧容器和镜像
docker stop rlinf_local && docker rm rlinf_local
docker rmi rlinf-zsh

# 重新构建镜像
bash requirements/docker_launch.sh

# 启动容器（后台运行）
docker run -d --gpus all --shm-size 100g --net=host \
  --name rlinf_local \
  -v /home/zhangchenguang/git_repo/RLinf:/root/git_repo/RLinf \
  -v /home/zhangchenguang/git_repo/RLinf/docker/torch-2.6/repos:/cache/z30081742/rlinf/repos \
  -e extrenal_repo=/cache/z30081742/rlinf/repos \
  rlinf-zsh sleep infinity
```

### 2. 安装过程

#### Stage 1: Prepare

```bash
bash requirements/install.sh prepare --python /usr/bin/python3.11
```

**结果**: ✅ 成功
- 安装了 Python 3.11.0rc1
- 配置了系统依赖
- 设置了环境变量

#### Stage 2: Embodied Installation

```bash
bash requirements/install.sh embodied \
  --model openvla \
  --env maniskill_libero \
  --python /usr/bin/python3.11
```

**结果**: ✅ 成功（有部分从远程下载）

---

## 测试结果分析

### ✅ 成功使用本地路径的依赖

| 依赖名称 | 来源 | 验证状态 |
|---------|------|---------|
| `latex2sympy2` | `file:///cache/z30081742/rlinf/repos/latex2sympy2` | ✅ |
| `openvla` | `file:///cache/z30081742/rlinf/repos/openvla` (通过 requirements 文件) | ✅ |
| `LIBERO` | `file:///cache/z30081742/rlinf/repos/LIBERO` (clone_or_copy_repo) | ✅ |
| ManiSkill Assets | `/cache/z30081742/rlinf/repos/assets/.maniskill` | ✅ |
| SAPIEN PhysX | `/cache/z30081742/rlinf/repos/assets/.sapien/physx` | ✅ |

日志证据：
```
[local-deps] Patching local repos...
[local-deps] Patching main pyproject.toml...
=== Local path replacements in main pyproject.toml ===
    "latex2sympy2 @ git+file:///cache/z30081742/rlinf/repos/latex2sympy2",

Updating file:///cache/z30081742/rlinf/repos/latex2sympy2 (HEAD)
Updated file:///cache/z30081742/rlinf/repos/latex2sympy2 (35fa1005d4cd9149d08c0b6f7efb233e4bbd25f7)

Using local repository: /cache/z30081742/rlinf/repos/LIBERO -> .venv/libero

[download_assets] Copying ManiSkill assets from local directory
[download_assets] Successfully copied ManiSkill assets from local directory.
```

### ⚠️ 仍从远程下载的依赖

| 依赖名称 | 实际来源 | 问题描述 |
|---------|---------|---------|
| `dlimp_openvla` | `git+https://github.com/moojink/dlimp_openvla` | openvla 的子依赖，应使用本地路径 |
| `ManiSkill` | `git+https://github.com/haosulab/ManiSkill.git` | 应使用本地路径 |

日志证据：
```
Updating https://github.com/moojink/dlimp_openvla (HEAD)
Updated https://github.com/moojink/dlimp_openvla (040105d256bd28866cc6620621a3d5f7b6b91b46)

Updating https://github.com/haosulab/ManiSkill.git (HEAD)
Updated https://github.com/haosulab/ManiSkill.git (81d3a4320babadc0add4e6f9ee61050d0903576a)

Building dlimp @ git+https://github.com/moojink/dlimp_openvla@040105d256bd28866cc6620621a3d5f7b6b91b46
Building mani-skill @ git+https://github.com/haosulab/ManiSkill.git@81d3a4320babadc0add4e6f9ee61050d0903576a
```

### ✅ PyPI 镜像正常工作

- 所有 PyPI 包均从 `https://mirrors.bfsu.edu.cn/pypi/web/simple` 下载
- 总计下载约 170+ 个 PyPI wheel 包
- 主要大包：torch (731MB), tensorflow (591MB), nvidia-cudnn-cu12 (634MB) 等

---

## 问题分析

### 问题 1: dlimp_openvla 未使用本地路径

**原因**：
- `openvla.txt` 中的 `openvla` 已被替换为 `file://` 路径
- 但 `openvla` 的 `pyproject.toml` 中的 `dlimp` 子依赖未被替换
- 当前的 `patch_local_repos_pyprojects()` 只在启动时执行一次，但 `openvla.txt` 中的包是通过 `uv pip install -r` 安装的，不走 `uv sync` 流程

**当前流程**：
```
install.sh 启动
  ↓
patch_all_pyprojects_for_install  # 只修改本地 repos/openvla/pyproject.toml
  ↓
patch_all_requirements_for_install  # 修改 openvla.txt (openvla URL)
  ↓
uv pip install -r openvla.txt
  ↓
uv 读取 file://repos/openvla  # 读到的是原始 pyproject.toml ❌
  ↓
dlimp 从 https 下载
```

**根本原因**：
- `patch_all_pyprojects_for_install` 应该在脚本启动时就修改 `repos/openvla/pyproject.toml`
- 但修改后的文件在 `trap EXIT` 时会被恢复
- 导致 `uv pip install` 时读到的仍是原始版本

**解决方案**：
需要修改 `patch_all_pyprojects_for_install` 的时机，确保：
1. 在所有安装命令执行前修改
2. 在所有安装命令执行后才恢复

### 问题 2: ManiSkill 未使用本地路径

**原因**：
- `maniskill.txt` 中直接写的是 `git+https://github.com/haosulab/ManiSkill.git`
- `patch_all_requirements_for_install` 应该已经替换，但可能匹配失败

**检查**：
需要查看 `maniskill.txt` 的实际内容和 `patch_all_requirements_for_install` 的替换逻辑

---

## 建议改进

### 短期方案（修复当前问题）

1. **修复 trap 时机**：
   - 将 `trap EXIT` 改为在所有安装完成后手动调用 `restore_all_*`
   - 或者在每个安装命令前重新 patch

2. **检查 maniskill.txt 替换逻辑**：
   - 确认 `ManiSkill` 仓库名匹配规则
   - 可能需要特殊处理大小写或特殊字符

### 长期方案（优化架构）

1. **简化 patch 机制**：
   - 不使用 trap 自动恢复
   - 安装前 patch，安装后手动恢复
   - 或者使用临时副本，不修改原文件

2. **统一路径管理**：
   - 所有 requirements 文件在加载前统一处理
   - 所有 pyproject.toml 在第一次访问前统一处理

---

## 测试覆盖率

| 安装目标 | 测试状态 | 备注 |
|---------|---------|------|
| embodied + openvla + maniskill_libero | ✅ 部分成功 | 主要依赖已使用本地，子依赖待修复 |
| embodied + openvla-oft | ❌ 未测试 | - |
| embodied + openpi | ❌ 未测试 | - |
| reason | ❌ 未测试 | - |

---

## 附录：完整安装日志

安装日志保存在容器内：`/tmp/install_full.log`

查看方式：
```bash
docker exec rlinf_local cat /tmp/install_full.log
```

---

## 下一步行动

1. ✅ 修复 `trap EXIT` 时机问题
2. ✅ 检查并修复 `maniskill.txt` 替换逻辑
3. ⬜ 重新运行完整测试
4. ⬜ 测试其他安装目标（openvla-oft, openpi, reason）
5. ⬜ 验证完全离线环境（`--network none`）

