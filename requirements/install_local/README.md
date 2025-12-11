# 本地离线安装配置说明

考虑到一些研发环境的服务器考虑到保密或者某些原因，可能无法访问互联网，因此我们提供了本地离线安装功能。
注意：
1. 机器无网络，但是有局域网内的pip源。如果机器有网络，请移步到[RLinf安装说明](../README.md)。
2. 如果pip 源都没有，需要额外打包uv 缓存，请自行查看uv 的文档。

本文档说明如何在离线环境下配置和使用 RLinf 的本地离线安装功能。

## 配置文件设置

首次使用前，需要创建本地配置文件 `requirements/config.local.sh`：

```bash
cd /path/to/RLinf
cp requirements/config.local.sh.example requirements/config.local.sh
# 编辑 config.local.sh，填入你的实际配置
```

配置文件包含以下隐私信息（不会被提交到 Git）：
- `PROXY_HOST`: 代理服务器地址
- `PROXY_PORT`: 代理服务器端口
- `SSH_KEY_EMAIL`: SSH 密钥邮箱
- `CACHE_DIR`: 容器内缓存目录路径
- `REPO_ROOT`: 项目根目录（可选，默认自动检测）

**重要**：`config.local.sh` 已被 `.gitignore` 忽略，请妥善保管。


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
│   │   ├── dlimp_openvla/
│   │   ├── openvla-oft/
│   │   ├── transformers-openvla-oft/
│   │   ├── openpi/
│   │   ├── Megatron-LM/
│   │   ├── cython/
│   │   ├── wheels/                 # Wheel 包目录
│   │   │   ├── flash_attn-...-cp310-cp310-linux_x86_64.whl
│   │   │   ├── flash_attn-...-cp311-cp311-linux_x86_64.whl
│   │   │   └── apex-0.1-cp311-cp311-linux_x86_64.whl
│   │   └── assets/                 # Assets 目录
│   │       ├── .maniskill/         # ManiSkill 数据集和机器人模型
│   │       ├── .sapien/            # SAPIEN PhysX
│   │       └── .cache/openpi/      # OpenPI tokenizer
└── requirements/
    ├── docker_test.sh              # 统一入口脚本（Docker/本地双模式）
    ├── docker_launch.sh            # Docker 镜像构建脚本
    ├── install_local_wrap.sh       # 核心安装+验证脚本（本地/Docker 共用）
    ├── install.sh                  # 安装脚本（支持本地资源检测）
    └── install_local/              # 本地安装工具目录
        ├── download.sh             # 下载脚本
        ├── restore.sh              # 还原脚本
        ├── README.md               # 本文档
        ├── url_replace.sh          # URL 替换工具
        ├── route.sh                # 路由函数
        └── prepare.sh              # 环境准备
