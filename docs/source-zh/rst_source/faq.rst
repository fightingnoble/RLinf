常见问题
========

下面整理了 RLinf 的常见问题。该部分会持续更新，欢迎大家不断提问，帮助我们改进！

------------------------------------

RuntimeError: The MUJOCO_EGL_DEVICE_ID environment variable must be an integer between 0 and 0 (inclusive), got 1.
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：** 运行设置了 MUJOCO_GL 环境变量为 "egl" 的模拟器时出现上述错误信息。

**原因：** 该错误是因为您的 GPU 环境未正确设置图形渲染，尤其是在 NVIDIA GPU 上。

**修复：** 检查您是否有此文件 `/usr/lib/x86_64-linux-gnu/libEGL_nvidia.so.0`。

1. 如果您有此文件，请检查您是否还拥有 `/usr/share/glvnd/egl_vendor.d/10_nvidia.json`。如果没有，请创建此文件并添加以下内容：

   .. code-block:: json

      {
         "file_format_version" : "1.0.0",
         "ICD" : {
            "library_path" : "libEGL_nvidia.so.0"
         }
      }

   然后在您的运行脚本中添加以下环境变量：

   .. code-block:: shell

      export NVIDIA_DRIVER_CAPABILITIES="all"

2. 如果您没有此文件，则表示您的 NVIDIA 驱动程序未正确安装图形功能。您可以尝试以下解决方案：

   * 重新安装 NVIDIA 驱动程序，并使用正确的选项启用图形功能。安装 NVIDIA 驱动程序时，有几个选项会禁用图形驱动程序。因此，您需要尝试安装NVIDIA的图形驱动。在Ubuntu上可以通过命令 ``apt install libnvidia-gl-<driver-version>`` 完成，具体参见NVIDIA的文档 https://docs.nvidia.com/datacenter/tesla/driver-installation-guide/ubuntu.html#compute-only-headless-and-desktop-only-no-compute-installation 。

   * 使用 **osmesa** 进行渲染，将运行脚本中的 `MUJOCO_GL` 和 `PYOPENGL_PLATFORM` 环境变量更改为 "osmesa"。但是，这可能会导致滚动过程比 EGL 慢 10 倍，因为它使用 CPU 进行渲染。



------------------------------------

任务迁移时出现 NCCL “cuda invalid argument”
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：** P2P 任务传输失败，报错 ``NCCL cuda invalid argument``。

**修复：** 若此机器上之前运行过任务，请先停止 Ray 并重新启动。

.. code-block:: bash

   ray stop

------------------------------------

SGLang 加载参数时出现 NCCL “cuda invalid argument”
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：** SGLang 在加载权重时报 ``NCCL cuda invalid argument``。

**原因：** Placement 不匹配。例如配置使用 *共享式（collocated）*，但训练（trainer）与生成（generation）实际跑在不同 GPU 上。

**修复：** 检查 Placement 策略。确保训练组与生成组按照 ``cluster.component_placement`` 指定的 GPU 放置。

------------------------------------

torch_memory_saver.cpp 中 CUDA CUresult Error（result=2）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：**
``CUresult error result=2 file=csrc/torch_memory_saver.cpp func=cu_mem_create line=103``

**原因：** SGLang 恢复缓存缓冲区时可用显存不足；常见于在更新前没有卸载推理权重的情况。

**修复：**

- 降低 SGLang 的静态显存占用（例如调低 ``static_mem_fraction``）。
- 确保在重新加载前，已正确释放推理权重。

------------------------------------

Gloo 超时 / “Global rank x is not part of group”
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：**

- ``RuntimeError: [../third_party/gloo/.../unbound_buffer.cc:81] Timed out waiting ... for recv``
- ``ValueError: Global rank xxx is not part of group``

**可能原因：** 之前的 SGLang 故障（见上面的 CUresult 错误）导致生成阶段未完成，Megatron 随后一直等待，直到 Gloo 超时。

**修复：**

1. 在日志中定位上一阶段的 SGLang 错误。  
2. 先解决 SGLang 的恢复/显存问题。  
3. 重新启动作业（必要时也重启 Ray）。

------------------------------------

数值精度 / 推理后端
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**提示：** SGLang 默认使用 **flashinfer** 作为注意力实现。若需更高稳定性或兼容性，可尝试 **triton**：

.. code-block:: yaml

   rollout:
     attention_backend: triton

------------------------------------

无法连接 GCS（ip:port）
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：** Worker 节点无法连接到给定地址上的 Ray head（GCS）。

**原因：** 在 0 号节点上通过以下命令获取 head 节点 IP：

.. code-block:: bash

   hostname -I | awk '{print $1}'

若该命令选择了其他节点不可达的网卡（如网卡顺序不一致；可达的是 ``eth0``，却选中了别的接口），Worker 将连接失败。

**修复：**

- 确认所选 IP 能被其他节点访问（例如使用 ping 测试）。
- 如有需要，请显式选择正确网卡对应的 IP 作为 Ray head，并将该 IP 告知各 Worker。

------------------------------------

Vulkan 兼容性错误：ErrorIncompatibleDriver
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：** 运行 ManiSkill 环境时出现以下错误：

.. code-block:: text

   vk::createInstanceUnique: ErrorIncompatibleDriver
   Failed to find system libvulkan. Fallback to SAPIEN builtin libvulkan.
   Failed to find glvnd ICD file.
   Your GPU driver does not support Vulkan.

**问题根源：**

1. **缺少 Vulkan 系统库**：Docker 容器中未安装 Vulkan 运行时库（`libvulkan1`、`vulkan-tools` 等）。
2. **Vulkan ICD 配置权限不足**：在运行 `sys_deps.sh` 时，由于权限问题，导致无法创建 Vulkan ICD 配置文件。

