#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import pytest

def test_correct_totals_mae():
    """Test that the submission file exists, is formatted correctly, and has an MAE < 0.01 compared to ground truth."""
    submission_path = '/home/user/correct_totals.csv'
    ground_truth_path = '/tests/ground_truth.csv'

    assert os.path.isfile(submission_path), f"Submission file {submission_path} does not exist."
    assert os.path.isfile(ground_truth_path), f"Ground truth file {ground_truth_path} does not exist."

    try:
        sub = pd.read_csv(submission_path)
    except Exception as e:
        pytest.fail(f"Could not read {submission_path} as a CSV: {e}")

    try:
        gt = pd.read_csv(ground_truth_path)
    except Exception as e:
        pytest.fail(f"Could not read {ground_truth_path} as a CSV: {e}")

    assert 'entity_id' in sub.columns, f"'entity_id' column missing in {submission_path}"
    assert 'total_value' in sub.columns, f"'total_value' column missing in {submission_path}"

    merged = pd.merge(gt, sub, on='entity_id', how='left')

    if merged['total_value_y'].isnull().any():
        missing_entities = merged[merged['total_value_y'].isnull()]['entity_id'].tolist()
        pytest.fail(f"Submission is missing entity_ids present in the ground truth. E.g.: {missing_entities[:5]}")

    mae = (merged['total_value_x'] - merged['total_value_y']).abs().mean()

    assert mae < 0.01, f"Mean Absolute Error (MAE) is {mae:.5f}, which is not less than the threshold of 0.01."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
