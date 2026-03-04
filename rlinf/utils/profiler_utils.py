# Copyright 2025 The RLinf Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     https://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

import os
import asyncio
import functools
from abc import ABC, abstractmethod
from functools import wraps
from contextlib import ContextDecorator, contextmanager, nullcontext
from typing import Union, Callable, ContextManager, Optional, List, Any, Dict
import torch
from torch.profiler import profile, ProfilerActivity, record_function, tensorboard_trace_handler
import nvtx
from rlinf.utils.profiling_metrics import ProfilingMetricsCollector


# NVTX Domain定义（单例模式）
class NVTXDomains:
    _domains = {}

    @classmethod
    def get(cls, name: str) -> nvtx.Domain:
        if name not in cls._domains:
            cls._domains[name] = nvtx.Domain(name)
        return cls._domains[name]


# Domain颜色映射（便于在Nsight中识别）
DOMAIN_COLORS = {
    "rlinf.env": "green",
    "rlinf.rollout": "blue",
    "rlinf.actor": "red",
    "rlinf.runner": "yellow",
}


class BaseProfilerImpl(ABC):
    """Profiler实现的抽象基类"""
    
    @abstractmethod
    def start(self, step: int = -1, **kwargs) -> None:
        """开始profiling"""
        pass
    
    @abstractmethod
    def stop(self) -> None:
        """停止profiling"""
        pass
    
    def step(self) -> None:
        """更新profiler内部状态（如torch profiler的step）"""
        pass
    
    @abstractmethod
    def get_profiling_ctx(self, name: str, domain: str = None):
        """返回profiling上下文管理器"""
        pass
    
    @property
    @abstractmethod
    def is_enabled(self) -> bool:
        """Profiler是否启用"""
        pass


class NVTXProfilerImpl(BaseProfilerImpl):
    """Nsight Systems Profiler实现，使用NVTX标记和cudaProfilerApi"""
    
    def __init__(self, config: Dict[str, Any] = None):
        self.config = config or {}
        self._this_step = False
    
    def start(self, step: int = -1, **kwargs) -> None:
        self._this_step = True
        if torch.cuda.is_available():
            # 通过cudaProfilerApi告知Nsight开始捕获
            # 这对应于 nsys profile --capture-range=cudaProfilerApi
            torch.cuda.profiler.start()
    
    def stop(self) -> None:
        self._this_step = False
        if torch.cuda.is_available():
            torch.cuda.profiler.stop()
    
    def get_profiling_ctx(self, name: str, domain: str = None):
        if not self._this_step:
            return nullcontext()
        
        nvtx_domain = NVTXDomains.get(domain) if domain else None
        color = DOMAIN_COLORS.get(domain, "white") if domain else "white"
        return nvtx.annotate(message=name, domain=nvtx_domain, color=color)

    @property
    def is_enabled(self) -> bool:
        return True


class TorchProfilerImpl(BaseProfilerImpl):
    """PyTorch Profiler实现"""
    
    def __init__(self, config: Dict[str, Any] = None):
        self.config = config or {}
        self._profiler = None
        self._is_running = False
    
    def start(self, step: int = -1, **kwargs) -> None:
        if self._is_running:
            return
            
        save_path = self.config.get("save_path", "./profiling")
        if not os.path.exists(save_path):
            os.makedirs(save_path, exist_ok=True)
            
        rank = int(os.environ.get("RANK", 0))
        self._profiler = profile(
            activities=[ProfilerActivity.CPU, ProfilerActivity.CUDA],
            record_shapes=self.config.get("record_shapes", True),
            profile_memory=self.config.get("profile_memory", True),
            with_stack=self.config.get("with_stack", False),
            on_trace_ready=tensorboard_trace_handler(save_path)
        )
        self._profiler.__enter__()
        self._is_running = True
    
    def stop(self) -> None:
        if self._profiler and self._is_running:
            self._profiler.__exit__(None, None, None)
            self._profiler = None
            self._is_running = False
    
    def step(self) -> None:
        if self._profiler and self._is_running:
            self._profiler.step()
    
    def get_profiling_ctx(self, name: str, domain: str = None):
        if not self._is_running:
            return nullcontext()
        return record_function(name)

    @property
    def is_enabled(self) -> bool:
        return self._is_running


