# RLinf Profiling 指南

本指南介绍如何使用 RLinf 的性能分析（Profiling）系统，该系统基于 PyTorch Profiler 和 NVIDIA Nsight Systems。

## 核心设计

RLinf 的 profiling 系统设计参考了 verl 的最佳实践，采用了统一的接口和控制逻辑。

### 1. Profiling 模式 (PROFILER_MODE)

可以通过环境变量 `PROFILER_MODE` 或配置文件中的 `tool` 参数设置：

- **`nvtx`** (推荐): 配合 Nsight Systems 使用。通过 NVTX 标记在 Timeline 上显示函数调用层次，并使用 `cudaProfilerApi` 精确控制捕获范围。
- **`torch`**: 使用 PyTorch 内置的 Profiler。生成 Chrome Traces (.json)，适合通过 TensorBoard 进行分析。
- **`none`**: 禁用所有 profiling 逻辑。

### 2. 统一控制逻辑

所有的 profiling 行为由 `RLinfProfiler` 和 `StepController` 统一管理：

- **Driver 进程**: 训练脚本本身（如 `train_embodied_agent.py`）会被分析。
- **Worker 进程**: 通过 Ray 的 `runtime_env` 自动在分布式 worker 中开启分析。

### 3. 精确控制捕获范围 (cudaProfilerApi)

为了避免捕获漫长的初始化过程和不必要的数据，我们使用 `cudaProfilerApi` 模式。只有在代码中调用 `torch.cuda.profiler.start()` 和 `stop()` 时，Nsight 才会记录数据。

## 配置参数

主要配置位于 `rlinf/config/profiling_config.yaml`。

| 参数 | 说明 | 推荐值 |
|------|------|--------|
| `tool` | profiling 工具 | `nvtx` |
| `steps` | 要进行分析的 global step 列表 | `[10, 20]` |
| `continuous` | 是否将连续的 step 合并到一个 trace 文件中 | `false` |
| `nsight.controller_nsight_options` | 传递给 Driver 进程的 nsys 参数 | 见示例 |
| `nsight.worker_nsight_options` | 传递给 Worker 进程的 nsys 参数 | 见示例 |

## 使用步骤

### 1. 准备配置文件

复制并修改示例配置：
```bash
cp rlinf/config/profiling_config.example.yaml rlinf/config/profiling_config.yaml
```

### 2. 使用 Nsight Systems 进行分析 (推荐)

使用提供的包装脚本启动训练：
```bash
bash examples/embodiment/run_embodiment_profiling.sh
```

该脚本会自动完成以下工作：
1. 从 `profiling_config.yaml` 读取要 profile 的 steps。
2. 计算 `repeat-shutdown` 次数。
3. 构造并执行 `nsys profile` 命令。
4. 启动训练脚本。

### 3. 使用 PyTorch Profiler 进行分析

1. 修改 `profiling_config.yaml` 中的 `tool: "torch"`。
2. 启动脚本：
   ```bash
   bash examples/embodiment/run_embodiment_profiling.sh -m record_function
   ```
3. 使用 TensorBoard 查看结果：
   ```bash
   tensorboard --logdir logs/profiling-<TIMESTAMP>/profiling
   ```

## 常见问题 (FAQ)

### Q: 为什么没有生成 .nsys-rep 文件？
- 确认 `profiling_config.yaml` 中的 `tool` 设置为 `nvtx`。
- 确认 `steps` 列表不为空，且训练运行到了这些步数。
- 检查 `nsys` 命令是否在环境中可用。

### Q: 如何分析分布式 Worker 的性能？
- 分布式 Worker 的 trace 文件通常保存在 Ray 的日志目录中（默认为 `/tmp/ray/session_latest/logs/nsight/`）。
- 您可以使用 `nsys-ui` 同时打开多个 trace 文件进行多机对比分析。

### Q: `continuous: true` 有什么用？
- 如果您想观察步与步之间的衔接（如数据传输、调度开销），可以将 `continuous` 设置为 `true`。它会从第一个指定的步数开始，一直捕获到最后一个指定的步数结束。

### Q: 训练在初始化阶段卡住怎么办？
- **现象**：程序在 `runner.init_workers().wait()` 处卡住，GPU 利用率为 0，没有日志输出。
- **原因**：Nsight Systems 的 trace 选项在分布式环境中初始化时会造成底层锁竞争或资源死锁。特别是在 ManiSkill 等渲染引擎初始化时，会同时触发多个进程的 GPU 资源争夺。例如：`vulkan` 和 `osrt`
- **解决方案**：
  1. 从 `profiling_config.yaml` 的 `worker_nsight_options.trace` 中移除 `vulkan` 和 `osrt`。
  2. 在 `worker_nsight_options` 中添加 `delay: 60`（延迟 60 秒启动 nsys 采集）。
  3. 也可以在 `run_embodiment_profiling.sh` 中相应调整 driver 侧的 trace 选项。
- **验证**：如果问题解决，您应该能看到 `[Profiling] START step=...` 打印，且 GPU 利用率开始上升。

### Q: 报错 `NotImplementedError: Got <class 'list'>, but numpy array or torch tensor are expected` 怎么办？
- **现象**：TensorBoard 记录指标时报错，提示不支持列表类型。
- **原因**：`embodied_runner.py` 中的 rollout 动态性统计（`episodes_per_rollout` 和 `steps_per_episode`）以列表形式存储，无法直接传给 TensorBoard 的 `add_scalar()` 方法。
- **解决方案**：已修复为将列表转换为标量统计量（均值、最大值、最小值），确保与 TensorBoard 兼容：
  - `rollout_stats/episodes_per_rollout_mean`
  - `rollout_stats/episodes_per_rollout_max`
  - `rollout_stats/episodes_per_rollout_min`
  - `rollout_stats/steps_per_episode_mean`
  - `rollout_stats/steps_per_episode_max`
  - `rollout_stats/steps_per_episode_min`
  - `rollout_stats/total_steps`

