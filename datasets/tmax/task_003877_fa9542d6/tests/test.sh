#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pandas as pd
import numpy as np
import pytest

def compute_expected_scores():
    demographics_path = "/home/user/demographics.csv"
    activity_path = "/home/user/activity.csv"

    assert os.path.exists(demographics_path), f"Missing {demographics_path}"
    assert os.path.exists(activity_path), f"Missing {activity_path}"

    demographics = pd.read_csv(demographics_path)
    activity = pd.read_csv(activity_path)

    agg = activity.groupby('uid').sum().reset_index()
    df = pd.merge(demographics, agg, on='uid', how='left').fillna(0)

    def compute_score(row):
        age = row['age']
        loc = row['location_code']
        c = row['clicks']
        i = row['impressions']
        d = row['duration_sec']

        denom = i if i > 1.0 else 1.0
        loc_mod = int(loc) % 10
        return (age * 0.5) + (loc_mod * 2.0) + ((c / denom) * 100.0) + (d * 0.01)

    df['expected_score'] = df.apply(compute_score, axis=1)
    df = df.sort_values('uid')
    return df[['uid', 'expected_score']]

def test_final_scores_mse():
    output_path = "/home/user/final_scores.csv"
    assert os.path.exists(output_path), f"The output file {output_path} does not exist."

    try:
        pred = pd.read_csv(output_path)
    except Exception as e:
        pytest.fail(f"Failed to read {output_path} as a CSV: {e}")

    assert 'uid' in pred.columns, "Output CSV is missing the 'uid' column."
    assert 'score' in pred.columns, "Output CSV is missing the 'score' column."

    truth = compute_expected_scores()

    assert len(pred) == len(truth), f"Length mismatch: Output has {len(pred)} rows, but expected {len(truth)} rows."

    # Ensure sorted by uid
    pred_sorted = pred.sort_values('uid').reset_index(drop=True)
    truth_sorted = truth.sort_values('uid').reset_index(drop=True)

    assert np.array_equal(pred_sorted['uid'].values, truth_sorted['uid'].values), "The 'uid' values in the output do not match the expected uids."

    mse = np.mean((pred_sorted['score'] - truth_sorted['expected_score'])**2)
    threshold = 0.001

    assert mse <= threshold, f"MSE is too high: {mse:.6f} > {threshold}. The predicted scores are not close enough to the true scores."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
