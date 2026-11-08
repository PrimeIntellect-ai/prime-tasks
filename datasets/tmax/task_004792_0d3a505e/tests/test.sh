#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import numpy as np
import pytest

def test_output_csv_exists():
    agent_file = '/home/user/station_averages.csv'
    assert os.path.isfile(agent_file), f"Output file {agent_file} does not exist."

def test_mae_metric():
    agent_file = '/home/user/station_averages.csv'
    truth_file = '/tests/ground_truth_averages.csv'

    assert os.path.isfile(agent_file), f"Output file {agent_file} does not exist."
    assert os.path.isfile(truth_file), f"Ground truth file {truth_file} missing."

    try:
        agent_df = pd.read_csv(agent_file)
    except Exception as e:
        pytest.fail(f"Failed to read {agent_file} as a CSV: {e}")

    try:
        truth_df = pd.read_csv(truth_file)
    except Exception as e:
        pytest.fail(f"Failed to read {truth_file} as a CSV: {e}")

    # Check columns
    expected_columns = ['StationID', 'AvgTemp', 'AvgHumid']
    assert list(agent_df.columns) == expected_columns, f"Expected columns {expected_columns}, got {list(agent_df.columns)}"

    # Sort and reset index to ensure alignment
    agent_df = agent_df.sort_values('StationID').reset_index(drop=True)
    truth_df = truth_df.sort_values('StationID').reset_index(drop=True)

    # Ensure station IDs match exactly
    assert np.array_equal(agent_df['StationID'].values, truth_df['StationID'].values), \
        f"Station IDs do not match. Expected {truth_df['StationID'].values}, got {agent_df['StationID'].values}."

    # Calculate MAE
    mae_temp = np.abs(agent_df['AvgTemp'] - truth_df['AvgTemp']).mean()
    mae_humid = np.abs(agent_df['AvgHumid'] - truth_df['AvgHumid']).mean()
    total_mae = (mae_temp + mae_humid) / 2.0

    # Assert threshold
    assert total_mae <= 0.05, f"Total MAE {total_mae:.4f} exceeds threshold of 0.05. (Temp MAE: {mae_temp:.4f}, Humid MAE: {mae_humid:.4f})"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
