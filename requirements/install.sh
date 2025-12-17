#! /bin/bash

set -euo pipefail

TARGET=""

MODEL=""
ENV_NAME=""
VENV_DIR=".venv"
PYTHON_VERSION="3.11.14"
USE_CURRENT_ENV=0
TEST_BUILD=${TEST_BUILD:-0}
# Absolute path to this script (resolves symlinks)
SCRIPT_PATH="$(readlink -f "${BASH_SOURCE[0]}")"
SCRIPT_DIR="$(dirname "$SCRIPT_PATH")"

# Source local install helpers (order matters: utils -> route -> prepare)
source "$SCRIPT_DIR/install_local/url_replace.sh"
source "$SCRIPT_DIR/install_local/route.sh"
source "$SCRIPT_DIR/install_local/prepare.sh"

# List of requirements files referenced by installs
REQ_FILES=(
    "$SCRIPT_DIR/embodied/models/openvla.txt"
    "$SCRIPT_DIR/embodied/models/openvla_oft.txt"
    "$SCRIPT_DIR/embodied/models/openpi.txt"
    "$SCRIPT_DIR/embodied/envs/maniskill.txt"
    "$SCRIPT_DIR/embodied/envs/metaworld.txt"
    "$SCRIPT_DIR/reason/megatron.txt"
)


SUPPORTED_TARGETS=("embodied" "reason" "prepare")
SUPPORTED_MODELS=("openvla" "openvla-oft" "openpi")
SUPPORTED_ENVS=("behavior" "maniskill_libero" "metaworld")

print_help() {
        cat <<EOF
Usage: bash install.sh <target> [options]

Targets:
    prepare                Install system dependencies and setup build env (Docker-like).
    embodied               Install embodied model and envs (default).
    reason                 Install reasoning stack (Megatron etc.).

Options (for target=embodied):
    --model <name>         Embodied model to install: ${SUPPORTED_MODELS[*]}.
    --env <name>           Single environment to install: ${SUPPORTED_ENVS[*]}.

Common options:
    -h, --help             Show this help message and exit.
    --venv <dir>           Virtual environment directory name (default: .venv).
    --no-venv              Do not create a venv, install into current environment.
    --python <path/ver>    Specify Python path or version to use (avoids download).
EOF
}

parse_args() {
    if [ "$#" -eq 0 ]; then
        print_help
        exit 0
    fi

    while [ "$#" -gt 0 ]; do
        case "$1" in
            -h|--help)
                print_help
                exit 0
                ;;
            --venv)
                if [ -z "${2:-}" ]; then
                    echo "--venv requires a directory name argument." >&2
                    exit 1
                fi
                VENV_DIR="${2:-}"
                shift 2
                ;;
            --no-venv)
                USE_CURRENT_ENV=1
                shift
                ;;
            --python)
                if [ -z "${2:-}" ]; then
                    echo "--python requires a path or version argument." >&2
                    exit 1
                fi
                PYTHON_VERSION="${2:-}"
                shift 2
                ;;
            --model)
                if [ -z "${2:-}" ]; then
                    echo "--model requires a model name argument." >&2
                    exit 1
                fi
                MODEL="${2:-}"
                shift 2
                ;;
            --env)
                if [ -n "$ENV_NAME" ]; then
                    echo "Only one --env can be specified." >&2
                    exit 1
                fi
                ENV_NAME="${2:-}"
                shift 2
                ;;
            --*)
                echo "Unknown option: $1" >&2
                echo "Use --help to see available options." >&2
                exit 1
                ;;
            *)
                if [ -z "$TARGET" ]; then
                    TARGET="$1"
                    shift
                else
                    echo "Unexpected positional argument: $1" >&2
                    echo "Use --help to see usage." >&2
                    exit 1
                fi
                ;;
        esac
    done

    if [ -z "$TARGET" ]; then
        TARGET="embodied"
    fi
}

