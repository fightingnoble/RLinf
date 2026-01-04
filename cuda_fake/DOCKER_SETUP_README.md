# RLinf Docker 环境配置说明

## 🚀 快速开始

### 步骤 1: 设置 CUDA 驱动环境（一次性）
```bash
./setup_cuda_drivers.sh
```

### 步骤 2: 启动 Docker 容器
```bash
./setup_cuda_fake.sh
```

## 🔧 环境特性

### CUDA 版本伪装
- **目标**: 在 CUDA 12.1 宿主机上运行 CUDA 12.4 容器
- **实现**: 通过软链接伪装驱动库版本
- **兼容性**: 支持 PyTorch 等 CUDA 12.4 应用

### 开发环境增强
- ✅ **Zsh + Oh My Zsh**: 自动安装和配置
- ✅ **插件系统**:
  - `zsh-completions`: 命令补全
  - `zsh-syntax-highlighting`: 语法高亮
  - `zsh-autosuggestions`: 自动建议
  - `extract`: 解压别名
  - `web-search`: 网页搜索别名
- ✅ **代理支持**: 自动检测和配置
- ✅ **Docker-in-Docker**: 支持容器内运行 Docker
- ✅ **模块化配置**: 通过 `.alias` 目录实现配置模块化

### 文档合规
- ✅ **NVIDIA_DRIVER_CAPABILITIES**: 启用完整 GPU 支持
- ✅ **目录安全**: 不覆盖 `/root` 和 `/opt` 系统目录
- ✅ **HOME 环境变量**: 保持为 `/root`
- ✅ **用户权限映射**: 确保文件权限正确

## 📁 文件结构

```
cuda_fake/
├── setup_cuda_drivers.sh        # CUDA 驱动环境设置脚本（一次性运行）
├── setup_cuda_fake.sh           # Docker 容器启动脚本（推荐）
├── launch_docker_custom.sh      # Docker 容器启动脚本（自定义版本）
├── docker_init_from_dockerfile.sh # 容器内环境初始化脚本
├── check_drivers.sh             # 驱动检查脚本
├── test_separation.sh           # 测试脚本
├── .alias/                      # 别名和配置目录
│   ├── common.sh                # 通用别名和环境变量
│   ├── proxy.sh                 # 代理相关函数
│   └── rlinf_alias.sh           # RLinf 特定别名和函数
└── DOCKER_SETUP_README.md       # 本说明文档
```

## 🛠️ 使用说明

### 脚本说明

#### `setup_cuda_drivers.sh`
- **用途**: 设置 CUDA 12.1 → CUDA 12.4 伪装环境
- **运行频率**: 一次性设置（除非需要更新 CUDA 版本）
- **操作**: 下载安装 CUDA Toolkit，创建驱动库伪装
- **输出**: `$HOME/cuda-fake/` 目录下的伪装环境

#### `setup_cuda_fake.sh` (推荐)
- **用途**: 启动配置完整的 RLinf Docker 容器
- **前提**: 需要先运行 `setup_cuda_drivers.sh`
- **操作**: 检查环境，启动容器，自动安装zsh并初始化开发环境

#### `launch_docker_custom.sh`
- **用途**: 启动 RLinf Docker 容器的自定义版本，支持参数化配置
- **前提**: 需要先运行 `setup_cuda_drivers.sh`
- **操作**: 检查环境，启动容器，支持自定义容器名、镜像名和用户名
- **参数**: `[容器名] [镜像名] [用户名]` (均为可选)

#### `docker_init_from_dockerfile.sh`
- **用途**: 容器内环境初始化脚本
- **操作**: 安装 zsh/oh-my-zsh/插件，配置用户环境，加载别名配置
- **特点**: 基于 Dockerfile 逻辑的纯 shell 脚本实现

### 工作流程

```
首次使用:
1. ./setup_cuda_drivers.sh           # 设置 CUDA 环境（耗时，一次性）
2. ./launch_docker_custom.sh         # 启动容器并自动初始化环境

后续使用:
1. ./launch_docker_custom.sh [容器名] [镜像名] [用户名]  # 直接启动（支持参数化）

注意:
- 容器启动时会自动运行 docker_init_from_dockerfile.sh
- Oh My Zsh 和插件会在首次运行时自动安装
- 别名配置通过 .alias/ 目录下的文件自动加载
- CUDA 环境设置只需运行一次
```

### 自动初始化
容器首次启动时会自动运行初始化脚本，安装：
- Oh My Zsh
- Zsh 插件
- 开发工具配置

### 手动初始化
如果自动初始化失败，可以手动运行：

```bash
docker_init
```

### 常用命令

| 命令 | 说明 |
|------|------|
| `cdrl` | 进入 RLinf 工作目录 |
| `cdhome` | 返回主目录 |
| `gs` | Git 状态 |
| `ll` | 详细文件列表 |
| `gpu_mem` | GPU 内存使用情况 |
| `proxy_en` | 启用代理 |
| `proxy_dis` | 禁用代理 |
| `docker_init` | 手动运行初始化 |

