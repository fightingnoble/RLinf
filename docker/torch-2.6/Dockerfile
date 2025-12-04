ARG BUILD_TARGET=reason

# Use CUDA 12.1 for compatibility with driver 530.x (supports up to CUDA 12.1)
# Use docker.1ms.run mirror for faster access in China
FROM docker.1ms.run/nvidia/cuda:12.1.1-cudnn8-devel-ubuntu22.04 AS base-image

ARG NO_MIRROR
SHELL ["/bin/bash", "-c"]
ENV PATH=/opt/conda/bin:$PATH
ENV DEBIAN_FRONTEND=noninteractive
RUN if [ -z "$NO_MIRROR" ]; then sed -i 's@//.*archive.ubuntu.com@//mirrors.ustc.edu.cn@g' /etc/apt/sources.list; fi
RUN apt-get update && apt-get install -y --no-install-recommends \
    git vim libibverbs-dev openssh-server sudo runit runit-systemd tmux \
    build-essential python3-dev cmake pkg-config iproute2 pciutils python3 python3-pip \
    wget unzip curl

# Use BFSU (Beijing Foreign Studies University) mirror - faster than Tsinghua
RUN pip config set global.index-url https://mirrors.bfsu.edu.cn/pypi/web/simple
RUN python3 -m pip install -i https://mirrors.bfsu.edu.cn/pypi/web/simple --upgrade pip setuptools wheel uv

ENV HF_HOME=/opt/.cache/huggingface
RUN mkdir -p $HF_HOME

# UV setup - use BFSU mirror for faster downloads
ENV UV_DEFAULT_INDEX=${NO_MIRROR:+"https://pypi.org/simple/"}
ENV UV_DEFAULT_INDEX=${UV_DEFAULT_INDEX:-"https://mirrors.bfsu.edu.cn/pypi/web/simple"}
ENV UV_PATH=/opt/venv
RUN mkdir $UV_PATH
WORKDIR $UV_PATH
COPY project $UV_PATH/pyproject.toml
ENV UV_LINK_MODE=symlink
ENV UV_CACHE_DIR=$UV_PATH/.cache
ENV UV_PYTHON_INSTALL_DIR=${UV_PATH}/.python

# switch_env utility
RUN printf '#!/bin/bash\n\
if [ -z "$1" ]; then\n\
    echo "Usage: switch_env <env_name>"\n\
    exit 1\n\
fi\n\
if [ ! -d "%s/$1" ]; then\n\
    echo "Environment $1 does not exist in %s."\n\
    exit 1\n\
fi\n\
source %s/$1/bin/activate\n' "${UV_PATH}" "${UV_PATH}" "${UV_PATH}" > /usr/local/bin/switch_env && \
    chmod +x /usr/local/bin/switch_env

ENV PYTHON_VERSION=3.11
ENV FLASH_ATTENTION_WHEEL="https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.6cxx11abiFALSE-cp311-cp311-linux_x86_64.whl"
# Use PyTorch cu121 index to match base image CUDA 12.1.1
ENV UV_EXTRA_INDEX_URL="https://download.pytorch.org/whl/cu121"
ENV UV_INDEX_STRATEGY="unsafe-best-match"
# Increase timeout for large packages
ENV UV_HTTP_TIMEOUT=300

FROM base-image AS reason-image

# Install Megatron-LM
# Create directory and set PYTHONPATH (actual code will be mounted at runtime)
RUN mkdir -p /opt/Megatron-LM
ENV PYTHONPATH=/opt/Megatron-LM:$PYTHONPATH

# Install reasoning env
RUN uv venv reason --python=${PYTHON_VERSION}
# Pre-install Git dependency (only latex2sympy2, ManiSkill is embodied-only)
RUN --mount=type=bind,source=repos/latex2sympy2,target=/tmp/latex2sympy2,rw \
    source switch_env reason && \
    uv pip install /tmp/latex2sympy2
RUN source switch_env reason && UV_TORCH_BACKEND=auto uv sync --active
RUN source switch_env reason && uv sync --extra sglang-vllm --active
RUN source switch_env reason && uv pip install https://github.com/RLinf/apex/releases/download/25.09/apex-0.1-cp311-cp311-linux_x86_64.whl
RUN source switch_env reason && uv pip install transformer_engine[pytorch]==2.1.0 --no-build-isolation
RUN source switch_env reason && uv pip install ${FLASH_ATTENTION_WHEEL}
RUN source switch_env reason && uv pip uninstall pynvml

