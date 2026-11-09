#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import pandas as pd
import pytest

PIPELINE_PATH = "/home/user/pipeline.py"
FINAL_FEATURES_PATH = "/home/user/final_features.csv"
SCORE_BINARY_PATH = "/app/score_features"
THRESHOLD = 0.85

def test_pipeline_exists_and_runs():
    assert os.path.exists(PIPELINE_PATH), f"Pipeline script missing at {PIPELINE_PATH}"

    # Remove final features if it exists to ensure pipeline creates it
    if os.path.exists(FINAL_FEATURES_PATH):
        os.remove(FINAL_FEATURES_PATH)

    result = subprocess.run(["python3", PIPELINE_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Pipeline script failed to run. Stderr: {result.stderr}"

    assert os.path.exists(FINAL_FEATURES_PATH), f"Pipeline did not create {FINAL_FEATURES_PATH}"

def test_final_features_format():
    assert os.path.exists(FINAL_FEATURES_PATH), f"Missing {FINAL_FEATURES_PATH}"

    try:
        df = pd.read_csv(FINAL_FEATURES_PATH, header=None)
    except Exception as e:
        pytest.fail(f"Failed to read {FINAL_FEATURES_PATH} as CSV: {e}")

    assert df.shape == (1000, 10), f"Expected shape (1000, 10), got {df.shape}"

    # Check if all columns are numeric
    for col in df.columns:
        assert pd.api.types.is_numeric_dtype(df[col]), f"Column {col} is not numeric"

    # Check for missing values
    assert df.isnull().sum().sum() == 0, "Output features contain missing values"

def test_accuracy_metric():
    assert os.path.exists(FINAL_FEATURES_PATH), f"Missing {FINAL_FEATURES_PATH}"
    assert os.path.exists(SCORE_BINARY_PATH), f"Missing binary {SCORE_BINARY_PATH}"

    result = subprocess.run([SCORE_BINARY_PATH, FINAL_FEATURES_PATH], capture_output=True, text=True)
    assert result.returncode == 0, f"Binary execution failed. Stderr: {result.stderr}"

    output = result.stdout.strip()

    # Parse the last floating point number
    words = output.split()
    accuracy = None
    for word in reversed(words):
        try:
            accuracy = float(word)
            break
        except ValueError:
            continue

    assert accuracy is not None, f"Could not parse accuracy from binary output: {output}"
    assert accuracy >= THRESHOLD, f"Accuracy {accuracy} is below the threshold of {THRESHOLD}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
