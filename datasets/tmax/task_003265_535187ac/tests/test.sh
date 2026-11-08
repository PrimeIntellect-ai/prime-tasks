#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import pytest
import pandas as pd

def test_uptime_report_accuracy():
    agent_report_path = "/home/user/uptime_report.csv"
    golden_report_path = "/tests/golden_uptime_report.csv"

    assert os.path.exists(agent_report_path), f"Agent report not found at {agent_report_path}"
    assert os.path.exists(golden_report_path), f"Golden report not found at {golden_report_path}"

    try:
        agent_df = pd.read_csv(agent_report_path)
    except Exception as e:
        pytest.fail(f"Failed to read agent report CSV: {e}")

    try:
        golden_df = pd.read_csv(golden_report_path)
    except Exception as e:
        pytest.fail(f"Failed to read golden report CSV: {e}")

    assert len(golden_df) > 0, "Golden report is empty, cannot verify."

    if len(agent_df) == 0:
        pytest.fail("Agent report is empty. Accuracy: 0.0, Expected: >= 0.98")

    expected_cols = ['Date', 'Total_Uptime_Seconds', 'Downtime_Events']
    for col in expected_cols:
        assert col in agent_df.columns, f"Missing expected column '{col}' in agent report."

    merged = pd.merge(agent_df, golden_df, on='Date', how='inner', suffixes=('_agent', '_golden'))

    correct = 0
    for _, row in merged.iterrows():
        if (row['Total_Uptime_Seconds_agent'] == row['Total_Uptime_Seconds_golden'] and
                row['Downtime_Events_agent'] == row['Downtime_Events_golden']):
            correct += 1

    accuracy = correct / len(golden_df)
    assert accuracy >= 0.98, f"Row-by-row accuracy is {accuracy:.4f}, which is below the threshold of 0.98."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
