#!/usr/bin/env python3
"""RLinf Profiling Results Analysis Tool

This script provides utilities to analyze profiling results from:
1. PyTorch Profiler traces
2. Nsight Systems reports
3. Custom profiling metrics
"""

import argparse
import json
import os
import subprocess
import sys
from pathlib import Path


def analyze_pytorch_traces(trace_dir: str):
    """Analyze PyTorch Profiler traces.

    Args:
        trace_dir: Directory containing PyTorch profiler traces
    """
    trace_dir = Path(trace_dir)

    if not trace_dir.exists():
        print(f"Error: Trace directory {trace_dir} does not exist")
        return

    print("=== PyTorch Profiler Analysis ===")
    print(f"Trace directory: {trace_dir}")

    # Find trace files
    trace_files = list(trace_dir.glob("*.pt.trace.json"))
    if not trace_files:
        print("No PyTorch trace files found (.pt.trace.json)")
        print("Make sure PyTorch profiling was enabled during training.")
        return

    print(f"Found {len(trace_files)} trace files:")
    for trace_file in trace_files:
        print(f"  - {trace_file.name}")

    print("\nTo view traces:")
    print(f"  tensorboard --logdir {trace_dir}")
    print("\nFor advanced analysis with Holistic Trace Analysis (HTA):")
    print("  pip install HolisticTraceAnalysis")
    print(f"  hta --trace_dir {trace_dir}")
    print("\nHTA provides:")
    print("  - Critical path analysis")
    print("  - Memory bandwidth analysis")
    print("  - Kernel duration analysis")
    print("  - Communication computation overlap analysis")


