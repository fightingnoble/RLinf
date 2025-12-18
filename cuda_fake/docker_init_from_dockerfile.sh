#!/bin/bash
set -e

# ================= RLinf Docker 初始化脚本 =================
# 此脚本基于 Dockerfile.zsh 的内容转换为普通 shell 脚本
# 用于在已有的 Docker 容器中进行初始化配置

echo "=== 开始 RLinf Docker 初始化 ==="

# 配置区域 - 与 Dockerfile 中的 ARG 对应
PROXY_HOST="${PROXY_HOST:-222.29.97.81}"
PROXY_PORT="${PROXY_PORT:-1080}"
SSH_KEY_EMAIL="${SSH_KEY_EMAIL:-zhangchg@stu.pku.edu.cn}"
NO_MIRROR="${NO_MIRROR:-}"
APP_USER="${APP_USER:-appuser}"

# 环境变量设置
export PATH=/opt/conda/bin:$PATH
export DEBIAN_FRONTEND=noninteractive

# 配置 apt 镜像（如果未设置 NO_MIRROR）
echo "📦 配置 apt 镜像..."
if [ -z "$NO_MIRROR" ]; then
    sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list
    echo "✅ 已配置 USTC 镜像"
else
    echo "ℹ️  跳过 apt 镜像配置 (NO_MIRROR 已设置)"
fi

# 配置 pip 镜像和升级
echo "🐍 配置 pip 镜像..."
pip config set global.index-url https://mirrors.bfsu.edu.cn/pypi/web/simple
echo "✅ pip 配置完成"

# 设置代理环境变量（用于临时构建）
PROXY_URL="http://${PROXY_HOST}:${PROXY_PORT}"
export PROXY_HOST=${PROXY_HOST}
export PROXY_PORT=${PROXY_PORT}
export PROXY_URL=${PROXY_URL}

# 获取主机用户ID和组ID
HOST_UID=$(id -u)
HOST_GID=$(id -g)

# 创建匹配主机的用户（如果不存在）
echo "👤 配置用户..."
if ! id -u ${APP_USER} > /dev/null 2>&1; then
    groupadd -g ${HOST_GID} ${APP_USER} 2>/dev/null || true
    useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/zsh ${APP_USER} 2>/dev/null || true
fi

# 配置 sudo
mkdir -p /etc/sudoers.d
echo "${APP_USER} ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/${APP_USER}
chmod 0440 /etc/sudoers.d/${APP_USER}

# 添加到 docker 组（如果存在）
(getent group docker >/dev/null || groupadd -r docker) && usermod -aG docker ${APP_USER} 2>/dev/null || true


# 添加link_assets到用户
cat <<EOF > /usr/local/bin/link_assets
#!/bin/bash
if [ -d /opt/assets/.maniskill ]; then
    if [ -d ~/.maniskill ]; then
        rm -rf ~/.maniskill
    fi
    ln -s /opt/assets/.maniskill ~/.maniskill
fi
if [ -d /opt/assets/.sapien ]; then
    if [ -d ~/.sapien ]; then
        rm -rf ~/.sapien
    fi
    ln -s /opt/assets/.sapien ~/.sapien
fi
mkdir -p ~/.cache
if [ -d /opt/assets/.cache/openpi ]; then
    if [ -d ~/.cache/openpi ]; then
        rm -rf ~/.cache/openpi
    fi
    ln -s /opt/assets/.cache/openpi ~/.cache/openpi
fi
EOF
chmod +x /usr/local/bin/link_assets

# 生成 SSH 密钥
echo "🔑 生成 SSH 密钥..."
mkdir -p ~/.ssh
if [ ! -f ~/.ssh/id_ed25519 ]; then
    ssh-keygen -t ed25519 -C "${SSH_KEY_EMAIL}" -f ~/.ssh/id_ed25519 -N ""
    echo "✅ SSH 密钥生成完成"
else
    echo "ℹ️  SSH 密钥已存在，跳过生成"
fi

# 配置 git
echo "🔧 配置 git..."
git config --global --add safe.directory '*'

# 为用户也配置 git
if id -u ${APP_USER} > /dev/null 2>&1; then
    su - ${APP_USER} -c "git config --global --add safe.directory '*'" 2>/dev/null || true
fi
echo "✅ git 配置完成"


# 设置 zsh 为默认 shell
apt-get install -y zsh zip
echo "🐚 设置 zsh 为默认 shell..."
chsh -s /bin/zsh
if id -u ${APP_USER} > /dev/null 2>&1; then
    chsh -s /bin/zsh ${APP_USER}
fi
echo "✅ zsh 设置完成"

# 安装 oh-my-zsh（使用代理）
echo "🎨 安装 Oh My Zsh..."
if [ ! -d '/root/.oh-my-zsh' ]; then
    # 备份现有的 .zshrc（如果存在）
    ZSHRC_BACKUP="/root/.zshrc.backup.$(date +%s)"
    if [ -f ~/.zshrc ]; then
        echo "📋 备份现有的 .zshrc 到 ${ZSHRC_BACKUP}"
        cp ~/.zshrc "${ZSHRC_BACKUP}"
    fi

    # 安装 Oh My Zsh
    http_proxy=${PROXY_URL} https_proxy=${PROXY_URL} \
    sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended || true

    # 如果安装成功且有备份，则恢复自定义配置
    if [ -f "${ZSHRC_BACKUP}" ] && [ -f ~/.zshrc ]; then
        echo "🔄 合并备份的配置到新的 .zshrc..."

        # 在 Oh My Zsh 配置之后添加备份的内容（排除 Oh My Zsh 相关配置）
        echo "" >> ~/.zshrc
        echo "# Custom configuration from backup" >> ~/.zshrc
        echo "# ==================================" >> ~/.zshrc

        # 提取备份文件中的自定义配置（排除 Oh My Zsh 自动生成的行）
        grep -v "^# If you come from bash you might have to change your" "${ZSHRC_BACKUP}" | \
        grep -v "^export ZSH=" | \
        grep -v "^ZSH_THEME=" | \
        grep -v "^plugins=(" | \
        grep -v "^source \$ZSH/oh-my-zsh.sh" | \
        grep -v "^# .*oh-my-zsh" >> ~/.zshrc

        echo "✅ 配置合并完成"
    fi

    # 清理备份文件
    [ -f "${ZSHRC_BACKUP}" ] && rm -f "${ZSHRC_BACKUP}"

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
        http_proxy=${PROXY_URL} https_proxy=${PROXY_URL} \
        git clone https://github.com/zsh-users/$plugin $ZSH/custom/plugins/$plugin
    fi
done && echo "✅ zsh 插件安装完成"


# 复制配置到用户
echo "📋 复制配置到用户..."
if id -u ${APP_USER} > /dev/null 2>&1; then
    if [ -d /root/.oh-my-zsh ]; then
        cp -r /root/.oh-my-zsh /home/${APP_USER}/.oh-my-zsh 2>/dev/null || true
        chown -R ${APP_USER}:${APP_USER} /home/${APP_USER}/.oh-my-zsh 2>/dev/null || true
    fi

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
else
    echo "ℹ️  ${APP_USER} 不存在，跳过配置复制"
fi

# 设置环境变量
export UMASK=0002

echo "🎉 RLinf Docker 初始化完成！"
echo ""
echo "💡 接下来将切换到 ${APP_USER} 并启动 zsh 环境"
