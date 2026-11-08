#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

def test_analysis_results_json_exists_and_valid():
    path = "/home/user/analysis_results.json"
    assert os.path.exists(path), f"File {path} is missing."
    assert os.path.isfile(path), f"Path {path} is not a regular file."

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} is not a valid JSON file."

    assert isinstance(data, dict), f"JSON content in {path} must be a dictionary."

    expected_keys = {"dropped_features", "best_alpha", "best_cv_score_r2"}
    missing_keys = expected_keys - set(data.keys())
    assert not missing_keys, f"Missing keys in JSON: {missing_keys}"

def test_analysis_results_values():
    path = "/home/user/analysis_results.json"
    if not os.path.exists(path):
        return # Handled by previous test

    with open(path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            return # Handled by previous test

    # Check dropped_features
    dropped = data.get("dropped_features")
    assert isinstance(dropped, list), f"'dropped_features' must be a list, got {type(dropped)}"
    assert set(dropped) == {"sensor_1"}, f"Expected 'dropped_features' to be ['sensor_1'], got {dropped}"

    # Check best_alpha
    best_alpha = data.get("best_alpha")
    assert isinstance(best_alpha, (int, float)), f"'best_alpha' must be a number, got {type(best_alpha)}"
    assert math.isclose(best_alpha, 10.0, rel_tol=1e-5), f"Expected 'best_alpha' to be 10.0, got {best_alpha}"

    # Check best_cv_score_r2
    best_cv_score = data.get("best_cv_score_r2")
    assert isinstance(best_cv_score, (int, float)), f"'best_cv_score_r2' must be a number, got {type(best_cv_score)}"
    assert math.isclose(best_cv_score, 0.9984, abs_tol=1e-3), f"Expected 'best_cv_score_r2' to be approximately 0.9984, got {best_cv_score}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
