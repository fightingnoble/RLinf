#!/bin/bash
# RLinf Embodied Agent Profiling Script with Nsight Systems
# This script wraps the training command with Nsight Systems profiling
#
# Note: The nsys options in this script correspond to controller_nsight_options in
#       rlinf/config/profiling_config.yaml. Worker nsight options are passed via
#       Ray's runtime_env (see worker_nsight_options in the config).
#
# Usage:
#   ./run_embodiment_profiling.sh [options]
#
# Options:
#   -c, --config NAME       Configuration name (default: maniskill_ppo_openvla_quickstart)
#   -m, --mode MODE         PROFILER_MODE: nvtx | torch (default: nvtx)
#   -d, --delay SECONDS     Skip first N seconds for warm-up (default: 10)
#   -t, --duration SECONDS  Profile for N seconds (default: 120)
#   -o, --output DIR        Custom output directory (default: auto-generated)
#   --capture-range MODE    Capture mode: none | cudaProfilerApi | nvtx (default: none)
#   --nvtx-trigger NAME     NVTX range to capture (e.g. "training_loop" or "step@rlinf.runner")
#   --python-sampling       Enable Python backtrace sampling
#
# Capture Range Modes (recommended for long-running VLA training):
#   --capture-range=none           - Time-based: use --delay + --duration (default)
#   --capture-range=cudaProfilerApi - API-based: use cudaProfilerStart/Stop in code
#   --capture-range=nvtx           - NVTX-based: trigger by named NVTX range
#
# Examples:
#   # Default: Nsight Systems + NVTX markers, 120s recording
#   ./run_embodiment_profiling.sh
#
#   # Precise mode: Triggered by NVTX range "training_loop"
#   ./run_embodiment_profiling.sh --capture-range nvtx --nvtx-trigger training_loop
#
#   # PyTorch Profiler + TensorBoard traces, 60s recording
#   ./run_embodiment_profiling.sh -m torch -t 60
#
#   # With Python sampling
#   ./run_embodiment_profiling.sh --python-sampling
#
#   # DEBUG: auto function annotation
#   ./run_embodiment_profiling.sh --auto-profile

set -e

# Default values
CONFIG_NAME="maniskill_ppo_openvla_quickstart"
PROFILER_MODE="nvtx"
DELAY=10
DURATION=120
OUTPUT_DIR=""
CAPTURE_RANGE="cudaProfilerApi"
NVTX_TRIGGER=""
PYTHON_SAMPLING="false"

# Argument parsing
while [[ $# -gt 0 ]]; do
    case $1 in
        -c|--config)
            CONFIG_NAME="$2"
            shift 2
            ;;
        -m|--mode)
            PROFILER_MODE="$2"
            shift 2
            ;;
        -d|--delay)
            DELAY="$2"
            shift 2
            ;;
        -t|--duration)
            DURATION="$2"
            shift 2
            ;;
        -o|--output)
            OUTPUT_DIR="$2"
            shift 2
            ;;
        --capture-range)
            CAPTURE_RANGE="$2"
            shift 2
            ;;
        --nvtx-trigger)
            NVTX_TRIGGER="$2"
            shift 2
            ;;
        --python-sampling)
            PYTHON_SAMPLING="true"
            shift
            ;;
        *)
            echo "Unknown option: $1"
            exit 1
            ;;
    esac
done

# Set environment variables
# (No environment variables needed)

# Set up paths
SCRIPT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"
REPO_PATH=$(dirname $(dirname "$SCRIPT_DIR"))
SRC_FILE="${REPO_PATH}/examples/embodiment/train_embodied_agent.py"
CONFIG_FILE="${REPO_PATH}/rlinf/config/profiling_config.yaml"