# Set default env
RUN echo "source ${UV_PATH}/reason/bin/activate" >> ~/.bashrc

FROM base-image AS embodied-common-image

# Embodied NVIDIA_DRIVER_CAPABILITIES
ENV NVIDIA_DRIVER_CAPABILITIES="all"

# Install rendering runtime configuration files
RUN mkdir -p /usr/share/glvnd/egl_vendor.d /etc/vulkan/icd.d /etc/vulkan/implicit_layer.d
RUN printf '{\n    "file_format_version" : "1.0.0",\n    "ICD" : {\n        "library_path" : "libEGL_nvidia.so.0"\n    }\n}\n' > /usr/share/glvnd/egl_vendor.d/10_nvidia.json
RUN printf '{\n    "file_format_version" : "1.0.0",\n    "ICD" : {\n        "library_path" : "libEGL_mesa.so.0"\n    }\n}\n' > /usr/share/glvnd/egl_vendor.d/50_mesa.json
RUN printf '{\n    "file_format_version" : "1.0.0",\n    "ICD" : {\n        "library_path" : "libGLX_nvidia.so.0",\n        "api_version" : "1.3.194"\n    }\n}\n' > /etc/vulkan/icd.d/nvidia_icd.json
RUN mkdir -p /etc/vulkan/implicit_layer.d && printf '{\n    "file_format_version" : "1.0.0",\n    "layer": {\n        "name": "VK_LAYER_NV_optimus",\n        "type": "INSTANCE",\n        "library_path": "libGLX_nvidia.so.0",\n        "api_version" : "1.3.194",\n        "implementation_version" : "1",\n        "description" : "NVIDIA Optimus layer",\n        "functions": {\n            "vkGetInstanceProcAddr": "vk_optimusGetInstanceProcAddr",\n            "vkGetDeviceProcAddr": "vk_optimusGetDeviceProcAddr"\n        },\n        "enable_environment": {\n            "__NV_PRIME_RENDER_OFFLOAD": "1"\n        },\n        "disable_environment": {\n            "DISABLE_LAYER_NV_OPTIMUS_1": ""\n        }\n    }\n}\n' > /etc/vulkan/implicit_layer.d/nvidia_layers.json
ENV VK_DRIVER_FILES=/etc/vulkan/icd.d/nvidia_icd.json
ENV VK_ICD_FILENAMES=/etc/vulkan/icd.d/nvidia_icd.json

# Embodied system dependencies
RUN apt-get install -y --no-install-recommends \
    mesa-utils \
    libosmesa6-dev \
    freeglut3-dev \
    libglew-dev \
    libegl1 \
    libgles2 \
    libglvnd-dev \
    libglfw3-dev \
    libgl1-mesa-dev \
    libgl1-mesa-glx \
    libglib2.0-0 \
    libsm6 \
    libxext6 \
    libxrender-dev \
    libgomp1

# link_assets utility
RUN printf '#!/bin/bash\n\
if [ -d /opt/.maniskill ]; then\n\
    ln -s /opt/.maniskill ~/.maniskill\n\
fi\n\
if [ -d /opt/.sapien ]; then\n\
    ln -s /opt/.sapien ~/.sapien\n\
fi\n\
mkdir -p ~/.cache\n\
if [ -d /opt/.openpi ]; then\n\
    ln -s /opt/.openpi ~/.cache/openpi\n\
fi\n' > /usr/local/bin/link_assets && \
    chmod +x /usr/local/bin/link_assets