def analyze_nsys_report(nsys_file: str):
    """Analyze Nsight Systems report.

    Args:
        nsys_file: Path to .nsys-rep file
    """
    nsys_file = Path(nsys_file)

    if not nsys_file.exists():
        print(f"Error: Nsight Systems file {nsys_file} does not exist")
        return

    print("=== Nsight Systems Analysis ===")
    print(f"Report file: {nsys_file}")

    try:
        # GPU trace summary
        print("\n--- GPU Trace Summary ---")
        result = subprocess.run(
            ["nsys", "stats", "--report", "gputrace", str(nsys_file)],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            # Print only the first 20 lines to avoid overwhelming output
            lines = result.stdout.strip().split('\n')[:20]
            print('\n'.join(lines))
            if len(result.stdout.strip().split('\n')) > 20:
                print("... (truncated, use 'nsys stats --report gputrace <file>' for full output)")
        else:
            print(f"Error running nsys stats: {result.stderr}")

        # OS runtime summary
        print("\n--- OS Runtime Summary ---")
        result = subprocess.run(
            ["nsys", "stats", "--report", "osrt", str(nsys_file)],
            capture_output=True, text=True, timeout=30
        )
        if result.returncode == 0:
            lines = result.stdout.strip().split('\n')[:15]
            print('\n'.join(lines))
            if len(result.stdout.strip().split('\n')) > 15:
                print("... (truncated)")
        else:
            print(f"Error running nsys stats: {result.stderr}")

        print("\nTo view full report in Nsight Systems GUI:")
        print(f"  nsys-ui {nsys_file}")

        print("\nTo get all available reports:")
        print(f"  nsys stats --list {nsys_file}")

    except FileNotFoundError:
        print("Error: nsys command not found. Make sure Nsight Systems is installed.")
        print("Installation: https://developer.nvidia.com/nsight-systems")
    except subprocess.TimeoutExpired:
        print("Warning: nsys stats timed out. The report might be very large.")


def analyze_custom_metrics(metrics_file: str):
    """Analyze custom profiling metrics.

    Args:
        metrics_file: Path to profiling_metrics.json file
    """
    metrics_file = Path(metrics_file)

    if not metrics_file.exists():
        print(f"Error: Metrics file {metrics_file} does not exist")
        return

    print("=== Custom Profiling Metrics Analysis ===")
    print(f"Metrics file: {metrics_file}")

    try:
        with open(metrics_file, 'r') as f:
            data = json.load(f)

        summary = data.get('summary', {})
        if not summary:
            print("No summary data found")
            return

        print("\n--- Timing Statistics ---")
        timing_keys = [k for k in summary.keys() if k.endswith('_time') or k in ['sync_weights', 'generate_rollouts', 'cal_adv_and_returns', 'actor_training']]
        for key in sorted(timing_keys):
            stats = summary[key]
            print("12")

        print("\n--- Rollout Dynamics ---")
        rollout_keys = [k for k in summary.keys() if 'rollout' in k.lower()]
        for key in sorted(rollout_keys):
            stats = summary[key]
            print("12")

        step_metrics = data.get('step_metrics', [])
        if step_metrics:
            print(f"\n--- Step Details ---")
            print(f"Total steps recorded: {len(step_metrics)}")
            if step_metrics:
                latest_step = step_metrics[-1]
                print(f"Latest step ({latest_step.get('step', 'N/A')}):")
                for k, v in latest_step.items():
                    if k != 'step' and isinstance(v, (int, float)):
                        print(".4f")

    except json.JSONDecodeError as e:
        print(f"Error parsing metrics file: {e}")
    except Exception as e:
        print(f"Error analyzing metrics: {e}")


def find_profiling_files(base_dir: str):
    """Find profiling files in a directory.

    Args:
        base_dir: Base directory to search

    Returns:
        Dictionary with paths to different profiling files
    """
    base_dir = Path(base_dir)

    files = {
        'pytorch_traces': None,
        'nsys_report': None,
        'custom_metrics': None
    }

    # Find PyTorch traces directory
    profiling_dir = base_dir / "profiling"
    if profiling_dir.exists():
        files['pytorch_traces'] = str(profiling_dir)

    # Find Nsight Systems report
    nsys_files = list(base_dir.glob("*.nsys-rep"))
    if nsys_files:
        files['nsys_report'] = str(nsys_files[0])

    # Find custom metrics
    if profiling_dir.exists():
        metrics_file = profiling_dir / "profiling_metrics.json"
        if metrics_file.exists():
            files['custom_metrics'] = str(metrics_file)

    return files


def main():
    parser = argparse.ArgumentParser(description="Analyze RLinf profiling results")
    parser.add_argument(
        "input_dir",
        help="Directory containing profiling results (or path to specific file)"
    )
    parser.add_argument(
        "--type",
        choices=["auto", "pytorch", "nsys", "metrics"],
        default="auto",
        help="Type of analysis to perform (default: auto-detect)"
    )

    args = parser.parse_args()

    input_path = Path(args.input_dir)

    if args.type == "auto":
        # Auto-detect file types
        if input_path.is_file():
            if input_path.suffix == ".nsys-rep":
                analyze_nsys_report(str(input_path))
            elif input_path.name == "profiling_metrics.json":
                analyze_custom_metrics(str(input_path))
            else:
                print(f"Unknown file type: {input_path}")
        else:
            # Directory mode - find all profiling files
            files = find_profiling_files(str(input_path))

            if files['pytorch_traces']:
                analyze_pytorch_traces(files['pytorch_traces'])
                print()

            if files['nsys_report']:
                analyze_nsys_report(files['nsys_report'])
                print()

            if files['custom_metrics']:
                analyze_custom_metrics(files['custom_metrics'])
                print()

            if not any(files.values()):
                print("No profiling files found in directory.")
                print("Make sure profiling was enabled during training.")

    elif args.type == "pytorch":
        analyze_pytorch_traces(args.input_dir)
    elif args.type == "nsys":
        analyze_nsys_report(args.input_dir)
    elif args.type == "metrics":
        analyze_custom_metrics(args.input_dir)


if __name__ == "__main__":
    main()

