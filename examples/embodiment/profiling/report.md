## 期望获得：

1. 端到端flow级别的延迟break down
┌──────────────────────────────────────────────────┐
│            RLinf 训练循环 Profiling 覆盖          │
├──────────────────────────────────────────────────┤
│  Runner.run() [ScopedTimer]                      │
│    ├── sync_weights [Timer]                      │
│    │     ├── Actor.sync_model_to_rollout         │
│    │     └── Rollout.sync_model_from_actor       │
│    ├── generate_rollouts [Timer]                 │
│    │     ├── Env.interact                        │
│    │     │     ├── recv_chunk_actions            │
│    │     │     ├── env_step                      │
│    │     │     └── send_env_batch                │
│    │     ├── Rollout.generate                    │
│    │     │     ├── recv_env_output               │
│    │     │     ├── predict_action                │
│    │     │     ├── send_chunk_actions            │
│    │     │     └── send_rollout_batch            │
│    │     └── Actor.recv_rollout_batch            │
│    ├── cal_adv_and_returns [Timer]               │
│    │     └── compute_adv_and_returns             │
│    └── actor_training [Timer]                    │
│          └── run_training                        │
│                ├── get_batch                     │
│                ├── forward_pass                  │
│                └── backward_pass                 │
└──────────────────────────────────────────────────┘
2. 系统资源利用率break down
3. 解析Ray 和 Rlinf中claim的负载动态性：
    1. Ray/ray 中提到的rollout动态分布：
        1. rollout时间（simulation 时间，generation时间）
            1. rollout总step数量
            2. 每轮rollout 包含的episode个数
            3. 每个episode包含的step数量
        2. training时间

### 挑战

1. Ray的异步调用
2. 长时间运行的任务
3. 多机多卡
4. 多层次负载：Flow级别的时序，kernel级别的性能