create_and_sync_venv() {
    # Ensure build environment is set up (env vars, pip installed)
    setup_build_env

    if [ "$USE_CURRENT_ENV" -eq 1 ]; then
        VENV_DIR=$("$PYTHON_CMD" -c "import sys; print(sys.prefix)")
        echo "Using current environment at: $VENV_DIR"
    else
        if [ ! -d "$VENV_DIR" ]; then
            echo "Creating virtual environment at $VENV_DIR with $PYTHON_CMD"
            "$PYTHON_CMD" -m venv "$VENV_DIR"
        fi
        # shellcheck disable=SC1090
        source "$VENV_DIR/bin/activate"
    fi
    
    echo "Virtual environment activated: $VENV_DIR"
    echo "Active Python: $(which python)"
    echo "Active pip: $(which pip)"
    python --version
    
    # Set ManiSkill environment variables in virtual environment
    if [ -f "$VENV_DIR/bin/activate" ]; then
        # Remove old settings if exist
        sed -i '/^export MS_SKIP_ASSET_DOWNLOAD_PROMPT=/d' "$VENV_DIR/bin/activate"
        sed -i '/^export MS_ASSET_DIR=/d' "$VENV_DIR/bin/activate"
        sed -i '/^export MS_NO_NETWORK=/d' "$VENV_DIR/bin/activate"
        # Add ManiSkill environment variables
        echo "export MS_SKIP_ASSET_DOWNLOAD_PROMPT=1" >> "$VENV_DIR/bin/activate"
        echo "export MS_NO_NETWORK=0" >> "$VENV_DIR/bin/activate"
        # MS_ASSET_DIR will be set when assets are deployed
        echo "Virtual environment: ManiSkill environment variables configured"
    fi
    
    # Upgrade pip, setuptools, wheel, uv in the virtual environment
    echo "Upgrading pip, setuptools, wheel, uv in virtual environment..."
    python -m pip install --upgrade pip setuptools wheel uv
    
    # uv venv "$VENV_DIR" --python "$PYTHON_VERSION"
    # # shellcheck disable=SC1090
    # source "$VENV_DIR/bin/activate"
    # UV_TORCH_BACKEND=auto uv sync --active


}

install_prebuilt_flash_attn() {
    # Base release info – adjust when bumping flash-attn
    local flash_ver="2.7.4.post1"
    local base_url="https://github.com/Dao-AILab/flash-attention/releases/download/v${flash_ver}"

    # Detect Python tags
    local py_major py_minor
    py_major=$(python - <<'EOF'
import sys
print(sys.version_info.major)
EOF
)
    py_minor=$(python - <<'EOF'
import sys
print(sys.version_info.minor)
EOF
)
    local py_tag="cp${py_major}${py_minor}"   # e.g. cp311
    local abi_tag="${py_tag}"                 # we assume cpXY-cpXY ABI, adjust if needed

    # Detect torch version (major.minor) and strip dots, e.g. 2.6.0 -> 26
    local torch_mm
    torch_mm=$(python - <<'EOF'
import torch
v = torch.__version__.split("+")[0]
parts = v.split(".")
print(f"{parts[0]}.{parts[1]}")
EOF
)

    # Detect CUDA tag for flash-attention wheel
    # Note: PyTorch may be compiled with cu118/cu121 for CUDA 12.1 compatibility,
    # but flash-attention wheels use cu12 for all CUDA 12.x versions
    local cu_tag=$(get_cuda_tag_for_flash_attn)
    local torch_tag="torch${torch_mm}"        # e.g. torch2.6

    # We currently assume cxx11 abi FALSE and linux x86_64
    local platform_tag="linux_x86_64"
    local cxx_abi="cxx11abiFALSE"

    local wheel_name="flash_attn-${flash_ver}+${cu_tag}${torch_tag}${cxx_abi}-${py_tag}-${abi_tag}-${platform_tag}.whl"
    uv pip uninstall flash-attn || true
    install_local_wheel_if_exists "${base_url}/${wheel_name}"
}

