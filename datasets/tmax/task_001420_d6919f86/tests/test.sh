#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pandas as pd
import numpy as np
import pytest


def test_output_file_exists():
    """Check if the agent generated the output file."""
    output_path = "/home/user/output.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."


def test_output_format_and_metric():
    """Check output format, record identities, and computed metrics."""
    output_path = "/home/user/output.csv"
    golden_path = "/tests/golden_output.csv"

    assert os.path.isfile(golden_path), f"Golden output file {golden_path} is missing. Test setup error."

    try:
        agent_df = pd.read_csv(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read {output_path} as CSV: {e}")

    try:
        golden_df = pd.read_csv(golden_path)
    except Exception as e:
        pytest.fail(f"Failed to read {golden_path} as CSV: {e}")

    expected_cols = ['timestamp', 'sensor_id', 'scaled_rolling_avg']
    for col in expected_cols:
        assert col in agent_df.columns, f"Missing expected column '{col}' in output.csv"

    agent_df = agent_df.sort_values(['timestamp', 'sensor_id']).reset_index(drop=True)
    golden_df = golden_df.sort_values(['timestamp', 'sensor_id']).reset_index(drop=True)

    assert len(agent_df) == len(golden_df), (
        f"Row count mismatch: expected {len(golden_df)} rows, but got {len(agent_df)} rows."
    )

    agent_ts = pd.to_numeric(agent_df['timestamp'], errors='coerce')
    golden_ts = pd.to_numeric(golden_df['timestamp'], errors='coerce')
    assert agent_ts.notna().all(), "Output contains invalid timestamps."
    assert agent_ts.tolist() == golden_ts.tolist(), "Submitted timestamps do not match the expected records."

    agent_ids = agent_df['sensor_id'].astype(str).tolist()
    golden_ids = golden_df['sensor_id'].astype(str).tolist()
    assert agent_ids == golden_ids, "Submitted sensor IDs do not match the expected records."

    agent_vals = pd.to_numeric(agent_df['scaled_rolling_avg'], errors='coerce').fillna(0.0)
    golden_vals = pd.to_numeric(golden_df['scaled_rolling_avg'], errors='coerce').fillna(0.0)

    mse = np.mean((agent_vals - golden_vals) ** 2)
    threshold = 0.05

    assert mse <= threshold, (
        f"MSE {mse:.4f} exceeds threshold of {threshold}. "
        "The computed scaled rolling averages differ too much from the expected values."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
