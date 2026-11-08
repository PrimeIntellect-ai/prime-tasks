#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import pytest

def test_compliance_report_accuracy():
    report_path = '/home/user/compliance_report.csv'
    assert os.path.exists(report_path), f"Report file not found at {report_path}"

    try:
        agent_df = pd.read_csv(report_path)
    except Exception as e:
        pytest.fail(f"Failed to read {report_path} as CSV: {e}")

    # Re-derive expected data
    expected_data = [
        {'tx_id': 1, 'root_tx_id': 1, 'department_id': 1, 'running_total': 1000},
        {'tx_id': 2, 'root_tx_id': 1, 'department_id': 1, 'running_total': 2500},
        {'tx_id': 4, 'root_tx_id': 1, 'department_id': 1, 'running_total': 5500},
        {'tx_id': 3, 'root_tx_id': 3, 'department_id': 2, 'running_total': 2000},
        {'tx_id': 5, 'root_tx_id': 3, 'department_id': 2, 'running_total': 6000}
    ]

    # Calculate expected risk scores using the exact algorithm
    for row in expected_data:
        amt = row['running_total']
        score = (amt * 137 % 1000) / 1000.0
        if amt > 5000:
            score += 0.5
        row['risk_score'] = round(score, 3)

    expected_df = pd.DataFrame(expected_data)

    assert len(agent_df) == len(expected_df), f"Expected {len(expected_df)} rows, but got {len(agent_df)}."

    matches = 0
    for i in range(len(expected_df)):
        try:
            if (int(agent_df.iloc[i]['tx_id']) == expected_df.iloc[i]['tx_id'] and
                int(agent_df.iloc[i]['root_tx_id']) == expected_df.iloc[i]['root_tx_id'] and
                int(agent_df.iloc[i]['department_id']) == expected_df.iloc[i]['department_id'] and
                int(agent_df.iloc[i]['running_total']) == expected_df.iloc[i]['running_total'] and
                abs(float(agent_df.iloc[i]['risk_score']) - expected_df.iloc[i]['risk_score']) < 0.01):
                matches += 1
        except KeyError as e:
            pytest.fail(f"Missing expected column in CSV: {e}")
        except ValueError as e:
            pytest.fail(f"Invalid data type in CSV at row {i}: {e}")

    accuracy = matches / len(expected_df)
    assert accuracy >= 1.0, f"Accuracy is {accuracy}, expected >= 1.0. {matches} out of {len(expected_df)} rows matched exactly."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