install_prebuilt_apex() {
    # Example URL: https://github.com/RLinf/apex/releases/download/25.09/apex-0.1-cp311-cp311-linux_x86_64.whl
    local base_url="https://github.com/RLinf/apex/releases/download/25.09"
    local py_major py_minor
    py_major=$(python - <<'EOF'
import sys
print(sys.version_info.major)
EOF
)
    py_minor=$(python - <<'EOF'
import sys
print(sys.version_info.minor)
EOF
)
    local py_tag="cp${py_major}${py_minor}"   # e.g. cp311
    local abi_tag="${py_tag}"                 # we assume cpXY-cpXY ABI, adjust if needed
    local platform_tag="linux_x86_64"
    local wheel_name="apex-0.1-${py_tag}-${abi_tag}-${platform_tag}.whl"
        
    uv pip uninstall apex || true
    # Try local first, if not found (function handles it), then install from URL.
    # If install fails (e.g. 404), echo error.
    local local_wheel=$(get_local_wheel_path "${base_url}/${wheel_name}")
    uv pip install "${local_wheel}" || (echo "Apex wheel is not available for Python ${py_major}.${py_minor}, please install apex manually. See https://github.com/NVIDIA/apex" >&2; exit 1)
}

#=======================EMBODIED INSTALLERS=======================

install_common_embodied_deps() {
    uv pip install -e .[embodied]
    sudo bash $SCRIPT_DIR/embodied/sys_deps.sh
    
    add_env_var "NVIDIA_DRIVER_CAPABILITIES" "all"
    add_env_var "VK_DRIVER_FILES" "/etc/vulkan/icd.d/nvidia_icd.json"
    add_env_var "VK_ICD_FILENAMES" "/etc/vulkan/icd.d/nvidia_icd.json"
}

install_openvla_model() {
    case "$ENV_NAME" in
        "")
            ;;
        maniskill_libero)
            create_and_sync_venv
            install_common_embodied_deps
            install_maniskill_libero_env
            ;;
        *)
            echo "Environment '$ENV_NAME' is not supported for OpenVLA model." >&2
            exit 1
            ;;
    esac
    UV_TORCH_BACKEND=auto uv pip install -r $SCRIPT_DIR/embodied/models/openvla.txt --no-build-isolation
    install_prebuilt_flash_attn
    uv pip uninstall pynvml || true
}

install_openvla_oft_model() {
    case "$ENV_NAME" in
        "")
            ;;
        behavior)
            PYTHON_VERSION="3.10"
            create_and_sync_venv
            install_common_embodied_deps
            UV_TORCH_BACKEND=auto uv pip install -r $SCRIPT_DIR/embodied/models/openvla_oft.txt --no-build-isolation
            install_behavior_env
            ;;
        maniskill_libero)
            create_and_sync_venv
            install_common_embodied_deps
            install_maniskill_libero_env
            install_prebuilt_flash_attn
            UV_TORCH_BACKEND=auto uv pip install -r $SCRIPT_DIR/embodied/models/openvla_oft.txt --no-build-isolation
            ;;
        *)
            echo "Environment '$ENV_NAME' is not supported for OpenVLA-OFT model." >&2
            exit 1
            ;;
    esac
    uv pip uninstall pynvml || true
}

