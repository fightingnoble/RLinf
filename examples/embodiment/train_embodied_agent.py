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

import json
import os
import yaml

import hydra
import torch.multiprocessing as mp
from omegaconf.omegaconf import OmegaConf

from rlinf.config import validate_cfg
from rlinf.runners.embodied_runner import EmbodiedRunner
from rlinf.scheduler import Cluster
from rlinf.utils.placement import HybridComponentPlacement
from rlinf.workers.actor.fsdp_actor_worker import EmbodiedFSDPActor
from rlinf.workers.env.env_worker import EnvWorker
from rlinf.workers.rollout.hf.huggingface_worker import MultiStepRolloutWorker

mp.set_start_method("spawn", force=True)


@hydra.main(
    version_base="1.1", config_path="config", config_name="maniskill_ppo_openvlaoft"
)
def main(cfg) -> None:
    cfg = validate_cfg(cfg)
    print(json.dumps(OmegaConf.to_container(cfg, resolve=True), indent=2))

    cluster = Cluster(cluster_cfg=cfg.cluster)
    component_placement = HybridComponentPlacement(cfg, cluster)

    # Load profiling configuration
    profiling_cfg = {}
    profiling_config_path = cfg.runner.get("profiling_config", None)
    if profiling_config_path and os.path.exists(profiling_config_path):
        with open(profiling_config_path, "r") as f:
            profiling_cfg = yaml.safe_load(f).get("profiling", {})

    nsight_options = None
    if profiling_cfg.get("tool") == "nvtx":
        nsight_options = profiling_cfg.get("nsight", {}).get("worker_nsight_options")
        
        # Preprocess nsight_options: filter out None values to avoid Ray conversion issues
        # Ray's Nsight plugin converts Python None to string "None", which nsys doesn't recognize
        if nsight_options:
            nsight_options = {k: v for k, v in nsight_options.items() if v is not None}
            
            # Auto-calculate capture-range-end if not specified (following verl's approach)
            # This ensures torch.cuda.profiler.start/stop pairs can repeat properly
            if "capture-range-end" not in nsight_options:
                profile_steps = profiling_cfg.get("steps", [])
                if profile_steps:
                    # Default: 6x the number of profile steps (covers all sub-tasks)
                    nsight_options["capture-range-end"] = f"repeat-shutdown:{6 * len(profile_steps)}"

    # Minimal startup observability: show profiling decisions early (helps diagnose "stuck"/no-capture)
    try:
        tool = profiling_cfg.get("tool", "none")
        steps = profiling_cfg.get("steps", [])
        continuous = profiling_cfg.get("continuous", False)
        print(
            f"[Profiling] tool={tool} steps={steps} continuous={continuous} "
            f"worker_nsight_options={'set' if bool(nsight_options) else 'none'}",
            flush=True,
        )
    except Exception:
        # Never let debug printing break training.
        pass

    # Create actor worker group
    actor_placement = component_placement.get_strategy("actor")
    actor_group = EmbodiedFSDPActor.create_group(cfg)
    if nsight_options:
        actor_group.with_nsight(nsight_options)
    actor_group = actor_group.launch(
        cluster, name=cfg.actor.group_name, placement_strategy=actor_placement
    )
    # Create rollout worker group
    rollout_placement = component_placement.get_strategy("rollout")
    rollout_group = MultiStepRolloutWorker.create_group(cfg)
    if nsight_options:
        rollout_group.with_nsight(nsight_options)
    rollout_group = rollout_group.launch(
        cluster, name=cfg.rollout.group_name, placement_strategy=rollout_placement
    )
    # Create env worker group
    env_placement = component_placement.get_strategy("env")
    env_group = EnvWorker.create_group(cfg)
    if nsight_options:
        env_group.with_nsight(nsight_options)
    env_group = env_group.launch(
        cluster, name=cfg.env.group_name, placement_strategy=env_placement
    )

    runner = EmbodiedRunner(
        cfg=cfg,
        actor=actor_group,
        rollout=rollout_group,
        env=env_group,
    )

    runner.init_workers()
    runner.run()


if __name__ == "__main__":
    main()
