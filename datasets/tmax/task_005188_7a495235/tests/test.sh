#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import pytest
import pandas as pd
import numpy as np


def test_smoothed_tracking_csv():
    """Verify that the smoothed tracking CSV exists, is complete, and meets the MSE threshold."""
    agent_csv_path = "/home/user/smoothed_tracking.csv"
    gt_csv_path = "/tests/ground_truth.csv"

    assert os.path.exists(agent_csv_path), f"Agent output file is missing at {agent_csv_path}"
    assert os.path.isfile(agent_csv_path), f"Path {agent_csv_path} is not a file"
    assert os.path.exists(gt_csv_path), f"Ground-truth file is missing at {gt_csv_path}"

    agent_df = pd.read_csv(agent_csv_path)
    gt_df = pd.read_csv(gt_csv_path)

    assert list(agent_df.columns) == ['frame', 'x', 'y'], "Agent CSV header must be exactly 'frame,x,y'"
    assert 'x' in agent_df.columns and 'y' in agent_df.columns, "Agent CSV must contain 'x' and 'y' columns"
    assert len(agent_df) == len(gt_df), f"Expected {len(gt_df)} trajectory rows, got {len(agent_df)}"

    min_len = min(len(agent_df), len(gt_df))
    assert min_len > 0, "Agent CSV is empty"

    agent_df_trunc = agent_df.iloc[:min_len]
    gt_df_trunc = gt_df.iloc[:min_len]

    assert np.array_equal(agent_df_trunc['frame'].to_numpy(), np.arange(min_len)), "Frame indices must start at 0 and be consecutive"
    assert np.isfinite(agent_df_trunc[['x', 'y']].to_numpy(dtype=float)).all(), "Trajectory coordinates must be finite numbers"

    mse_x = np.mean((agent_df_trunc['x'].values - gt_df_trunc['x'].values) ** 2)
    mse_y = np.mean((agent_df_trunc['y'].values - gt_df_trunc['y'].values) ** 2)
    total_mse = mse_x + mse_y

    assert total_mse <= 10.0, f"MSE {total_mse} is greater than the threshold of 10.0"


def test_experiment_log_json():
    """Verify that the experiment log JSON exists and contains the correct data."""
    log_path = "/home/user/experiment_log.json"
    agent_csv_path = "/home/user/smoothed_tracking.csv"

    assert os.path.exists(log_path), f"Experiment log is missing at {log_path}"
    assert os.path.isfile(log_path), f"Path {log_path} is not a file"

    with open(log_path, 'r') as f:
        try:
            log_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("Experiment log is not valid JSON")

    assert "run_name" in log_data, "Experiment log missing 'run_name'"
    assert log_data["run_name"] == "physics_01", f"Expected run_name to be 'physics_01', got '{log_data['run_name']}'"

    assert "model" in log_data, "Experiment log missing 'model'"

    assert "num_frames" in log_data, "Experiment log missing 'num_frames'"

    if os.path.exists(agent_csv_path):
        agent_df = pd.read_csv(agent_csv_path)
        expected_frames = len(agent_df)
        assert log_data["num_frames"] == expected_frames, f"Expected num_frames to be {expected_frames}, got {log_data['num_frames']}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
