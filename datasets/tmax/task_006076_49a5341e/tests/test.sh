#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import csv
import sys
import subprocess
import pytest

def test_predictions_exists():
    """Check that the predictions file was created."""
    assert os.path.exists('/home/user/predictions.csv'), "/home/user/predictions.csv is missing. Did you run the script?"

def test_predictions_format():
    """Check that the predictions file has the correct headers and no float strings."""
    with open('/home/user/predictions.csv', 'r') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            pytest.fail("predictions.csv is empty")

        assert header == ['id', 'target'], f"predictions.csv header must be exactly 'id,target', got {header}"

        for i, row in enumerate(reader, start=2):
            assert len(row) == 2, f"Row {i} does not have exactly two columns"
            id_val, target_val = row
            assert '.' not in id_val, f"id column contains float values (e.g., '{id_val}') at row {i}. It must be an integer."
            assert '.' not in target_val, f"target column contains float values (e.g., '{target_val}') at row {i}. It must be an integer."

def test_predictions_correctness():
    """Recompute the expected predictions and assert an exact match."""
    # We write a small script to compute the truth using pandas and sklearn, 
    # then run it via subprocess to adhere to the stdlib-only rule in the test file itself.
    truth_script = """
import pandas as pd
from sklearn.ensemble import RandomForestClassifier

train = pd.read_csv('/home/user/train.csv')
test = pd.read_csv('/home/user/test.csv')

# 1. Median imputation using train only
f2_median = train['f2'].median()
train['f2'] = train['f2'].fillna(f2_median)
test['f2'] = test['f2'].fillna(f2_median)

# 2. Strict Data Types
train['id'] = train['id'].astype('int64')
train['f2'] = train['f2'].astype('int64')
test['id'] = test['id'].astype('int64')
test['f2'] = test['f2'].astype('int64')

X_train = train[['f1', 'f2', 'f3']]
y_train = train['target']
X_test = test[['f1', 'f2', 'f3']]

# 3. Reproducibility
clf = RandomForestClassifier(n_estimators=50, random_state=42)
clf.fit(X_train, y_train)

test['target'] = clf.predict(X_test).astype('int64')

# 4. Save
test[['id', 'target']].to_csv('/tmp/expected_predictions.csv', index=False)
"""
    truth_script_path = '/tmp/compute_truth.py'
    expected_output_path = '/tmp/expected_predictions.csv'

    with open(truth_script_path, 'w') as f:
        f.write(truth_script)

    try:
        subprocess.run([sys.executable, truth_script_path], check=True, capture_output=True)
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Failed to compute ground truth predictions: {e.stderr.decode()}")

    assert os.path.exists(expected_output_path), "Failed to generate ground truth predictions file."

    with open(expected_output_path, 'r') as f:
        expected_lines = f.read().splitlines()

    with open('/home/user/predictions.csv', 'r') as f:
        actual_lines = f.read().splitlines()

    assert len(actual_lines) == len(expected_lines), f"Expected {len(expected_lines)} rows, but got {len(actual_lines)} rows in predictions.csv"

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Mismatch at line {i + 1}.\n"
            f"Expected: {expected}\n"
            f"Actual:   {actual}\n"
            "Ensure you impute using the train median ONLY, cast id and f2 to int64, "
            "and use random_state=42 for the RandomForestClassifier."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
