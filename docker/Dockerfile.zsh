FROM docker.1ms.run/nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04

# Configurable arguments
# Usage: docker build --build-arg PROXY_HOST=your.proxy.com --build-arg PROXY_PORT=1080 --build-arg SSH_KEY_EMAIL=your@email.com
ARG PROXY_HOST=222.29.97.81
ARG PROXY_PORT=1080
ARG SSH_KEY_EMAIL=zhangchg@stu.pku.edu.cn
ARG NO_MIRROR
# Keep UID/GID in sync with host to avoid root-owned artifacts on mounts
ARG HOST_UID=1000
ARG HOST_GID=1000

SHELL ["/bin/bash", "-c"]
ENV PATH=/opt/conda/bin:$PATH
ENV DEBIAN_FRONTEND=noninteractive

# Configure apt mirror if needed
RUN if [ -z "$NO_MIRROR" ]; then sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list; fi

# Install packages
RUN apt-get update && apt-get install -y --no-install-recommends \
    git vim libibverbs-dev openssh-server sudo runit runit-systemd tmux \
    build-essential python3-dev cmake pkg-config iproute2 pciutils python3 python3-pip \
    wget unzip curl \
    zsh \
    openssh-client \
    && rm -rf /var/lib/apt/lists/*

# Configure pip mirror and upgrade
RUN pip config set global.index-url https://mirrors.bfsu.edu.cn/pypi/web/simple
RUN python3 -m pip install -i https://mirrors.bfsu.edu.cn/pypi/web/simple --upgrade pip setuptools wheel uv

# Set zsh as default shell
RUN chsh -s /bin/zsh

# Set proxy for downloads
ENV PROXY_HOST=${PROXY_HOST}
ENV PROXY_PORT=${PROXY_PORT}
ENV PROXY_URL=http://${PROXY_HOST}:${PROXY_PORT}
ENV http_proxy=${PROXY_URL}
ENV https_proxy=${PROXY_URL}

# Create host-matching user with passwordless sudo for occasional privileged commands
RUN groupadd -g ${HOST_GID} appuser && \
    useradd -m -u ${HOST_UID} -g ${HOST_GID} -s /bin/zsh appuser && \
    mkdir -p /etc/sudoers.d && \
    echo "appuser ALL=(ALL) NOPASSWD: ALL" > /etc/sudoers.d/appuser && \
    chmod 0440 /etc/sudoers.d/appuser && \
    (getent group docker >/dev/null || groupadd -r docker) && \
    usermod -aG docker,sudo appuser

# Configure git proxy and safe directory for root
RUN git config --global http.proxy ${PROXY_URL} && \
    git config --global https.proxy ${PROXY_URL} && \
    git config --global --add safe.directory '*'

# Install oh-my-zsh for root user (with proxy)
RUN sh -c "$(curl -fsSL https://install.ohmyz.sh/)" "" --unattended || true

# Generate SSH key for root (non-interactive)
RUN mkdir -p ~/.ssh && \
    ssh-keygen -t ed25519 -C "${SSH_KEY_EMAIL}" -f ~/.ssh/id_ed25519 -N ""

# Clone zsh plugins using HTTPS (with proxy) for root
RUN ZSH=~/.oh-my-zsh && \
    mkdir -p $ZSH/custom/plugins && \
    git clone https://github.com/zsh-users/zsh-completions $ZSH/custom/plugins/zsh-completions && \
    git clone https://github.com/zsh-users/zsh-syntax-highlighting $ZSH/custom/plugins/zsh-syntax-highlighting && \
    git clone https://github.com/zsh-users/zsh-autosuggestions $ZSH/custom/plugins/zsh-autosuggestions

# Configure zsh plugins and proxy alias for root
RUN sed -i 's/plugins=(git)/plugins=(git zsh-completions zsh-syntax-highlighting zsh-autosuggestions z extract web-search)/' ~/.zshrc && \
    echo '' >> ~/.zshrc && \
    echo '# Proxy alias' >> ~/.zshrc && \
    echo "alias proxy_en='export https_proxy=\"${PROXY_URL}\";export http_proxy=\"${PROXY_URL}\"'" >> ~/.zshrc && \
    echo "alias proxy_dis='unset https_proxy;unset http_proxy'" >> ~/.zshrc

# Copy root's oh-my-zsh, SSH, and zsh config to appuser
RUN cp -r /root/.oh-my-zsh /home/appuser/.oh-my-zsh && \
    cp -r /root/.ssh /home/appuser/.ssh && \
    cp /root/.zshrc /home/appuser/.zshrc && \
    chown -R appuser:appuser /home/appuser/.oh-my-zsh && \
    chown -R appuser:appuser /home/appuser/.ssh && \
    chown appuser:appuser /home/appuser/.zshrc && \
    chmod 700 /home/appuser/.ssh && \
    chmod 600 /home/appuser/.ssh/id_ed25519 && \
    chmod 644 /home/appuser/.ssh/id_ed25519.pub 2>/dev/null || true

# Configure git proxy and safe directory for appuser
RUN su - appuser -c "git config --global --add safe.directory '*'"

# Default to the unprivileged user; use sudo when escalation is required
USER appuser

ENV UMASK=0002

# Ensure a user-writable workspace by default
WORKDIR /home/appuser

CMD ["/bin/zsh"]