**解决办法：**

1. **安装 Vulkan 库**：在 Docker 构建时添加 Vulkan 包：

   .. code-block:: dockerfile

      RUN apt-get update && apt-get install -y --no-install-recommends \
          libvulkan1 mesa-vulkan-drivers vulkan-tools

2. **修复 ICD 配置权限**：
   确保执行 ``sys_deps.sh`` 的用户有sudo权限创建 Vulkan ICD 配置文件。

3. **可选：禁用渲染**：如果 Vulkan 问题持续存在，可以在训练配置中禁用渲染：

   .. code-block:: yaml

      env:
        init_params:
          render_mode: null  # 禁用渲染，仅进行物理仿真

------------------------------------

ManiSkill Assets 缺失错误
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：** Ray worker 初始化时出现以下错误：

.. code-block:: text

   Environment PutCarrotOnPlateInScene-v2 requires asset(s) bridge_v2_real2sim which could not be found
   RuntimeError: Simulator initialization failed: {'status': 'error', 'error': 'EOF when reading a line'}

**问题根源：**

1. **Assets 路径不匹配**：ManiSkill 默认查找用户目录 `~/.maniskill`，但 RLinf 将 assets 部署到虚拟环境目录 `.venv/.maniskill`。
2. **环境变量未持久化**：`MS_ASSET_DIR` 环境变量没有写入虚拟环境激活脚本，导致 Ray worker 无法获取正确路径。
3. **交互式下载阻塞**：`MS_SKIP_ASSET_DOWNLOAD_PROMPT` 未设置，导致尝试交互式下载 assets 时阻塞进程。

**解决办法：**

1. **检查 Assets 部署**：确保 `deploy_maniskill_assets` 函数正确执行，并设置了 `MS_ASSET_DIR`：

   .. code-block:: bash

      # 重新部署 assets（如果需要）
      source requirements/install_local/route.sh
      deploy_maniskill_assets .venv

2. **验证环境变量**：激活虚拟环境后检查：

   .. code-block:: bash

      source .venv/bin/activate
      echo $MS_ASSET_DIR  # 应显示绝对路径
      echo $MS_SKIP_ASSET_DOWNLOAD_PROMPT  # 应为 1

3. **手动设置（临时方案）**：如果自动设置失败，可以手动设置：

   .. code-block:: bash

      export MS_ASSET_DIR="/path/to/your/.venv/.maniskill"
      export MS_SKIP_ASSET_DOWNLOAD_PROMPT=1
      export MS_NO_NETWORK=0

4. **重建虚拟环境**：如果问题持续，重新运行完整安装流程：

   .. code-block:: bash

      bash requirements/install_local_wrap.sh

------------------------------------

TimeLimitWrapper 属性错误：'TimeLimitWrapper' object has no attribute 'obs_mode'
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：** Ray worker 初始化时出现以下错误：

.. code-block:: text

   Exception: 'TimeLimitWrapper' object has no attribute 'obs_mode'

**问题根源：**

ManiSkill 环境被 ``gym.wrappers.TimeLimit`` 包装后，环境对象变成了 ``TimeLimitWrapper`` 类型，而该 wrapper 没有 ``obs_mode`` 属性。在 RLinf 的代码中直接访问 ``self.env.obs_mode`` 时出错。

**解决办法：**

1. **修复代码访问**：修改 ``rlinf/envs/maniskill/maniskill_env.py`` 中的 ``_wrap_obs`` 方法：

   .. code-block:: python

      def _wrap_obs(self, raw_obs):
          # Access obs_mode from unwrapped environment to handle TimeLimit wrapper
          obs_mode = getattr(self.env.unwrapped, 'obs_mode', None)
          if obs_mode == "state":
              wrapped_obs = {"images": None, "task_description": None, "state": raw_obs}
          else:
              wrapped_obs = self._extract_obs_image(raw_obs)
          return wrapped_obs

2. **验证修复**：确保环境可以正常初始化和运行。

3. **检查其他类似问题**：搜索代码中是否还有其他直接访问 wrapper 属性的地方。

------------------------------------

Tensor 类型错误：expected Tensor as element 0 in argument 0, but got NoneType
~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~~

**现象：** Ray worker 运行时出现以下错误：

.. code-block:: text

   Exception: expected Tensor as element 0 in argument 0, but got NoneType

**问题根源：**

动作处理函数 ``prepare_actions_for_maniskill`` 的参数传递错误，导致 ``action_scale`` 参数被传递了错误的类型（字符串而不是数字），进而导致 NumPy 计算失败，返回了 ``None`` 而不是期望的 Tensor。

**解决办法：**

1. **检查动作处理参数**：确保 ``prepare_actions`` 函数调用时正确传递了 ``action_scale`` 参数：

   .. code-block:: python

      chunk_actions = prepare_actions(
          raw_chunk_actions=chunk_actions,
          simulator_type=self.cfg.env.train.simulator_type,
          model_name=self.cfg.actor.model.model_name,
          num_action_chunks=self.cfg.actor.model.num_action_chunks,
          action_dim=self.cfg.actor.model.action_dim,
          action_scale=self.cfg.actor.model.get("action_scale", 1.0),  # 确保传递数字类型
          policy=self.cfg.actor.model.get("policy_setup", None),
      )

2. **验证动作处理**：检查动作处理函数是否返回了有效的 Tensor。

3. **检查配置文件**：确保 ``action_scale`` 在配置文件中是数字类型，而不是字符串。