install_openpi_model() {
    case "$ENV_NAME" in
        "")
            ;;
        maniskill_libero)
            create_and_sync_venv
            install_common_embodied_deps
            install_maniskill_libero_env
            UV_TORCH_BACKEND=auto GIT_LFS_SKIP_SMUDGE=1 uv pip install -r $SCRIPT_DIR/embodied/models/openpi.txt
            install_prebuilt_flash_attn
            ;;
        metaworld)
            create_and_sync_venv
            install_common_embodied_deps
            UV_TORCH_BACKEND=auto GIT_LFS_SKIP_SMUDGE=1 uv pip install -r $SCRIPT_DIR/embodied/models/openpi.txt
            install_prebuilt_flash_attn
            install_metaworld_env
            ;;
        *)
            echo "Environment '$ENV_NAME' is not supported for OpenPI model." >&2
            exit 1
            ;;
    esac

    # Replace transformers models with OpenPI's modified versions
    local py_major_minor
    py_major_minor=$(python - <<'EOF'
import sys
print(f"{sys.version_info.major}.{sys.version_info.minor}")
EOF
)
    cp -r "$VENV_DIR/lib/python${py_major_minor}/site-packages/openpi/models_pytorch/transformers_replace/"* \
        "$VENV_DIR/lib/python${py_major_minor}/site-packages/transformers/"
    
    deploy_openpi_assets "$VENV_DIR"
    uv pip uninstall pynvml || true
}

#=======================ENV INSTALLERS=======================

install_maniskill_libero_env() {
    # Prefer an existing checkout if LIBERO_PATH is provided; otherwise clone into the venv.
    local libero_dir
    if [ -n "${LIBERO_PATH:-}" ]; then
        if [ ! -d "$LIBERO_PATH" ]; then
            echo "LIBERO_PATH is set to '$LIBERO_PATH' but the directory does not exist." >&2
            exit 1
        fi
        libero_dir="$LIBERO_PATH"
    else
        libero_dir="$VENV_DIR/libero"
        # Use clone_or_copy_repo instead of git clone
        clone_or_copy_repo "https://github.com/RLinf/LIBERO.git" "$libero_dir"
    fi

    uv pip install -e "$libero_dir"
    add_env_var "PYTHONPATH" "$(realpath "$libero_dir"):\$PYTHONPATH"
    UV_TORCH_BACKEND=auto uv pip install -r $SCRIPT_DIR/embodied/envs/maniskill.txt

    # Deploy ManiSkill assets (smart: uses local cache if available)
    deploy_maniskill_assets "$VENV_DIR"
    # Ensure ManiSkill environment variables are set in the virtual environment
    if [ -f "$VENV_DIR/bin/activate" ]; then
        # Set MS_ASSET_DIR if deployed
        if [ -n "${MS_ASSET_DIR:-}" ]; then
            add_env_var "MS_ASSET_DIR" "$MS_ASSET_DIR"
        fi
        # Ensure MS_SKIP_ASSET_DOWNLOAD_PROMPT is set to avoid interactive prompts
        add_env_var "MS_SKIP_ASSET_DOWNLOAD_PROMPT" "${MS_SKIP_ASSET_DOWNLOAD_PROMPT:-1}"
        # Set MS_NO_NETWORK if needed to fail fast when assets are missing
        add_env_var "MS_NO_NETWORK" "${MS_NO_NETWORK:-0}"
    fi
}

install_behavior_env() {
    # Prefer an existing checkout if BEHAVIOR_PATH is provided; otherwise clone into the venv.
    local behavior_dir
    if [ -n "${BEHAVIOR_PATH:-}" ]; then
        if [ ! -d "$BEHAVIOR_PATH" ]; then
            echo "BEHAVIOR_PATH is set to '$BEHAVIOR_PATH' but the directory does not exist." >&2
            exit 1
        fi
        behavior_dir="$BEHAVIOR_PATH"
    else
        behavior_dir="$VENV_DIR/BEHAVIOR-1K"
        # Use clone_or_copy_repo instead of git clone
        clone_or_copy_repo "https://github.com/RLinf/BEHAVIOR-1K.git" "$behavior_dir" "RLinf/v3.7.1" "1"
    fi

    pushd "$behavior_dir" >/dev/null
    ./setup.sh --omnigibson --bddl --joylo --confirm-no-conda --accept-nvidia-eula
    popd >/dev/null
    uv pip uninstall flash-attn || true
    uv pip install ml_dtypes==0.5.3 protobuf==3.20.3
    uv pip install click==8.2.1
    pushd ~ >/dev/null
    uv pip install torch==2.5.1 torchvision==0.20.1 torchaudio==2.5.1
    install_prebuilt_flash_attn
    popd >/dev/null
}