# download_assets utility
RUN printf '#!/bin/bash\n\
\n\
# Download assets for ManiSkill\n\
export MS_ASSET_DIR=/opt/.maniskill\n\
python -m mani_skill.utils.download_asset bridge_v2_real2sim -y\n\
python -m mani_skill.utils.download_asset widowx250s -y\n\
\n\
# Download assets for SAPIEN\n\
export PHYSX_VERSION=105.1-physx-5.3.1.patch0\n\
export PHYSX_DIR=/opt/.sapien/physx/$PHYSX_VERSION\n\
mkdir -p $PHYSX_DIR\n\
wget -O $PHYSX_DIR/linux-so.zip https://github.com/sapien-sim/physx-precompiled/releases/download/$PHYSX_VERSION/linux-so.zip\n\
unzip $PHYSX_DIR/linux-so.zip -d $PHYSX_DIR && rm $PHYSX_DIR/linux-so.zip\n\
\n\
# Download assets for OpenPI\n\
export TOKENIZER_DIR=/opt/.openpi/big_vision/\n\
mkdir -p $TOKENIZER_DIR && gsutil -m cp -r gs://big_vision/paligemma_tokenizer.model $TOKENIZER_DIR\n' > /usr/local/bin/download_assets && \
    chmod +x /usr/local/bin/download_assets

# Install LIBERO
# Create directory and set PYTHONPATH (actual code will be mounted at runtime)
RUN mkdir -p /opt/libero
ENV PYTHONPATH=/opt/libero:$PYTHONPATH

FROM embodied-common-image AS embodied-image

# Install openvla env
ARG VENV_TARGET=openvla
RUN uv venv ${VENV_TARGET} --python ${PYTHON_VERSION}
# Pre-install Git dependencies from local repos to avoid network issues
# Use rw mount to allow build artifacts (written data discarded after RUN)
RUN --mount=type=bind,source=repos/latex2sympy2,target=/tmp/latex2sympy2,rw \
    --mount=type=bind,source=repos/ManiSkill,target=/tmp/ManiSkill,rw \
    source switch_env ${VENV_TARGET} && \
    uv pip install /tmp/latex2sympy2 && \
    uv pip install /tmp/ManiSkill
RUN source switch_env ${VENV_TARGET} && UV_TORCH_BACKEND=auto uv sync --active
RUN source switch_env ${VENV_TARGET} && uv sync --extra embodied --active
# Use rw mount for openvla (build artifacts discarded after RUN)
RUN --mount=type=bind,source=repos/openvla,target=/tmp/openvla,rw \
    source switch_env ${VENV_TARGET} && \
    uv pip install /tmp/openvla --no-build-isolation
RUN source switch_env ${VENV_TARGET} && uv pip install $FLASH_ATTENTION_WHEEL --no-build-isolation
RUN source switch_env ${VENV_TARGET} && uv pip uninstall pynvml

# Install openvla-oft env
ARG VENV_TARGET=openvla-oft
RUN uv venv ${VENV_TARGET} --python ${PYTHON_VERSION}
# Mount repos with rw to allow build artifacts
RUN --mount=type=bind,source=repos/latex2sympy2,target=/tmp/latex2sympy2,rw \
    --mount=type=bind,source=repos/ManiSkill,target=/tmp/ManiSkill,rw \
    source switch_env ${VENV_TARGET} && \
    uv pip install /tmp/latex2sympy2 && \
    uv pip install /tmp/ManiSkill
RUN source switch_env ${VENV_TARGET} && UV_TORCH_BACKEND=auto uv sync --active
RUN source switch_env ${VENV_TARGET} && uv sync --extra embodied --active
# Use rw mount for openvla-oft
RUN --mount=type=bind,source=repos/openvla-oft,target=/tmp/openvla-oft,rw \
    source switch_env ${VENV_TARGET} && \
    uv pip install /tmp/openvla-oft --no-build-isolation
RUN source switch_env ${VENV_TARGET} && uv pip install $FLASH_ATTENTION_WHEEL --no-build-isolation
RUN source switch_env ${VENV_TARGET} && uv pip uninstall pynvml

# Install openpi env
ARG VENV_TARGET=openpi
RUN uv venv ${VENV_TARGET} --python ${PYTHON_VERSION}
# Mount repos with rw to allow build artifacts
RUN --mount=type=bind,source=repos/latex2sympy2,target=/tmp/latex2sympy2,rw \
    --mount=type=bind,source=repos/ManiSkill,target=/tmp/ManiSkill,rw \
    source switch_env ${VENV_TARGET} && \
    uv pip install /tmp/latex2sympy2 && \
    uv pip install /tmp/ManiSkill
