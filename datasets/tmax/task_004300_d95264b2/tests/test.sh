#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def test_report_exists_and_valid():
    report_path = '/home/user/report.json'
    assert os.path.exists(report_path), f"Report file not found at {report_path}"
    assert os.path.isfile(report_path), f"Path {report_path} is not a file"

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} does not contain valid JSON")

    expected_keys = {"best_model", "best_model_mse", "most_similar_model", "similarity_score"}
    assert set(report_data.keys()) == expected_keys, f"Report keys do not match expected keys. Found: {list(report_data.keys())}"

    assert report_data["best_model"] == "model_B", f"Expected best_model to be 'model_B', got {report_data['best_model']}"

    # Check MSE with small tolerance due to rounding
    mse = report_data["best_model_mse"]
    assert isinstance(mse, (int, float)), "best_model_mse must be a number"
    assert math.isclose(mse, 0.0084, abs_tol=0.0001), f"Expected best_model_mse to be around 0.0084, got {mse}"

    assert report_data["most_similar_model"] == "model_C", f"Expected most_similar_model to be 'model_C', got {report_data['most_similar_model']}"

    # Check similarity score
    sim_score = report_data["similarity_score"]
    assert isinstance(sim_score, (int, float)), "similarity_score must be a number"
    assert math.isclose(sim_score, 1.0000, abs_tol=0.0001), f"Expected similarity_score to be around 1.0000, got {sim_score}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
