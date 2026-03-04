## 输出信息 `nsys runs automatically in a single process mode (--run-agent-in-process=true)` 是 Nsight Systems 在特定环境下的**默认保护行为**，尤其是在 **Docker/容器** 环境中。

为什么会自动切换到“单进程模式”？

在正常的物理机环境下，`nsys` 采用“多进程模式”：它会启动一个主控制进程和一个后台 Agent 进程。Agent 进程通过 `ptrace` 等系统调用去“附着”到你的训练进程上进行采集。

但在 **Docker 容器** 中，这种模式会遇到很多障碍：
*   **权限限制**：容器默认没有 `CAP_SYS_PTRACE` 权限，`nsys` 的后台进程无法控制你的训练进程。
*   **PID 隔离**：容器内的进程空间受到限制，多进程间的通信（IPC）有时会因为容器配置不当而失效。
*   **信号处理**：在容器中，如果主进程（PID 1）退出，所有子进程会被强制杀掉，这可能导致采集报告损坏。

**因此，`nsys` 检测到自己在容器内运行后，会自动启用 `--run-agent-in-process=true`。** 
这意味着它不再启动后台进程，而是通过 `LD_PRELOAD` 将采集插件直接注入到你的 Python 进程内部。这对用户来说是无感的，且更加稳定。

**总结**：单进程模式是好事，它让你在 Docker 里跑分析更稳定。

## 有哪些log输出？

RLinf 框架的日志输出和导出逻辑主要分为以下几个层次：

### 1. 实验指标与配置导出 (自动导出)
框架通过 `MetricLogger` 模块（定义在 `rlinf/utils/metric_logger.py`）自动导出以下内容到 `${runner.logger.log_path}` 指定的目录：
- 这个路径默认定义在配置文件中，例如：`RLinf/examples/embodiment/config/maniskill_ppo_openvla_quickstart.yaml`
- 默认值为`../results` = 从 `config/` 目录向上一级 → `embodiment/` 目录 → 进入 `results/` 子目录；**绝对路径** = `RLinf/examples/embodiment/results/`。
- **通常被脚本覆盖**：通过 Hydra 命令行参数覆盖这个设置：`++runner.logger.log_path=${LOG_DIR}`

*   **TensorBoard/WandB/SwanLab 数据**: 训练过程中的标量（Loss, Reward, Steps 等）会持久化到这些后端的本地存储目录中。
*   **Hydra 配置**: 在 TensorBoard 目录下会自动保存一个 `config.yaml`，记录本次运行的所有超参数。
*   **视频记录**: 如果开启了视频保存，评估过程中的渲染视频会保存在 `video/eval` 子目录下。

### 2. 命令行文本日志 (通过脚本导出)
框架代码本身（Python 层）默认主要通过 `print` 和标准 `logging` 输出到控制台。为了方便回溯，提供的启动脚本通常会进行重定向：
*   **`run_embodiment.sh`**: 使用 `tee` 命令将所有控制台输出同步保存到日志文件中：
    ```bash
    # 在脚本中定义的路径
    MEGA_LOG_FILE="${LOG_DIR}/run_embodiment.log"
    # 执行命令并重定向
    ${CMD} 2>&1 | tee -a ${MEGA_LOG_FILE}
    ```
*   **`run_embodiment_profiling.sh`**: 主要导出 Nsight Systems 的 `.nsys-rep` 报告文件和 `profiling_metrics.json` 指标文件。

### 3. 分布式 Worker 日志 (Ray 自动导出)
由于 RLinf 基于 Ray 运行，各个 Worker（Actor, Rollout, Env）的 `stdout` 和 `stderr` 会被 Ray 自动捕获并存储在集群的日志目录中：
*   **默认路径**: `/tmp/ray/session_latest/logs/`
*   你可以通过 `ray attach` 或 `ray dashboard` 查看这些详细的后台进程日志。

### 4. 总结与建议
如果你需要查找之前的运行记录：
1.  **首选位置**: 查看你的实验结果目录（例如 `results/` 或 `logs/` 下的具体日期文件夹），寻找 `.log` 文件。
2.  **调试 Worker 崩溃**: 如果程序卡住或 Worker 报错但主进程没显示，请检查 `/tmp/ray/session_latest/logs/` 下对应的 `worker-*.out` 文件。
3.  **配置建议**: 如果你想改变日志存储位置，可以在启动命令中通过 Hydra 覆盖：
    ```bash
    python train_embodied_agent.py runner.logger.log_path=/your/custom/path
    ```
## 参数配置

Rlinf 通过 Hydra 配置系统来管理配置。Hydra 是一个用于管理复杂配置的库，支持命令行参数、配置文件、环境变量等多种配置源。
### 🔍 Hydra 配置语法解析
基本参数：
    --config_path
    --config_name
    --version_base
配置参数：
**`++` 前缀的作用**：在 Hydra 配置系统中，`++` 是**强制覆盖/添加**操作符，具有最高优先级。

#### Hydra 的三种语法规则：

1. **`key=value`** （标准设置）
   - 仅当配置项**已存在**时有效
   - 如果配置项不存在，会报错：`ConfigCompositionException`

2. **`+key=value`** （添加新项）
   - 用于添加**新的配置项**
   - 如果配置项已存在，会报错

3. **`++key=value`** （强制覆盖）
   - **无论是否存在**都会成功
   - 如果不存在会创建，如果存在会覆盖
   - **优先级最高**，会覆盖所有其他配置源

#### 🔧 Hydra 配置解析机制

当您运行类似这样的命令时：
```bash
python train_embodied_agent.py \
    --config-name maniskill_ppo_openvla_quickstart \
    ++profiling.tool=nvtx
```

Hydra 会按以下优先级顺序解析配置：

1. **基础配置文件** (`maniskill_ppo_openvla_quickstart.yaml`)
2. **命令行参数**（按出现顺序）
   - `key=value` 优先级较低
   - `++key=value` 优先级最高，会覆盖之前的所有设置

#### 💡 最佳实践建议

- **安全起见**：在脚本中使用 `++` 前缀可以避免因配置结构变化导致的错误
- **精确控制**：当你确定配置项存在且不想意外创建新项时，使用无前缀的 `key=value`
- **调试技巧**：如果遇到配置错误，可以在命令前加 `--config-path="" --config-name=null` 来查看最终合并的配置

这样设计确保了配置系统的灵活性和健壮性，即使配置文件结构发生变化，脚本也能正常工作。