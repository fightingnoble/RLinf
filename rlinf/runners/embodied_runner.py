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
import yaml

from omegaconf.dictconfig import DictConfig
from tqdm import tqdm
import torch

from rlinf.utils.distributed import ScopedTimer
from rlinf.utils.metric_logger import MetricLogger
from rlinf.utils.metric_utils import compute_evaluate_metrics
from rlinf.utils.profiler_utils import RLinfProfiler, StepController, profiling_range
from rlinf.utils.runner_utils import check_progress
from rlinf.workers.actor.fsdp_actor_worker import EmbodiedFSDPActor
from rlinf.workers.env.env_worker import EnvWorker
from rlinf.workers.rollout.hf.huggingface_worker import MultiStepRolloutWorker


class EmbodiedRunner:
    def __init__(
        self,
        cfg: DictConfig,
        actor: EmbodiedFSDPActor,
        rollout: MultiStepRolloutWorker,
        env: EnvWorker,
        critic=None,
        reward=None,
        run_timer=None,
    ):
        self.cfg = cfg
        self.actor = actor
        self.rollout = rollout
        self.env = env
        self.critic = critic
        self.reward = reward

        # this timer checks if we should stop training
        self.run_timer = run_timer

        self.consumed_samples = 0
        # the step here is GRPO step
        self.global_step = 0

        # compute `max_steps`
        self.set_max_steps()

        self.timer = ScopedTimer(reduction="max", sync_cuda=False)

        self.metric_logger = MetricLogger(cfg)

        # Load profiling config
        profiling_config_path = cfg.runner.get("profiling_config", None)
        profiling_cfg_dict = {}
        if profiling_config_path and os.path.exists(profiling_config_path):
            with open(profiling_config_path, "r") as f:
                full_cfg = yaml.safe_load(f)
                profiling_cfg_dict = full_cfg.get("profiling", {})
        
        # Initialize profiler and step controller
        self.profiler = RLinfProfiler(profiling_cfg_dict)
        self.step_controller = StepController(
            steps=profiling_cfg_dict.get("steps", []),
            continuous=profiling_cfg_dict.get("continuous", False)
        )

    def init_workers(self):
        # create worker in order to decrease the maximum memory usage
        self.actor.init_worker().wait()
        self.rollout.init_worker().wait()
        self.env.init_worker().wait()

        resume_dir = self.cfg.runner.get("resume_dir", None)
        if resume_dir is None:
            return

        actor_checkpoint_path = os.path.join(resume_dir, "actor")
        assert os.path.exists(actor_checkpoint_path), (
            f"resume_dir {actor_checkpoint_path} does not exist."
        )
        self.actor.load_checkpoint(actor_checkpoint_path).wait()
        self.global_step = int(resume_dir.split("global_step_")[-1])

    def update_rollout_weights(self):
        rollout_futures = self.rollout.sync_model_from_actor()
        actor_futures = self.actor.sync_model_to_rollout()
        actor_futures.wait()
        rollout_futures.wait()

    def generate_rollouts(self):
        env_futures = self.env.interact()
        rollout_futures = self.rollout.generate()
        actor_futures = self.actor.recv_rollout_batch()
        env_results = env_futures.wait()
        actor_futures.wait()
        rollout_futures.wait()

        env_results_list = [results for results in env_results if results is not None]
        env_metrics = compute_evaluate_metrics(env_results_list)

        # Extract rollout dynamics statistics from env_results
        # Only store scalar values for TensorBoard compatibility
        episodes_per_rollout = []
        steps_per_episode = []
        total_steps = 0

        for result in env_results_list:
            # result is a dict[str, torch.Tensor] containing episode metrics like 'r' and 'l'
            # (from EnvWorker.interact() -> env_metrics)
            
            # Count episodes (episodes that ended/completed)
            if 'r' in result:  # rewards indicate episode completion
                episode_count = len(result['r'])
                episodes_per_rollout.append(episode_count)

            # Count steps per episode if available
            if 'l' in result:  # episode lengths
                episode_lengths = result['l'].tolist()
                steps_per_episode.extend(episode_lengths)
                total_steps += sum(episode_lengths)

        # Convert lists to scalar metrics for TensorBoard
        if episodes_per_rollout:
            env_metrics['rollout_stats/episodes_per_rollout_mean'] = sum(episodes_per_rollout) / len(episodes_per_rollout)
            env_metrics['rollout_stats/episodes_per_rollout_max'] = max(episodes_per_rollout)
            env_metrics['rollout_stats/episodes_per_rollout_min'] = min(episodes_per_rollout)
        if steps_per_episode:
            env_metrics['rollout_stats/steps_per_episode_mean'] = sum(steps_per_episode) / len(steps_per_episode)
            env_metrics['rollout_stats/steps_per_episode_max'] = max(steps_per_episode)
            env_metrics['rollout_stats/steps_per_episode_min'] = min(steps_per_episode)
        env_metrics['rollout_stats/total_steps'] = total_steps

        return env_metrics

    def evaluate(self):
        env_futures = self.env.evaluate()
        rollout_futures = self.rollout.evaluate()
        env_results = env_futures.wait()
        rollout_futures.wait()
        eval_metrics_list = [results for results in env_results if results is not None]
        eval_metrics = compute_evaluate_metrics(eval_metrics_list)
        return eval_metrics

    def run(self):
        """启动训练，包装profiling上下文"""
        with profiling_range("training_loop", domain="rlinf.runner"):
            self._run_training_loop()

    def _run_training_loop(self):
        """实际的训练循环逻辑"""
        start_step = self.global_step
        global_pbar = tqdm(
            initial=start_step,
            total=self.max_steps,
            desc="Global Step",
            ncols=800,
        )
        for _step in range(start_step, self.max_steps):
            self.step_controller.update(self.global_step)

            if self.step_controller.should_start():
                # Minimal observability: confirm when cudaProfilerApi capture is armed
                # (useful when nsys uses --capture-range=cudaProfilerApi)
                try:
                    print(f"[Profiling] START step={self.global_step}", flush=True)
                except Exception:
                    pass
                self.profiler.start(step=self.global_step)

            # set global step
            self.actor.set_global_step(self.global_step)
            self.rollout.set_global_step(self.global_step)
            eval_metrics = {}
            if (
                _step % self.cfg.runner.val_check_interval == 0
                and self.cfg.runner.val_check_interval > 0
            ):
                with self.timer("eval"):
                    self.update_rollout_weights()
                    eval_metrics = self.evaluate()
                    eval_metrics = {f"eval/{k}": v for k, v in eval_metrics.items()}
                    self.metric_logger.log(data=eval_metrics, step=_step)

            with self.timer("step"):
                with self.timer("sync_weights"):
                    self.update_rollout_weights()
                with self.timer("generate_rollouts"):
                    env_metrics = self.generate_rollouts()

                # compute advantages and returns.
                with self.timer("cal_adv_and_returns"):
                    actor_futures = self.actor.compute_advantages_and_returns()
                    actor_rollout_metrics = actor_futures.wait()

                # actor training.
                with self.timer("actor_training"):
                    actor_training_futures = self.actor.run_training()
                    actor_training_metrics = actor_training_futures.wait()

                self.global_step += 1

                run_val, save_model, is_train_end = check_progress(
                    self.global_step,
                    self.max_steps,
                    self.cfg.runner.val_check_interval,
                    self.cfg.runner.save_interval,
                    1.0,
                    run_time_exceeded=False,
                )

                if save_model:
                    self._save_checkpoint()

            if self.step_controller.should_stop(self.global_step + 1):
                self.profiler.stop()
                try:
                    print(f"[Profiling] STOP step={self.global_step}", flush=True)
                except Exception:
                    pass

            time_metrics = self.timer.consume_durations()

            time_metrics = {f"time/{k}": v for k, v in time_metrics.items()}
            rollout_metrics = {
                f"rollout/{k}": v for k, v in actor_rollout_metrics[0].items()
            }
            env_metrics = {f"env/{k}": v for k, v in env_metrics.items()}
            time_metrics = {f"time/{k}": v for k, v in time_metrics.items()}
            training_metrics = {
                f"train/{k}": v for k, v in actor_training_metrics[0].items()
            }
            self.metric_logger.log(env_metrics, _step)
            self.metric_logger.log(rollout_metrics, _step)
            self.metric_logger.log(time_metrics, _step)
            self.metric_logger.log(training_metrics, _step)

            logging_metrics = time_metrics
            logging_metrics.update(eval_metrics)
            logging_metrics.update(env_metrics)
            logging_metrics.update(rollout_metrics)
            logging_metrics.update(training_metrics)

            global_pbar.set_postfix(logging_metrics, refresh=False)
            global_pbar.update(1)

            self.profiler.step()

            # Record profiling metrics for this step
            if self.profiler.profiling_collector is not None:
                step_metrics = {}
                # Add timing metrics
                for k, v in time_metrics.items():
                    step_metrics[k.replace("time/", "")] = v

                # Add env metrics (flatten rollout_stats)
                if "rollout_stats/total_steps" in env_metrics:
                    step_metrics["rollout_total_steps"] = env_metrics[
                        "rollout_stats/total_steps"
                    ]
                if "rollout_stats/episodes_per_rollout" in env_metrics:
                    episodes_list = env_metrics["rollout_stats/episodes_per_rollout"]
                    if episodes_list:
                        step_metrics["rollout_episodes_count"] = len(episodes_list)
                        step_metrics["rollout_episodes_mean"] = sum(
                            episodes_list
                        ) / len(episodes_list)

                    self.profiler.profiling_collector.record_step(_step, step_metrics)

        # Save profiling metrics summary
        if self.profiler.profiling_collector is not None:
            self.profiler.profiling_collector.save()

        self.metric_logger.finish()

    def _save_checkpoint(self):
        base_output_dir = os.path.join(
            self.cfg.runner.logger.log_path,
            self.cfg.runner.logger.experiment_name,
            f"checkpoints/global_step_{self.global_step}",
        )
        actor_save_path = os.path.join(base_output_dir, "actor")
        os.makedirs(actor_save_path, exist_ok=True)
        self.actor.save_checkpoint(actor_save_path).wait()

    def set_max_steps(self):
        self.num_steps_per_epoch = 1
        self.max_steps = self.num_steps_per_epoch * self.cfg.runner.max_epochs

        if (max_steps := self.cfg.runner.get("max_steps", -1)) >= 0:
            self.max_steps = min(self.max_steps, max_steps)

    @property
    def epoch(self):
        return self.global_step // self.num_steps_per_epoch
