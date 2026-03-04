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

"""Profiling metrics collector for RLinf."""

import json
import os
from collections import defaultdict
from typing import Any, Dict, List


class ProfilingMetricsCollector:
    """收集profiling metrics，支持在线统计和离线存储。

    主要功能：
    - 在线聚合统计（mean/min/max/count）
    - 可选存储最近N个step的详细数据（默认100）
    - 输出JSON格式的summary
    """

    def __init__(self, log_dir: str, store_distribution: bool = True, max_steps: int = 100):
        """初始化metrics收集器。

        Args:
            log_dir: 日志目录
            store_distribution: 是否存储详细分布数据
            max_steps: 最多存储的step数量（仅在store_distribution=True时生效）
        """
        self.log_dir = log_dir
        self.store_distribution = store_distribution
        self.max_steps = max_steps
        self.step_metrics: List[Dict[str, Any]] = []
        self.aggregated_stats = defaultdict(list)

    def record_step(self, step_id: int, metrics: Dict[str, Any]) -> None:
        """记录单个step的metrics。

        Args:
            step_id: 训练step ID
            metrics: metrics字典
        """
        step_data = {'step': step_id, **metrics}
        self.step_metrics.append(step_data)

        # 在线聚合统计（减少存储）
        for key, value in metrics.items():
            if isinstance(value, (int, float)):
                self.aggregated_stats[key].append(value)

        # 限制存储的step数量
        if self.store_distribution and len(self.step_metrics) > self.max_steps:
            self.step_metrics.pop(0)

    def get_summary(self) -> Dict[str, Any]:
        """获取统计摘要。

        Returns:
            包含统计摘要的字典
        """
        summary = {}
        for key, values in self.aggregated_stats.items():
            if values:
                summary[key] = {
                    'mean': sum(values) / len(values),
                    'min': min(values),
                    'max': max(values),
                    'count': len(values),
                    'sum': sum(values)
                }
            else:
                summary[key] = {
                    'mean': 0.0,
                    'min': 0.0,
                    'max': 0.0,
                    'count': 0,
                    'sum': 0.0
                }
        return summary

    def save(self, filename: str = "profiling_metrics.json") -> None:
        """保存metrics到文件。

        Args:
            filename: 输出文件名
        """
        output = {
            'summary': self.get_summary()
        }

        if self.store_distribution:
            output['step_metrics'] = self.step_metrics[-self.max_steps:]  # 只保存最近的N个

        filepath = os.path.join(self.log_dir, filename)
        with open(filepath, 'w', encoding='utf-8') as f:
            json.dump(output, f, indent=2, ensure_ascii=False)

        print(f"Profiling metrics saved to: {filepath}")

    def reset(self) -> None:
        """重置收集器状态。"""
        self.step_metrics.clear()
        self.aggregated_stats.clear()