# Get profiling repeat count from config file using Python
# This determines how many capture ranges nsys should expect
if [ -f "$CONFIG_FILE" ]; then
    REPEAT_COUNT=$(python3 -c "
import yaml
try:
    with open('$CONFIG_FILE', 'r') as f:
        cfg = yaml.safe_load(f).get('profiling', {})
        steps = sorted(cfg.get('steps', []))
        continuous = cfg.get('continuous', False)
        if not steps:
            print(0)
        elif not continuous:
            print(len(steps))
        else:
            segments = 1
            for i in range(1, len(steps)):
                if steps[i] != steps[i-1] + 1:
                    segments += 1
            print(segments)
except Exception:
    print(0)
")
else
    REPEAT_COUNT=0
fi

# Set up environment variables (same as run_embodiment.sh)
export EMBODIED_PATH="$( cd "$(dirname "${BASH_SOURCE[0]}" )" && pwd )"
export REPO_PATH=$(dirname $(dirname "$EMBODIED_PATH"))
export PYTHONPATH=${REPO_PATH}:$PYTHONPATH

# Environment setup (same as run_embodiment.sh)
export MUJOCO_GL="egl"
export PYOPENGL_PLATFORM="egl"

export OMNIGIBSON_DATA_PATH=$OMNIGIBSON_DATA_PATH
export OMNIGIBSON_DATASET_PATH=${OMNIGIBSON_DATASET_PATH:-$OMNIGIBSON_DATA_PATH/behavior-1k-assets/}
export OMNIGIBSON_KEY_PATH=${OMNIGIBSON_KEY_PATH:-$OMNIGIBSON_DATA_PATH/omnigibson.key}
export OMNIGIBSON_ASSET_PATH=${OMNIGIBSON_ASSET_PATH:-$OMNIGIBSON_DATA_PATH/omnigibson-robot-assets/}
export OMNIGIBSON_HEADLESS=${OMNIGIBSON_HEADLESS:-1}
export ISAAC_PATH=${ISAAC_PATH:-/path/to/isaac-sim}
export EXP_PATH=${EXP_PATH:-$ISAAC_PATH/apps}
export CARB_APP_PATH=${CARB_APP_PATH:-$ISAAC_PATH/kit}

# Determine output directory
if [ -z "$OUTPUT_DIR" ]; then
    TIMESTAMP=$(date +'%Y%m%d-%H%M%S')
    LOG_DIR="${REPO_PATH}/logs/profiling-${TIMESTAMP}"
else
    LOG_DIR="$OUTPUT_DIR"
fi

# Create log directory
mkdir -p "${LOG_DIR}"

echo "=== RLinf Profiling with Nsight Systems ==="
echo "Configuration: ${CONFIG_NAME}"
echo "Profiler mode: ${PROFILER_MODE}"
echo "Capture range: ${CAPTURE_RANGE}"
if [ "$CAPTURE_RANGE" = "cudaProfilerApi" ]; then
    echo "Repeat count: ${REPEAT_COUNT}"
elif [ "$CAPTURE_RANGE" = "nvtx" ]; then
    echo "NVTX capture filter: ${NVTX_TRIGGER}"
else
    echo "Delay: ${DELAY}s"
    echo "Duration: ${DURATION}s"
fi
echo "Python sampling: ${PYTHON_SAMPLING}"
echo "Output directory: ${LOG_DIR}"
echo "=========================================="

# 选择要追踪的 API
# trace: "cuda,nvtx,osrt,vulkan,cudnn,cublas,ucx"

# 追踪 GPU 内存使用情况（必须是字符串类型）
# cuda-memory-usage: "true"

# CUDA graphs 追踪模式
# "node": 每个节点单独追踪
# "graph": 整个图作为一个整体追踪
# cuda-graph-trace: "graph"

# GPU metrics 设备选择
# gpu-metrics-devices: "all"

# 启用 CUDA backtrace
# cudabacktrace: "true"

# Build the training command
TRAIN_CMD="python ${SRC_FILE} \
    --config-path ${EMBODIED_PATH}/config/ \
    --config-name ${CONFIG_NAME} \
    ++runner.logger.log_path=${LOG_DIR} \
    ++runner.profiling_config=${CONFIG_FILE} \
    ++profiling.tool=${PROFILER_MODE}"

echo "Training command: ${TRAIN_CMD}"

# Build nsys command
# These options align with profiling_config.yaml -> nsight.controller_nsight_options
NSYS_OPTS="--trace=cuda,nvtx,osrt,cudnn,cublas,ucx"
NSYS_OPTS+=" --gpu-metrics-devices=all"
NSYS_OPTS+=" --cuda-memory-usage=true"
NSYS_OPTS+=" --cuda-graph-trace=graph"
NSYS_OPTS+=" --cudabacktrace=true"
NSYS_OPTS+=" --kill=none"

if [ "$CAPTURE_RANGE" = "cudaProfilerApi" ]; then
    NSYS_OPTS+=" --capture-range=cudaProfilerApi"
    if [ "$REPEAT_COUNT" -gt 0 ]; then
        NSYS_OPTS+=" --capture-range-end=repeat-shutdown:${REPEAT_COUNT}"
    fi
elif [ "$CAPTURE_RANGE" = "nvtx" ]; then
    NSYS_OPTS+=" --capture-range=nvtx"
    if [ -n "$NVTX_TRIGGER" ]; then
        # Format: range@domain. If no domain is provided, use range@*
        if [[ "$NVTX_TRIGGER" == *"@"* ]]; then
            NSYS_OPTS+=" --nvtx-capture=${NVTX_TRIGGER}"
        else
            NSYS_OPTS+=" --nvtx-capture=${NVTX_TRIGGER}@*"
        fi
    fi
elif [ "$CAPTURE_RANGE" = "none" ]; then
    # Time-based mode (backward compatibility / manual override)
    NSYS_OPTS+=" --delay=${DELAY} --duration=${DURATION}"
else
    # Any other explicitly passed mode
    NSYS_OPTS+=" --capture-range=${CAPTURE_RANGE}"
fi

if [ "$PYTHON_SAMPLING" = "true" ]; then
    NSYS_OPTS+=" --python-sampling=true"
    NSYS_OPTS+=" --python-sampling-frequency=1000"
fi

echo "Running Nsight Systems profiling..."
nsys profile ${NSYS_OPTS} \
    --force-overwrite=true \
    --output="${LOG_DIR}/nsys_profile" \
    --wait primary \
    -x true \
    ${TRAIN_CMD} 2>&1 | tee -a "${LOG_DIR}/nsys_profile.log"

echo "=========================================="
echo "Profiling completed!"
echo "Results saved to: ${LOG_DIR}"
echo ""
echo "To view Nsight Systems results:"
echo "  nsys-ui ${LOG_DIR}/nsys_profile.nsys-rep"
echo ""
echo "To get summary statistics:"
echo "  nsys stats --report gputrace ${LOG_DIR}/nsys_profile.nsys-rep"
echo ""
echo "PyTorch Profiler traces (if PROFILER_MODE=torch):"
echo "  tensorboard --logdir ${LOG_DIR}/profiling"
echo ""
echo "Custom profiling metrics:"
echo "  cat ${LOG_DIR}/profiling/profiling_metrics.json"
echo ""
echo "Note: Make sure to set profiling.enabled=true in ${CONFIG_FILE}"