RUN source switch_env ${VENV_TARGET} && UV_TORCH_BACKEND=auto uv sync --active
RUN source switch_env ${VENV_TARGET} && uv sync --extra embodied --active
# Use rw mount for openpi
RUN --mount=type=bind,source=repos/openpi,target=/tmp/openpi,rw \
    source switch_env ${VENV_TARGET} && \
    GIT_LFS_SKIP_SMUDGE=1 uv pip install /tmp/openpi
RUN source switch_env ${VENV_TARGET} && uv pip uninstall pynvml
RUN cp -r ${UV_PATH}/${VENV_TARGET}/lib/python${PYTHON_VERSION}/site-packages/openpi/models_pytorch/transformers_replace/* ${UV_PATH}/${VENV_TARGET}/lib/python${PYTHON_VERSION}/site-packages/transformers/

RUN source switch_env openvla && download_assets
RUN link_assets

# Set default env
RUN echo "source ${UV_PATH}/openvla/bin/activate" >> ~/.bashrc

FROM embodied-common-image AS embodied-behavior-image

ENV PYTHON_VERSION=3.10
# FlashAttention for Python 3.10 and PyTorch 2.5 (behavior env uses torch 2.5.1)
ENV FLASH_ATTENTION_WHEEL="https://github.com/Dao-AILab/flash-attention/releases/download/v2.7.4.post1/flash_attn-2.7.4.post1+cu12torch2.5cxx11abiFALSE-cp310-cp310-linux_x86_64.whl"

# Install BEHAVIOR-1K
# Create directory (actual code will be mounted at runtime)
RUN mkdir -p /opt/BEHAVIOR-1K

# Install openvla-oft env for embodied-behavior
ARG VENV_TARGET=openvla-oft
RUN uv venv ${VENV_TARGET} --python=${PYTHON_VERSION}
# Mount repos with rw for this stage (different Python version)
RUN --mount=type=bind,source=repos/latex2sympy2,target=/tmp/latex2sympy2,rw \
    --mount=type=bind,source=repos/ManiSkill,target=/tmp/ManiSkill,rw \
    source switch_env ${VENV_TARGET} && \
    uv pip install /tmp/latex2sympy2 && \
    uv pip install /tmp/ManiSkill
RUN source switch_env ${VENV_TARGET} && UV_TORCH_BACKEND=auto uv sync --active
RUN source switch_env ${VENV_TARGET} && uv sync --extra embodied --active
RUN source switch_env ${VENV_TARGET} && cd /opt/BEHAVIOR-1K && UV_LINK_MODE=hardlink ./setup.sh --omnigibson --bddl --joylo --confirm-no-conda --accept-nvidia-eula --use-uv && cd -
# Use rw mount for openvla-oft in behavior stage
RUN --mount=type=bind,source=repos/openvla-oft,target=/tmp/openvla-oft,rw \
    source switch_env ${VENV_TARGET} && \
    uv pip install /tmp/openvla-oft --no-build-isolation
RUN source switch_env ${VENV_TARGET} && uv pip install $FLASH_ATTENTION_WHEEL --no-build-isolation
RUN source switch_env ${VENV_TARGET} && uv pip install ml_dtypes==0.5.3 protobuf==3.20.3
# Ray is not compatible with click 8.3.0 on Python 3.10
RUN source switch_env ${VENV_TARGET} && pip install click==8.2.1
RUN source switch_env ${VENV_TARGET} && cd && uv pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1 && cd -
RUN source switch_env ${VENV_TARGET} && uv pip uninstall pynvml
# omnigibson downloads assets to /tmp during initialization
RUN source switch_env ${VENV_TARGET} && python -c "import omnigibson as og; cfg={}; og.Environment(cfg); og.shutdown()" || exit 0

RUN source switch_env ${VENV_TARGET} && download_assets
RUN link_assets

# Set default env
RUN echo "source ${UV_PATH}/${VENV_TARGET}/bin/activate" >> ~/.bashrc

FROM ${BUILD_TARGET}-image AS final-image

# Clean up
RUN uv cache prune
RUN rm -rf /var/lib/apt/lists/*

WORKDIR /workspace

CMD ["/bin/bash"]