```

## 概述

为了支持离线或网络受限环境下的安装，我们提供了本地资源检测和使用功能。安装脚本会自动检测本地是否有所需的 Git 仓库和 Wheel 包，优先使用本地资源，如果本地不存在则自动回退到远程下载。

**核心特性：**
- 自动检测本地 Git 仓库和 Wheel 包
- 支持 Docker 和本地两种运行模式
- 统一的安装和验证流程
- 离线优先，网络回退

## 快速开始

### 步骤 1：下载依赖到本地

在有网络的环境中，运行下载脚本：

```bash
cd /path/to/RLinf
bash requirements/install_local/download.sh
```

此脚本会下载所有依赖到 `docker/torch-2.6/repos/` 目录，包括：
- **Git 仓库**：latex2sympy2, ManiSkill, LIBERO, BEHAVIOR-1K, openvla, dlimp_openvla, openvla-oft, transformers-openvla-oft, openpi, Megatron-LM, cython
- **Wheel 包**：flash-attn (Python 3.10/3.11), apex (Python 3.11)
- **Assets**：ManiSkill 数据集和机器人模型、SAPIEN PhysX、OpenPI tokenizer

将下载的依赖复制到目标机器上。

### 步骤 2：运行安装

推荐通过统一入口脚本 `requirements/docker_test.sh`，支持 Docker 和本地两种模式。
设置CACHE_DIR 为下载依赖的目录。

Docker 模式适合无法使用预编译版本docker，但是有docker权限的用户。
本地模式适用于开发环境已经是docker内部，无法再安装docker的情况。

#### Docker 模式（默认）

```bash
cd /path/to/RLinf
bash requirements/docker_test.sh
# 或显式指定
bash requirements/docker_test.sh --mode docker
```

**流程：**
1. 检查/下载本地依赖：`requirements/install_local/download.sh`
2. 清理环境、还原备份：`requirements/install_local/restore.sh`
3. 构建 Docker 镜像：`requirements/docker_launch.sh`（传递宿主 UID/GID）
4. 启动容器并挂载本地缓存：`docker/torch-2.6/repos -> $CACHE_DIR`（CACHE_DIR 在 config.local.sh 中配置）
5. 容器内执行安装：`requirements/install_local_wrap.sh`
   - 清理 uv 缓存和虚拟环境
   - Prepare 阶段：安装 Python 3.11 和系统依赖
   - Embodied 安装：安装模型和环境
   - 验证安装结果
6. 日志输出：`/tmp/install_full.log`

#### 本地模式

直接在当前环境执行，同样复用本地资源：

```bash
cd /path/to/RLinf
bash requirements/docker_test.sh --mode local
```

**流程：**
1. 检查/下载本地依赖：`requirements/install_local/download.sh`
2. 清理环境、还原备份：`requirements/install_local/restore.sh`
3. 设置环境变量：`external_repo=$CACHE_DIR`（CACHE_DIR 在 config.local.sh 中配置）
4. 直接执行安装：`requirements/install_local_wrap.sh`（同 Docker 模式）
5. 日志输出：`/tmp/install_full.log`

### 步骤 3：支持的安装目标
见
具体请参考 `requirements/README.md`。


## 依赖列表

### Git 仓库

| 仓库 | URL | 分支/标签 | 用途 |
|------|-----|-----------|------|
| latex2sympy2 | https://github.com/RLinf/latex2sympy2.git | default | 数学符号处理 |
| ManiSkill | https://github.com/haosulab/ManiSkill.git | default | 机器人仿真环境 |
| LIBERO | https://github.com/RLinf/LIBERO.git | default | 机器人任务库 |
| BEHAVIOR-1K | https://github.com/RLinf/BEHAVIOR-1K.git | RLinf/v3.7.1 | 行为任务数据集 |
| openvla | https://github.com/openvla/openvla.git | default | OpenVLA 模型 |
| dlimp_openvla | https://github.com/moojink/dlimp_openvla.git | default | OpenVLA 数据处理库 |
| openvla-oft | https://github.com/moojink/openvla-oft.git | default | OpenVLA-OFT 模型 |
| transformers-openvla-oft | https://github.com/moojink/transformers-openvla-oft.git | default | OpenVLA-OFT Transformers 扩展 |
| openpi | https://github.com/RLinf/openpi.git | default | OpenPI 模型 |
| Megatron-LM | https://github.com/NVIDIA/Megatron-LM.git | core_r0.13.0 | Megatron 训练框架 |
| cython | https://github.com/cython/cython.git | default | Cython 编译器 |

### Wheel 包

| 包名 | URL | Python 版本 | 用途 |
|------|-----|------------|------|
| flash-attn | [v2.7.4.post1+cu12torch2.5](https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.5cxx11abiFALSE-cp310-cp310-linux_x86_64.whl) | 3.10 | Flash Attention (BEHAVIOR) |
| flash-attn | [v2.7.4.post1+cu12torch2.6](https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.6cxx11abiFALSE-cp311-cp311-linux_x86_64.whl) | 3.11 | Flash Attention (主要环境) |
| apex | [v25.09](https://github.com/RLinf/apex/releases/download/25.09/apex-0.1-cp311-cp311-linux_x86_64.whl) | 3.11 | NVIDIA Apex (reason) |

### Assets 资源

| 资源类型 | 来源 | 存储路径 | 用途 |
|---------|------|---------|------|
| ManiSkill bridge_v2_real2sim | HuggingFace | `assets/.maniskill/data/tasks/bridge_v2_real2sim_dataset/` | 真实到仿真数据集 |
| ManiSkill WidowX250S | GitHub | `assets/.maniskill/data/robots/widowx/` | WidowX 机器人模型 |
| SAPIEN PhysX | GitHub | `assets/.sapien/physx/105.1-physx-5.3.1.patch0/` | 物理引擎库 |
| OpenPI tokenizer | Google Cloud Storage | `assets/.cache/openpi/big_vision/paligemma_tokenizer.model` | OpenPI tokenizer 模型 |

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

`install.sh` 会递归扫描 `requirements/` 目录下的所有 `*.txt`（包括模型与环境的 requirements），如：
- `requirements/embodied/models/openvla.txt`
- `requirements/embodied/models/openvla_oft.txt`
- `requirements/embodied/models/openpi.txt`
- `requirements/embodied/envs/maniskill.txt`
- `requirements/embodied/envs/metaworld.txt`
- `requirements/reason/megatron.txt`

自动替换其中的 Git 仓库 URL 和 Wheel URL 为本地路径（如果本地存在）。

**调试输出（带颜色标记）：**
- 🟢 **绿色** - 成功使用本地资源：
  - `[local-deps] using local repo <repo_name> -> <local_path> in <file>`
  - `[local-deps] using local wheel <local_path> in <file>`
- 🟡 **黄色** - 未命中本地，回退远程：
  - `[local-deps] remote fallback for repo <repo_name> (not referenced) in <file>`
  - `[local-deps] remote fallback for <url> in <file>`
  - `[local-deps] remote wheel fallback <url> in <file>`
- 🔵 **青色** - 还原备份文件：
  - `[local-deps] restoring requirements backup <file>.backup -> <file>`
  - `[local-deps] restoring main pyproject backup ...`
  - `[local-deps] restoring repo pyproject backup ...`

### 4. Pyproject.toml 处理

安装过程中会临时修改 `pyproject.toml` 中的 Git 依赖 URL 为本地路径，安装完成后自动恢复原文件。

**文件状态流程：**
- **安装前**：`file`（原始文件，git URLs）
- **安装中**：`file`（修改后，file:// URLs）+ `file.backup`（原始备份）
- **安装后**：`file`（已恢复原始）+ `file.patched`（修改后版本，供调试）

说明：`.patched` 文件保留了所有本地路径替换的结果，可用于调试和对比（`diff file file.patched`）。

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

**解决**：运行 `bash requirements/install_local/download.sh` 下载依赖。

### 问题：Git clone 失败，提示认证错误

**原因**：使用 HTTPS 协议克隆私有仓库。

**解决**：确保仓库是公开的，或使用 SSH 协议（修改 `requirements/install_local/download.sh` 中的 URL）。

### 问题：Wheel 安装失败

**原因**：Python 版本不匹配或 CUDA 版本不兼容。

**解决**：
- 检查 Python 版本是否正确（`python --version`）
- 检查 CUDA 版本是否为 12.1/12.2（`nvcc --version`）
- 如果版本不匹配，从远程下载正确版本的 wheel

### 问题：Docker 容器内文件权限错误

**原因**：容器内创建的文件归 root 所有，挂载到宿主后无法访问。

**解决**：使用 Docker 模式时，`docker_launch.sh` 会自动传递宿主 UID/GID 构建镜像，确保文件权限正确。

## 维护和更新

### 更新本地资源

重新运行下载脚本即可：

```bash
bash requirements/install_local/download.sh
```

脚本会自动跳过已存在的文件，并更新 Git 仓库到最新版本。

### 添加新依赖

1. 编辑 `requirements/install_local/download.sh`
2. 在 `REPOS` 数组中添加 Git 仓库，或在 `WHEELS` 数组中添加 Wheel URL
3. 运行脚本下载新依赖
4. 更新 `requirements/install.sh`（如果需要）

## 注意事项

1. **磁盘空间**：确保有足够的磁盘空间（约 5-10 GB）
2. **网络环境**：首次下载需要良好的网络连接（或代理）
3. **`.gitignore`**：`docker/torch-2.6/repos` 已添加到 `.gitignore`，不会提交到 Git
4. **分支隔离**：所有本地安装修改都在 `local_install_merged` 分支，不影响 `main` 和 `release/v0.1`
5. **OpenPI tokenizer**：需要 `gsutil` 工具下载，如果未安装会自动跳过

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

## 贡献者

此本地安装功能由以下改进组成：
- 本地 Git 仓库检测和复用
- 本地 Wheel 包检测和使用
- 自动下载脚本
- Requirements 文件动态处理
- Pyproject.toml 临时修改和恢复
- Docker/本地双模式统一安装流程