install_metaworld_env() {
    uv pip install -r $SCRIPT_DIR/embodied/envs/metaworld.txt
}

#=======================REASONING INSTALLER=======================

install_reason() {
    uv pip install -e .[sglang-vllm]

    # Megatron-LM
    # Prefer an existing checkout if MEGATRON_PATH is provided; otherwise clone into the venv.
    local megatron_dir
    if [ -n "${MEGATRON_PATH:-}" ]; then
        if [ ! -d "$MEGATRON_PATH" ]; then
            echo "MEGATRON_PATH is set to '$MEGATRON_PATH' but the directory does not exist." >&2
            exit 1
        fi
        megatron_dir="$MEGATRON_PATH"
    else
        megatron_dir="$VENV_DIR/Megatron-LM"
        # Use clone_or_copy_repo instead of git clone
        clone_or_copy_repo "https://github.com/NVIDIA/Megatron-LM.git" "$megatron_dir" "core_r0.13.0"
    fi

    add_env_var "PYTHONPATH" "$(realpath "$megatron_dir"):\$PYTHONPATH"

    # If TEST_BUILD is 1, skip installing megatron.txt
    if [ "$TEST_BUILD" -ne 1 ]; then
        UV_TORCH_BACKEND=auto APEX_CPP_EXT=1 APEX_CUDA_EXT=1 NVCC_APPEND_FLAGS="--threads 24" APEX_PARALLEL_BUILD=24 uv pip install -r $SCRIPT_DIR/reason/megatron.txt --no-build-isolation
    fi

    install_prebuilt_apex
    install_prebuilt_flash_attn
    uv pip uninstall pynvml || true
}

main() {
    parse_args "$@"

    # Patch files for non-prepare targets (trap EXIT will restore on any exit)
    if [ "$TARGET" != "prepare" ]; then
        # Ensure backup files are restored on any exit (success, failure, or interruption)
        trap 'restore_all_backups' EXIT
        patch_all_files_for_install
    fi

    case "$TARGET" in
        prepare)
            prepare_docker_like_env
            ;;
        embodied)
            if [ -z "$MODEL" ]; then
                echo "--model is required when target=embodied. Supported models: ${SUPPORTED_MODELS[*]}" >&2
                exit 1
            fi
            # validate model
            if [[ ! " ${SUPPORTED_MODELS[*]} " =~ " $MODEL " ]]; then
                echo "Unknown embodied model: $MODEL. Supported models: ${SUPPORTED_MODELS[*]}" >&2
                exit 1
            fi
            # check --env is set and supported
            if [ -n "$ENV_NAME" ]; then
                if [[ ! " ${SUPPORTED_ENVS[*]} " =~ " $ENV_NAME " ]]; then
                    echo "Unknown environment: $ENV_NAME. Supported environments: ${SUPPORTED_ENVS[*]}" >&2
                    exit 1
                fi
            else
                echo "--env must be specified when target=embodied." >&2
                exit 1
            fi

            case "$MODEL" in
                openvla)
                    install_openvla_model
                    ;;
                openvla-oft)
                    install_openvla_oft_model
                    ;;
                openpi)
                    install_openpi_model
                    ;;
            esac
            ;;
        reason)
            create_and_sync_venv
            install_reason
            ;;
        *)
			echo "Unknown target: $TARGET" >&2
			echo "Supported targets: ${SUPPORTED_TARGETS[*]}" >&2
            exit 1
            ;;
    esac
    
    # Note: Backup files will be restored by trap EXIT
}

main "$@"