### flow 级别的延迟
[在RL强化学习场景下对于多系统如何进行性能分析？ - 随机游走的回答 - 知乎](https://www.zhihu.com/question/1967637440933127877/answer/1967641637401391734)

### kernel 级别的延迟

PyTorch Profiler：如果需要快速迭代 PyTorch 代码（如 RLinf 的 rollout/training），用它作为第一步。
- recipe: 
    - https://help.aliyun.com/zh/ack/cloud-native-ai-suite/use-cases/use-pytorch-profiler-to-realize-performance-analysis-and-troubleshooting-of-large-models

Nsight Systems：
如果 PyTorch Profiler 显示 discrepancies 或需系统级 insight（如多卡带宽瓶颈），再用 Nsight。
注意：nsight system 针对python支持区域标注，有torch.cuda.nvtx 和 独立nvtx两个版本api，后者支持的标记更加丰富。

- recipe:
    - [17.3. GPU Profiling — Kempner Institute Computing Handbook](https://handbook.eng.kempnerinstitute.harvard.edu/s5_ai_scaling_and_engineering/scalability/gpu_profiling.html)
    - [Speed Up PyTorch Training by 3x with NVIDIA Nsight and PyTorch 2.0 Tricks | Practical ML](https://arikpoz.github.io/posts/2025-05-25-speed-up-pytorch-training-by-3x-with-nvidia-nsight-and-pytorch-2-tricks/)


### Verl Profiler System:
1. 兼容多种工具：torch profiler，nsight system
2. 能够正确处理ray的异步调用
3. 能够筛选循环轮次，profile 捕获范围（Profile Capture-Range），以及特定的rank

参考链接：
[verl Profiler System — verl documentation](https://verl.readthedocs.io/en/latest/perf/verl_profiler_system.html)

[NVIDIA Nsight Systems profiling in verl — verl documentation](https://verl.readthedocs.io/en/latest/perf/nsight_profiling.html)

[(99+ 封私信 / 68 条消息) NVIDIA技术沙龙《强化学习流水线优化：性能分析与 Rollout加速》演讲笔记 - 知乎](https://zhuanlan.zhihu.com/p/1947055154202387888)


## 代码风格：

profiling的代码和框架代码尽量分离——不要使用繁琐的 if profiling_enabled 判断和显式的 record_function 上下文管理器。

对于profiling逻辑：
定义profiling 类管理profiling上下文（profiling开始前的准备，执行后Profiler处理数据）；使用warp或者contextmanager (需要仔细考虑使用warp或者contextmanager的差别是什么)

### 使用warp或者contextmanager的差别：

1. 使用 @wraps 的场景：装饰具体函数，进行细粒度 profiling
    
    适用：当你需要对 RLinf 中的特定函数（如模型前向传播、动作采样、环境 step、损失计算）进行性能测量时。
    为什么适合：Profiling 往往针对单个函数调用，需要保留原函数元信息（name、doc），便于调试和栈追踪（尤其在分布式 Ray 环境中）。
    优势：不改变函数调用方式，易于插入到 RLinf 的 worker、rollout 或 trainer 模块中。
    
2. 使用 @contextmanager 的场景：包裹代码块，进行阶段性 profiling
    
    适用：当你需要对 RLinf 训练的一个完整阶段（如整个 rollout 循环、一个 episode 的采样、PPO 的一个 update 迭代）进行资源监控和清理时。
    为什么适合：VLA RL 训练涉及多组件交互（simulator rendering + model inference + env step），需要确保进入/退出时自动记录时间、GPU 内存，甚至异常时也清理资源。
    优势：支持 with 语句，自动处理异常后的清理（e.g., 释放 CUDA 缓存），更安全、自然地包裹大块代码。

## Nsight Systems 使用方法

### NVTX 标记 API

NVIDIA Tools Extension (NVTX) API 用于在 Timeline 视图中标记 CPU 线程的活动范围，这些范围会投影到 GPU 上，便于观察 CPU 代码段触发的 GPU 活动。RLinf 提供两种 NVTX 标记方式：

1. **torch.cuda.nvtx 模块**：PyTorch 内置的 NVTX 封装，提供同步和异步标记接口
   - `torch.cuda.nvtx.range_push(message)` / `pop()`：同步标记范围，适用于单个线程内的代码段
   - `torch.cuda.nvtx.range_push_async(message)` / `pop_async()`：异步标记，适用于跨线程或需要非阻塞的场景
   - `torch.cuda.nvtx.range_push_wait(message)` / `pop_wait()`：等待模式，在范围内插入同步点
   - `torch.cuda.nvtx.range_push_wait_async(message)` / `pop_wait_async()`：结合异步和等待的混合模式

2. **nvtx-py 模块**：独立的 NVTX Python 绑定，提供更丰富的功能（详见 https://nvidia.github.io/NVTX/python/index.html）
   - 支持自定义 Domain（命名空间）以组织不同模块的标记
   - 支持颜色标记以在 Timeline 中区分不同类别的活动
   - 支持命名 CPU/GPU 资源以改善多进程、多设备环境的可读性
   - 示例：`nvtx.annotate(message="training_step", domain="rlinf.runner", color="blue")`

在 RLinf 中，推荐使用 `nvtx-py` 的 `annotate` 装饰器和上下文管理器，通过 Domain 和颜色实现模块化标记体系（如 `rlinf.env`、`rlinf.rollout`、`rlinf.actor`）。

### Nsight Systems CLI 核心选项

Nsight Systems CLI 通过 `nsys profile` 命令收集性能数据，关键选项分为捕获控制、性能追踪、输出控制和高级选项四类。

**捕获控制选项**控制数据收集的时机和范围。`--trace` 指定要追踪的 API 层，在分布式环境中初始化阶段应避免追踪 `vulkan` 和 `osrt`，这些选项可能导致 ManiSkill 等渲染引擎初始化时出现锁竞争或死锁。Worker 进程建议使用 `cuda,nvtx,cublas,cudnn`，Driver 进程可使用 `cuda,nvtx,osrt,cudnn,cublas,ucx`。`--capture-range=cudaProfilerApi` 使用 CUDA Profiler API 控制捕获范围，程序必须显式调用 `cudaProfilerStart()`（Python 中为 `torch.cuda.profiler.start()`）和 `cudaProfilerStop()` 来开始/停止数据收集，这是避免捕获漫长初始化过程和不必要数据的关键选项。`--capture-range-end=repeat-shutdown:n` 指定捕获范围的结束行为，当使用 `cudaProfilerApi` 模式时，`n` 表示 `cudaProfilerStart/stop` 对的重复次数，例如若要在 3 个 step 进行 profiling，设置为 `repeat-shutdown:3`。`--delay=n` 延迟启动采集 n 秒，跳过应用程序启动阶段的初始化工作，Worker 进程建议设置 60-90 秒以覆盖 `init_worker` 耗时。`--duration=n` 指定采集持续时间（仅在 `capture-range=none` 时有效）。`--kill=none` 采集完成后不强制终止应用程序进程组，让程序自行退出，这是配合 `cudaProfilerApi` 模式的必要选项。

**性能追踪选项**控制收集哪些性能指标。`--gpu-metrics-devices=all` 收集所有 GPU 设备的硬件指标（如 SM 利用率、内存带宽、计算吞吐量）。`--cuda-memory-usage=true` 追踪 CUDA 内存分配和释放，记录内存使用峰值和分配堆栈。`--cuda-graph-trace=graph` 追踪 CUDA Graph 执行，`graph` 模式将整个图作为一个整体追踪，适用于分析图启动开销，`node` 模式单独追踪图内的每个节点。`--cudabacktrace=true` 捕获 CUDA API 调用的回溯信息，帮助定位内存分配或内核启动的代码位置。

**输出和控制选项**控制数据输出和行为。`--output` 指定输出文件路径，默认生成 `.nsys-rep` 二进制文件，可用 `nsys-ui` 或 `nsys stats` 分析。`--wait=primary` 等待主进程完成后再结束采集，适用于使用 CUDA Profiler API 或 NVTX 控制的场景。`-x=true` 在采集结束后自动生成报告，用于快速验证数据收集是否成功。`--force-overwrite=true` 覆盖已存在的输出文件。

**高级选项**提供更精细的控制。`--nvtx-capture=range@domain` 在 NVTX 模式下指定要捕获的 NVTX 范围和域，例如 `--nvtx-capture="training_step@rlinf.runner"` 只捕获域 `rlinf.runner` 中名为 `training_step` 的范围。`--python-sampling=true` 启用 Python 回溯采样，追踪 Python 解释器的执行路径，有助于定位 CPU 瓶颈。

在分布式 RL 训练中，Driver 进程和 Worker 进程的 profiling 配置需要区分。Driver 进程通过 `nsys profile` 命令包装启动，Worker 进程通过 Ray 的 `runtime_env` 传递 `nsight_options` 字典。Worker 侧的 `worker_nsight_options` 应使用精简的 trace 选项并设置 `delay` 参数，避免初始化阶段的资源竞争。