class StepController:
    """Step级别的profiling控制器，实现verl的三状态变量逻辑"""
    
    def __init__(self, steps: List[int] = None, continuous: bool = False):
        self.steps = set(steps or [])
        self.continuous = continuous
        
        # 识别连续段
        if self.continuous and steps:
            self._segments = self._identify_continuous_segments(sorted(steps))
        else:
            self._segments = [[s] for s in sorted(list(self.steps))]
            
        # 三状态变量
        self._prev_step_profile = False
        self._curr_step_profile = False
        self._next_step_profile = False
        self._current_step = -1

    def _identify_continuous_segments(self, sorted_steps: List[int]) -> List[List[int]]:
        """将 steps 分割为连续段。
        例如：[1,2,3,5,6,10] -> [[1,2,3], [5,6], [10]]
        """
        if not sorted_steps:
            return []
        
        segments = []
        current_segment = [sorted_steps[0]]
        
        for step in sorted_steps[1:]:
            if step == current_segment[-1] + 1:
                current_segment.append(step)
            else:
                segments.append(current_segment)
                current_segment = [step]
        
        segments.append(current_segment)
        return segments
    
    def update(self, current_step: int) -> None:
        """更新状态变量"""
        self._current_step = current_step
        self._prev_step_profile = self._curr_step_profile
        self._curr_step_profile = current_step in self.steps if self.steps else False
    
    def should_start(self) -> bool:
        """判断是否应该开始profiling"""
        if self.continuous:
            # 连续模式：只在连续段的第一个 step 开始
            for segment in self._segments:
                if self._curr_step_profile and self._current_step == segment[0]:
                    return True
            return False
        else:
            # 离散模式：每个step独立
            return self._curr_step_profile
    
    def should_stop(self, next_step: int) -> bool:
        """判断是否应该停止profiling"""
        self._next_step_profile = next_step in self.steps if self.steps else False
        if self.continuous:
            # 连续模式：只在连续段的最后一个 step 停止
            for segment in self._segments:
                if self._curr_step_profile and self._current_step == segment[-1]:
                    return True
            return False
        else:
            # 离散模式：如果当前步是profile步，则在步结束时停止
            return self._curr_step_profile


class RLinfProfiler:
    """统一的Profiler管理器，参考verl的DistProfiler设计"""
    
    _instance: Optional["RLinfProfiler"] = None
    
    def __init__(self, config: Dict[str, Any] = None):
        self.config = config or {}
        self._impl: Optional[BaseProfilerImpl] = None
        self._init_impl()
        
        # Initialize metrics collector
        log_dir = self.config.get("save_path", "./profiling")
        # Ensure directory exists only if we are the main process or have a valid path
        if log_dir and not os.path.exists(log_dir):
            try:
                os.makedirs(log_dir, exist_ok=True)
            except OSError:
                pass
        self.profiling_collector = ProfilingMetricsCollector(log_dir) if log_dir else None
        
        RLinfProfiler._instance = self
    
    def _init_impl(self):
        tool = self.config.get("tool", "none")
        if tool == "nvtx":
            self._impl = NVTXProfilerImpl(self.config.get("nvtx", {}))
        elif tool == "torch":
            self._impl = TorchProfilerImpl(self.config.get("torch", {}))
        else:
            self._impl = None  # No-op
    
    def start(self, step: int = -1, **kwargs):
        if self._impl:
            self._impl.start(step, **kwargs)
    
    def stop(self):
        if self._impl:
            self._impl.stop()
    
    def step(self):
        if self._impl:
            self._impl.step()
    
    @classmethod
    def get_instance(cls) -> "RLinfProfiler":
        if cls._instance is None:
            # 如果没有显式初始化，创建一个默认的（禁用状态）
            cls._instance = RLinfProfiler({"tool": "none"})
        return cls._instance



def get_profiling_ctx(name: str, domain: str = None):
    """
    统一上下文工厂：根据当前启用的Profiler返回对应的上下文管理器
    """
    profiler = RLinfProfiler.get_instance()
    if profiler and profiler._impl:
        return profiler._impl.get_profiling_ctx(name, domain)
    return nullcontext()


class profiling_range(ContextDecorator):
    """
    统一的 Profiling 标记类：支持 with 语句和 @ 装饰器（同步/异步）。
    自动处理 NVTX (nsys) 和 record_function (PyTorch Profiler) 模式。
    """
    def __init__(self, name: str, domain: str = "rlinf.runner"):
        self.name = name
        self.domain = domain

    def __enter__(self):
        self._ctx = get_profiling_ctx(self.name, self.domain)
        return self._ctx.__enter__()

    def __exit__(self, exc_type, exc_value, traceback):
        if hasattr(self, "_ctx"):
            self._ctx.__exit__(exc_type, exc_value, traceback)

    def __call__(self, func):
        if asyncio.iscoroutinefunction(func):
            @wraps(func)
            async def wrapper(*args, **kwargs):
                with get_profiling_ctx(self.name, self.domain):
                    return await func(*args, **kwargs)
            return wrapper
        else:
            @wraps(func)
            def wrapper(*args, **kwargs):
                with get_profiling_ctx(self.name, self.domain):
                    return func(*args, **kwargs)
            return wrapper


# 别名，使 with 语句语义更明确
profiling_ctx = profiling_range


def nvtx_mark(message: str, domain: str = "rlinf.runner"):
    """
    发射一个NVTX mark事件
    """
    if not torch.cuda.is_available():
        return

    nvtx_domain = NVTXDomains.get(domain)
    color = DOMAIN_COLORS.get(domain, "white")
    nvtx.mark(message=message, domain=nvtx_domain, color=color)
