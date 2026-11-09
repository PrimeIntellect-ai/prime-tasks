#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import math
import pandas as pd
import numpy as np

def test_smoothed_cpu_output():
    agent_file = '/home/user/smoothed_cpu.csv'

    # 1. Check if the output file exists
    assert os.path.exists(agent_file), f"Agent output file not found at {agent_file}"
    assert os.path.isfile(agent_file), f"Path {agent_file} is not a file"

    # 2. Load the data
    try:
        df_agent = pd.read_csv(agent_file)
    except Exception as e:
        raise AssertionError(f"Failed to read agent CSV file: {e}")

    # Reconstruct the deterministic hidden ground truth at verification time.
    np.random.seed(42)
    ground_truth_cpu = []
    for sec in range(1, 61):
        cpu_val = 40.0 + 20 * math.sin(sec / 5.0) + np.random.normal(0, 2.0)
        ground_truth_cpu.append(round(cpu_val, 1))

    df_gt = pd.DataFrame({'second': range(1, 61), 'cpu': ground_truth_cpu})
    df_gt['smoothed_cpu_gt'] = df_gt['cpu'].rolling(window=5, min_periods=1).mean()

    # 3. Check for required columns
    assert 'second' in df_agent.columns, "Column 'second' missing in agent CSV"
    assert 'smoothed_cpu' in df_agent.columns, "Column 'smoothed_cpu' missing in agent CSV"

    # 4. Sort and align by 'second'
    df_agent = df_agent.sort_values('second').reset_index(drop=True)
    df_gt = df_gt.sort_values('second').reset_index(drop=True)

    # 5. Truncate to the shortest length and check minimum length
    min_len = min(len(df_agent), len(df_gt))
    assert min_len >= 50, f"Too many missing frames. Found {min_len}/60. Expected at least 50."

    # 6. Compute MSE
    agent_values = df_agent['smoothed_cpu'][:min_len].values
    gt_values = df_gt['smoothed_cpu_gt'][:min_len].values

    mse = np.mean((agent_values - gt_values)**2)

    # 7. Assert MSE is within threshold
    threshold = 2.0
    assert mse <= threshold, f"MSE is {mse:.4f}, which is greater than the threshold of {threshold}. The OCR parsing or rolling average calculation might be inaccurate."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
