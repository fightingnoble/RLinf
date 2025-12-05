# 本地离线安装配置说明

本文档说明如何配置和使用 RLinf 的本地离线安装功能。

## 概述

为了支持离线或网络受限环境下的安装，我们提供了本地资源检测和使用功能。安装脚本会自动检测本地是否有所需的 Git 仓库和 Wheel 包，优先使用本地资源，如果本地不存在则自动回退到远程下载。

## 目录结构

```
RLinf/
├── docker/torch-2.6/
│   ├── repos/                      # 本地资源目录
│   │   ├── latex2sympy2/          # Git 仓库（扁平结构）
│   │   ├── ManiSkill/
│   │   ├── LIBERO/
│   │   ├── BEHAVIOR-1K/
│   │   ├── openvla/
│   │   ├── openvla-oft/
│   │   ├── openpi/
│   │   ├── Megatron-LM/
│   │   └── wheels/                # Wheel 包目录
│   │       ├── flash_attn-...-cp310-cp310-linux_x86_64.whl
│   │       ├── flash_attn-...-cp311-cp311-linux_x86_64.whl
│   │       └── apex-0.1-cp311-cp311-linux_x86_64.whl
│   └── download_repos.sh          # 自动下载脚本
└── requirements/
    └── install.sh                  # 安装脚本（支持本地资源检测）
```

## 使用方法

### 1. 下载依赖到本地

在有网络的环境中，运行下载脚本：

```bash
cd /path/to/RLinf
./docker/torch-2.6/download_repos.sh
```

此脚本会下载：
- **8 个 Git 仓库**：latex2sympy2, ManiSkill, LIBERO, BEHAVIOR-1K, openvla, openvla-oft, openpi, Megatron-LM
- **3 个 Wheel 包**：flash-attn (cp310/cp311), apex (cp311)

### 2. 运行安装

在项目根目录运行 `install.sh`：

```bash
cd /path/to/RLinf
bash requirements/install.sh <target>
```

安装脚本会自动：
1. 检测 `docker/torch-2.6/repos` 目录是否存在
2. 如果存在相应的本地资源，使用本地副本（加速安装，支持离线）
3. 如果不存在，自动从远程下载

### 3. 支持的安装目标

- `openvla`: OpenVLA 模型
- `openvla-oft`: OpenVLA-OFT 模型
  - 添加 `--enable-behavior` 启用 BEHAVIOR-1K 支持
- `openpi`: OpenPI 模型
- `reason`: 推理模型（Megatron-LM + SGLang/vLLM）

示例：
```bash
# 安装 OpenVLA
bash requirements/install.sh openvla

# 安装 OpenVLA-OFT 并启用 BEHAVIOR
bash requirements/install.sh openvla-oft --enable-behavior

# 安装推理环境
bash requirements/install.sh reason
```

## 功能特性

### 1. Git 仓库本地检测

`install.sh` 会检测以下位置的本地 Git 仓库：
- `docker/torch-2.6/repos/<repo_name>/`

如果存在，会使用 `file://` 协议或直接复制，避免网络下载。

### 2. Wheel 包本地检测

安装脚本会检测 `docker/torch-2.6/repos/wheels/` 目录下的 Wheel 包：
- Flash Attention (Python 3.10, 3.11)
- Apex (Python 3.11)

如果存在本地 Wheel，会优先使用本地文件而不是从 GitHub releases 下载。

### 3. Requirements 文件处理

`install.sh` 会动态处理以下文件：
- `requirements/openvla.txt`
- `requirements/openvla_oft.txt`
- `requirements/openpi.txt`
- `requirements/megatron.txt`

自动替换其中的 Git 仓库 URL 和 Wheel URL 为本地路径（如果本地存在）。

### 4. Pyproject.toml 处理

安装过程中会临时修改 `pyproject.toml` 中的 Git 依赖 URL 为本地路径，安装完成后自动恢复原文件。

## 分支管理策略

### Git Remote 配置

```
origin    → git@github.com:fightingnoble/RLinf.git  (你的仓库)
upstream  → git@github.com:RLinf/RLinf.git           (原仓库)
```

### 分支结构

- **main**: 与 `origin/main` 同步，保持干净以便随时同步 upstream
- **release/v0.1**: 与 `origin/release/v0.1` 同步，保持干净
- **local_install_merged**: 基于 `release/v0.1`，包含本地安装优化
- **cu121_docker_build**: 基于 `release/v0.1`，Docker 构建优化
- **cu121_driver_modify**: 基于 `release/v0.1`，CUDA 驱动处理

### 更新工作流

从 upstream 同步更新：