### 别名配置系统

容器启动时会自动加载 `.alias/` 目录下的所有配置文件：

#### `.alias/common.sh`
- 通用别名：`python`, `pip`, `grep`, `egrep` 等
- 环境变量：`PATH`, `EDITOR`, `LANG` 等
- 系统设置：Git 配置、历史记录、补全等

#### `.alias/proxy.sh`
- 代理函数：`proxy_en()`, `proxy_dis()`
- 自动设置 HTTP/HTTPS 代理和 Git 代理

#### `.alias/rlinf_alias.sh`
- RLinf 特定别名：`cdrl`, `gpu_mem` 等
- 工具函数：`link_assets()` 等

### 代理配置

代理设置通过函数调用，无需环境变量传递：

```bash
# 启用代理
proxy_en

# 禁用代理
proxy_dis
```

## 🔍 故障排除

### 1. 驱动库检查

运行驱动检查脚本：

```bash
./check_drivers.sh
```

### 2. CUDA 环境设置问题

```bash
# 检查 CUDA 环境是否设置
ls -la ~/cuda-fake/

# 重新设置 CUDA 环境
./setup_cuda_drivers.sh
```

### 3. 容器启动失败

```bash
# 检查 CUDA 环境
./setup_cuda_fake.sh  # 会自动检查环境

# 查看详细错误信息
docker logs rlinf
```

### 4. 容器内调试

```bash
# 进入容器
docker exec -it rlinf /bin/zsh

# 重新初始化环境
docker_init

# 检查安装状态
ls -la ~/.oh-my-zsh/
```

### 3. 权限问题

如果遇到文件权限问题，检查用户映射：

```bash
# 确认当前用户
id

# 检查文件权限
ls -la /root/git_repo/RLinf/
```

### 4. 网络问题

如果插件安装失败，可能是网络问题：

```bash
# 启用代理后重试
proxy_en
docker_init
```

## 📋 技术细节

### 架构设计

#### 分离式架构优势
- **设置分离**: 驱动环境设置与容器启动分离
- **性能优化**: 避免重复下载和安装 CUDA Toolkit
- **维护友好**: 可以独立更新驱动环境或容器配置
- **调试便利**: 可以单独测试驱动设置是否正确

#### 文件关系
```
setup_cuda_drivers.sh        → 创建 ~/cuda-fake/ 环境
launch_docker_custom.sh      → 使用 ~/cuda-fake/ 启动容器，传递环境变量
docker_init_from_dockerfile.sh → 在容器内初始化开发环境，加载 .alias 配置
.alias/ 目录                 → 存放所有别名、函数和环境配置
```

### CUDA 伪装机制

1. **下载 CUDA 12.4 Toolkit**: 包含编译器和运行时库
2. **创建 compat 目录**: 存放版本伪装的驱动库软链接
3. **软链接映射**: 将宿主机的真实驱动库伪装成目标版本
4. **nvidia-container-toolkit**: 检测到伪装版本后允许启动

### 环境初始化流程

#### 容器外（setup_cuda_drivers.sh）
1. **检查驱动**: 验证 NVIDIA 驱动可用性
2. **下载安装**: 获取并安装 CUDA 12.4 Toolkit
3. **创建伪装**: 构建驱动库软链接伪装层
4. **配置缓存**: 设置动态链接库缓存

#### 容器内（docker_init_from_dockerfile.sh）
1. **代理配置**: 加载并启用代理设置
2. **系统配置**: 设置 apt/pip 镜像，安装系统依赖
3. **Zsh 环境**: 安装 Oh My Zsh 和插件
4. **用户创建**: 创建与宿主机对应的用户账户
5. **配置加载**: 自动加载 `.alias` 目录下的所有配置文件
6. **环境设置**: 配置 Git、权限等开发环境

### 安全考虑

- **目录隔离**: 只挂载必要的用户目录
- **权限控制**: 使用宿主机用户权限运行
- **代理安全**: 支持企业代理环境
- **系统完整性**: 不修改系统关键目录
- **环境分离**: 容器内外环境完全隔离

## 🤝 贡献

如需修改配置，请编辑相应文件：

- `setup_cuda_drivers.sh`: CUDA 驱动环境设置
- `launch_docker_custom.sh`: Docker 容器启动配置
- `docker_init_from_dockerfile.sh`: 容器内环境初始化逻辑
- `.alias/common.sh`: 通用别名和环境变量
- `.alias/proxy.sh`: 代理相关函数
- `.alias/rlinf_alias.sh`: RLinf 特定别名和函数

### 开发建议

- **驱动环境**: 修改 `setup_cuda_drivers.sh` 时注意版本兼容性
- **容器启动**: 修改 `setup_cuda_fake.sh` 时保持文档合规性
- **环境初始化**: 修改 `docker_init.sh` 时考虑网络环境和代理支持
- **配置更新**: 更新配置时同步修改相关文档
