#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import pytest

def test_analysis_summary_exists_and_valid():
    path = "/home/user/analysis_summary.json"
    assert os.path.isfile(path), f"File {path} does not exist. The reporting file was not created."

    try:
        with open(path, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {path} is not valid JSON.")

    expected_keys = {
        "clean_row_count",
        "abs_correlation_pc1",
        "abs_correlation_pc2",
        "missing_predictions"
    }

    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in {path}: {missing_keys}"

    # Check clean_row_count
    assert data["clean_row_count"] == 6, f"Expected 'clean_row_count' to be 6, got {data['clean_row_count']}."

    # Check missing_predictions
    assert data["missing_predictions"] == 2, f"Expected 'missing_predictions' to be 2, got {data['missing_predictions']}."

    # Check correlations with tolerance
    expected_pc1 = 0.0886
    expected_pc2 = 0.1764

    assert isinstance(data["abs_correlation_pc1"], (int, float)), "'abs_correlation_pc1' must be a number."
    assert isinstance(data["abs_correlation_pc2"], (int, float)), "'abs_correlation_pc2' must be a number."

    assert math.isclose(data["abs_correlation_pc1"], expected_pc1, abs_tol=0.0002), \
        f"Expected 'abs_correlation_pc1' to be approx {expected_pc1}, got {data['abs_correlation_pc1']}."

    assert math.isclose(data["abs_correlation_pc2"], expected_pc2, abs_tol=0.0002), \
        f"Expected 'abs_correlation_pc2' to be approx {expected_pc2}, got {data['abs_correlation_pc2']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