```bash
# 1. 更新 main 和 release/v0.1
git checkout main
git pull upstream main

git checkout release/v0.1
git pull upstream release/v0.1

# 2. Rebase 工作分支
git checkout local_install_merged
git rebase release/v0.1

git checkout cu121_docker_build
git rebase release/v0.1

git checkout cu121_driver_modify
git rebase release/v0.1

# 3. 推送到你的远程仓库
git push origin main
git push origin release/v0.1
git push origin local_install_merged --force-with-lease
git push origin cu121_docker_build --force-with-lease
git push origin cu121_driver_modify --force-with-lease
```

## 依赖列表

### Git 仓库

| 仓库 | URL | 分支/标签 | 用途 |
|------|-----|-----------|------|
| latex2sympy2 | https://github.com/RLinf/latex2sympy2.git | default | 数学符号处理 |
| ManiSkill | https://github.com/haosulab/ManiSkill.git | default | 机器人仿真环境 |
| LIBERO | https://github.com/RLinf/LIBERO.git | default | 机器人任务库 |
| BEHAVIOR-1K | https://github.com/RLinf/BEHAVIOR-1K.git | RLinf/v3.7.1 | 行为任务数据集 |
| openvla | https://github.com/openvla/openvla.git | default | OpenVLA 模型 |
| openvla-oft | https://github.com/moojink/openvla-oft.git | default | OpenVLA-OFT 模型 |
| openpi | https://github.com/RLinf/openpi.git | default | OpenPI 模型 |
| Megatron-LM | https://github.com/NVIDIA/Megatron-LM.git | core_r0.13.0 | Megatron 训练框架 |

### Wheel 包

| 包名 | URL | Python 版本 | 用途 |
|------|-----|------------|------|
| flash-attn | [v2.7.4.post1+cu12torch2.5](https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.5cxx11abiFALSE-cp310-cp310-linux_x86_64.whl) | 3.10 | Flash Attention (BEHAVIOR) |
| flash-attn | [v2.7.4.post1+cu12torch2.6](https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.6cxx11abiFALSE-cp311-cp311-linux_x86_64.whl) | 3.11 | Flash Attention (主要环境) |
| apex | [v25.09](https://github.com/RLinf/apex/releases/download/25.09/apex-0.1-cp311-cp311-linux_x86_64.whl) | 3.11 | NVIDIA Apex (reason) |

## 优化策略

### Apex 安装优化

在 `reason` 模式下，如果本地存在 Apex wheel 包，会优先使用 wheel 安装而不是从源码编译。这可以显著加快安装速度（从数十分钟降低到几秒）。

### Flash Attention 安装优化

所有需要 Flash Attention 的环境都会优先使用本地 wheel，避免从 GitHub releases 下载大文件（~180MB）。

### Git 仓库复制优化

当从本地复制 Git 仓库时，使用 `cp -a` 保留所有属性和链接，避免重新下载 Git 历史。

## 故障排除

### 问题：安装时提示找不到本地仓库

**原因**：`docker/torch-2.6/repos` 目录不存在或为空。

**解决**：运行 `./docker/torch-2.6/download_repos.sh` 下载依赖。

### 问题：Git clone 失败，提示认证错误

**原因**：使用 HTTPS 协议克隆私有仓库。

**解决**：确保仓库是公开的，或使用 SSH 协议（修改 `download_repos.sh` 中的 URL）。

### 问题：Wheel 安装失败

**原因**：Python 版本不匹配或 CUDA 版本不兼容。

**解决**：
- 检查 Python 版本是否正确（`python --version`）
- 检查 CUDA 版本是否为 12.1/12.2（`nvcc --version`）
- 如果版本不匹配，从远程下载正确版本的 wheel

## 维护和更新

### 更新本地资源

重新运行下载脚本即可：

```bash
./docker/torch-2.6/download_repos.sh
```

脚本会自动跳过已存在的文件，并更新 Git 仓库到最新版本。

### 添加新依赖

1. 编辑 `docker/torch-2.6/download_repos.sh`
2. 添加相应的 `clone_or_update_repo` 或 `download_file` 调用
3. 运行脚本下载新依赖
4. 更新 `requirements/install.sh`（如果需要）

## 注意事项

1. **磁盘空间**：确保有足够的磁盘空间（约 5-10 GB）
2. **网络环境**：首次下载需要良好的网络连接（或代理）
3. **`.gitignore`**：`docker/torch-2.6/repos` 已添加到 `.gitignore`，不会提交到 Git
4. **分支隔离**：所有本地安装修改都在 `local_install_merged` 分支，不影响 `main` 和 `release/v0.1`

## 贡献者

此本地安装功能由以下改进组成：
- 本地 Git 仓库检测和复用
- 本地 Wheel 包检测和使用
- 自动下载脚本
- Requirements 文件动态处理
- Pyproject.toml 临时修改和恢复

