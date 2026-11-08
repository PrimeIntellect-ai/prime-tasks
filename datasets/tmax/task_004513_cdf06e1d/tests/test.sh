#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import numpy as np
import pandas as pd

def test_clean_data_exists():
    """Test that the output file exists."""
    assert os.path.exists('/home/user/clean_data.csv'), "The output file /home/user/clean_data.csv is missing."

def test_pipeline_log_exists_and_content():
    """Test that the pipeline log exists and contains required keywords."""
    log_path = '/home/user/pipeline.log'
    assert os.path.exists(log_path), f"{log_path} is missing."

    with open(log_path, 'r') as f:
        content = f.read().upper()

    assert "STARTED" in content, "The log file does not contain 'STARTED'."
    assert "COMPLETED" in content, "The log file does not contain 'COMPLETED'."

def test_cpp_source_exists():
    """Test that the C++ source file exists."""
    assert os.path.exists('/home/user/cleaner.cpp'), "The C++ source file /home/user/cleaner.cpp is missing."

def test_mse_metric_threshold():
    """
    Re-derive the expected cleaned time series from noisy_sensor.csv and
    verify that the agent's output is within the allowed MSE threshold.
    """
    # 1. Read noisy data
    noisy_path = '/app/noisy_sensor.csv'
    assert os.path.exists(noisy_path), f"Input file {noisy_path} is missing."

    noisy_df = pd.read_csv(noisy_path, header=None, names=['timestamp', 'value'])
    timestamps = noisy_df['timestamp'].values
    values = noisy_df['value'].values

    # 2. Re-derive canonical solution
    # Regularize grid
    start_time = int(timestamps[0])
    end_time = int(timestamps[-1])
    reg_timestamps = np.arange(start_time, end_time + 1)

    # Forward fill
    reg_values = np.zeros(len(reg_timestamps))
    idx = 0
    for i, t in enumerate(reg_timestamps):
        while idx < len(timestamps) - 1 and timestamps[idx + 1] <= t:
            idx += 1
        reg_values[i] = values[idx]

    # Rolling mean (Window = 11)
    window = 11
    half_w = window // 2
    n = len(reg_values)
    rolling_means = np.zeros(n)
    for i in range(n):
        start = max(0, i - half_w)
        end = min(n, i + half_w + 1)
        rolling_means[i] = np.mean(reg_values[start:end])

    # EMA (Alpha = 0.25)
    alpha = 0.25
    ema = np.zeros(n)
    ema[0] = rolling_means[0]
    for i in range(1, n):
        ema[i] = alpha * rolling_means[i] + (1 - alpha) * ema[i-1]

    # 3. Read agent's output
    agent_path = '/home/user/clean_data.csv'
    assert os.path.exists(agent_path), f"Agent output {agent_path} is missing."

    agent_df = pd.read_csv(agent_path, header=None, names=['timestamp', 'value'])

    # 4. Compare
    assert len(agent_df) == len(reg_timestamps), \
        f"Expected {len(reg_timestamps)} rows in output, but got {len(agent_df)}."

    agent_values = agent_df['value'].values
    mse = np.mean((agent_values - ema)**2)

    threshold = 0.001
    assert mse <= threshold, \
        f"Verification failed: MSE {mse:.6f} is greater than the threshold {threshold}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
