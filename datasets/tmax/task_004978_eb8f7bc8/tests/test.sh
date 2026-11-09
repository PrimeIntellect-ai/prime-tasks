#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
from collections import defaultdict

def test_bottleneck_computation():
    trace_log_path = "/home/user/trace.log"
    bottleneck_txt_path = "/home/user/bottleneck.txt"

    assert os.path.isfile(trace_log_path), f"Trace log {trace_log_path} is missing."
    assert os.path.isfile(bottleneck_txt_path), f"Result file {bottleneck_txt_path} is missing."

    mcmc_durations = defaultdict(int)
    mesh_refine_durations = defaultdict(list)

    with open(trace_log_path, "r") as f:
        for line in f:
            parts = line.strip().split()
            if len(parts) != 4:
                continue
            timestamp, module, rank, duration = parts
            rank = int(rank)
            duration = int(duration)

            if module == "MCMC_SAMPLER":
                mcmc_durations[rank] += duration
            elif module == "MESH_REFINE":
                mesh_refine_durations[rank].append(duration)

    assert mcmc_durations, "No MCMC_SAMPLER entries found in trace.log."

    # Identify the target rank
    target_rank = max(mcmc_durations.items(), key=lambda x: x[1])[0]

    # Calculate average MESH_REFINE duration for the target rank
    durations = mesh_refine_durations[target_rank]
    if durations:
        avg_duration = sum(durations) / len(durations)
    else:
        avg_duration = 0.0

    expected_output = f"Target Rank: {target_rank}\nAverage MESH_REFINE Duration: {avg_duration:.2f}"

    with open(bottleneck_txt_path, "r") as f:
        actual_output = f.read().strip()

    assert actual_output == expected_output, (
        f"Contents of {bottleneck_txt_path} are incorrect.\n"
        f"Expected:\n{expected_output}\n\n"
        f"Actual:\n{actual_output}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
