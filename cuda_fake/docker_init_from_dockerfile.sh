#!/bin/bash
set -e

# ================= RLinf Docker 初始化脚本 =================
# 此脚本基于 Dockerfile.zsh 的内容转换为普通 shell 脚本
# 用于在已有的 Docker 容器中进行初始化配置

echo "=== 开始 RLinf Docker 初始化 ==="

# ================= 环境变量设置 =================
# 环境变量设置
export PATH=/opt/conda/bin:$PATH
export DEBIAN_FRONTEND=noninteractive

# 配置 apt 镜像（如果未设置 NO_MIRROR）
echo "📦 配置 apt 镜像..."
if [ -z "$NO_MIRROR" ]; then
    sed -i 's@//.*archive.ubuntu.com@//mirrors.bfsu.edu.cn@g' /etc/apt/sources.list
    echo "✅ 已配置 BFSU 镜像"
else
    echo "ℹ️  跳过 apt 镜像配置 (NO_MIRROR 已设置)"
fi

# 配置 pip 镜像和升级
echo "🐍 配置 pip 镜像..."
pip config set global.index-url https://mirrors.bfsu.edu.cn/pypi/web/simple
echo "✅ pip 配置完成"



# ================= 代理配置 =================
# 启用代理（通过 .alias 中的 proxy_en）
if [ -f /root/.alias/proxy.sh ]; then
    source /root/.alias/proxy.sh
    proxy_en
    echo "✅ 已启用代理"
fi

# ================= zsh 配置 =================
# 设置 zsh 为默认 shell
apt-get update
apt-get install zsh -y
chsh -s /bin/zsh

# 安装 oh-my-zsh（使用代理）
if [ ! -d '~/.oh-my-zsh' ]; then
    sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended || true
    echo "✅ Oh My Zsh 安装完成"
else
    echo "ℹ️  Oh My Zsh 已存在，跳过安装"
fi

# 克隆 zsh 插件
echo "🔌 安装 zsh 插件..."
ZSH=~/.oh-my-zsh
mkdir -p $ZSH/custom/plugins && \
for plugin in zsh-completions zsh-syntax-highlighting zsh-autosuggestions; do
    if [ ! -d "$ZSH/custom/plugins/$plugin" ]; then
        git clone https://github.com/zsh-users/$plugin $ZSH/custom/plugins/$plugin
    fi
done && echo "✅ zsh 插件安装完成"

# Configure zsh plugins for root
sed -i 's/plugins=(git)/plugins=(git zsh-completions zsh-syntax-highlighting zsh-autosuggestions z extract web-search)/' ~/.zshrc

# Source .alias files for root
if [ -d /root/.alias ]; then
    echo "" >> /root/.zshrc
    echo "# Source aliases from .alias directory" >> /root/.zshrc
    echo "if [ -d /root/.alias ]; then" >> /root/.zshrc
    echo "    for alias_file in /root/.alias/*.sh; do" >> /root/.zshrc
    echo "        if [ -f \"\$alias_file\" ]; then" >> /root/.zshrc
    echo "            source \"\$alias_file\"" >> /root/.zshrc
    echo "        fi" >> /root/.zshrc
    echo "    done" >> /root/.zshrc
    echo "fi" >> /root/.zshrc
fi

# ================= git 配置 =================

# 配置 git
echo "🔧 配置 git..."
git config --global --add safe.directory '*'

# ================= 用户配置 =================
# if APP_USER is not root, then create user
if [ "$APP_USER" != "root" ]; then

    # 获取主机用户ID和组ID
    HOST_UID=$(id -u)
    HOST_GID=$(id -g)

    # 创建匹配主机的用户（如果不存在）
    echo "👤 配置用户${APP_USER}..."

    # 复制配置到用户
    if id -u ${APP_USER} > /dev/null 2>&1; then
        groupadd -g ${HOST_GID} ${APP_USER} 2>/dev/null || true
        useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/zsh ${APP_USER} 2>/dev/null || true
    fi 

    # 配置 sudo
    mkdir -p /etc/sudoers.d
    echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${APP_USER}
    chmod 0440 /etc/sudoers.d/${APP_USER}

    # 添加到 docker 组（如果存在）
    (getent group docker >/dev/null || groupadd -r docker) && usermod -aG docker ${APP_USER} 2>/dev/null || true
    chsh -s /bin/zsh ${APP_USER}
    su - ${APP_USER} -c "git config --global --add safe.directory '*'" 2>/dev/null || true
    if [ -d /root/.oh-my-zsh ]; then
        cp -r /root/.oh-my-zsh /home/${APP_USER}/.oh-my-zsh 2>/dev/null || true
        chown -R ${APP_USER}:${APP_USER} /home/${APP_USER}/.oh-my-zsh 2>/dev/null || true
    fi

    echo "📋 复制配置到用户..."
    if [ -d /root/.ssh ]; then
        cp -r /root/.ssh /home/${APP_USER}/.ssh 2>/dev/null || true
        chown -R ${APP_USER}:${APP_USER} /home/${APP_USER}/.ssh 2>/dev/null || true
        chmod 700 /home/${APP_USER}/.ssh 2>/dev/null || true
        chmod 600 /home/${APP_USER}/.ssh/id_ed25519 2>/dev/null || true
        chmod 644 /home/${APP_USER}/.ssh/id_ed25519.pub 2>/dev/null || true
    fi

    if [ -f /root/.zshrc ]; then
        cp /root/.zshrc /home/${APP_USER}/.zshrc 2>/dev/null || true
        chown ${APP_USER}:${APP_USER} /home/${APP_USER}/.zshrc 2>/dev/null || true
    fi

    echo "✅ 配置复制完成"
    echo "💡 接下来将切换到 ${APP_USER} 并启动 zsh 环境"
else
    echo "ℹ️  using default user root"
fi

# 设置环境变量
export UMASK=0002
apt install -y software-properties-common
sudo apt-key adv --fetch-keys https://developer.download.nvidia.com/compute/cuda/repos/ubuntu1804/x86_64/7fa2af80.pub
sudo add-apt-repository "deb https://developer.download.nvidia.com/devtools/repos/ubuntu$(source /etc/lsb-release; echo "$DISTRIB_RELEASE" | tr -d .)/$(dpkg --print-architecture)/ /"
sudo apt install nsight-systems-2025.5.2
apt-get install libvulkan1 mesa-vulkan-drivers vulkan-tools -y

pip install PyOpenGL-accelerate
export PATH="/usr/local/bin:$PATH"
echo "🎉 Docker 初始化完成！"
echo ""


