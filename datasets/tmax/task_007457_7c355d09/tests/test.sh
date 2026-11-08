#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

BASE_DIR = "/home/user/graph_research"
RESULTS_FILE = os.path.join(BASE_DIR, "test_results.json")
EXPECTED_FILE = "/root/truth/expected.json"
SOLVER_FILE = os.path.join(BASE_DIR, "uf_solver")
ANALYZE_FILE = os.path.join(BASE_DIR, "analyze.py")

def test_executable_exists():
    assert os.path.isfile(SOLVER_FILE), f"Executable {SOLVER_FILE} was not found. Did you compile the C program?"
    assert os.access(SOLVER_FILE, os.X_OK), f"File {SOLVER_FILE} is not executable."

def test_analyze_script_exists():
    assert os.path.isfile(ANALYZE_FILE), f"Python script {ANALYZE_FILE} was not found."

def test_results_file_exists():
    assert os.path.isfile(RESULTS_FILE), f"Results file {RESULTS_FILE} was not found. Did the script run successfully?"

def test_results_content():
    assert os.path.isfile(EXPECTED_FILE), f"Truth file {EXPECTED_FILE} is missing. Cannot verify results."

    with open(EXPECTED_FILE, 'r') as f:
        expected = json.load(f)

    with open(RESULTS_FILE, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_FILE} is not valid JSON.")

    required_keys = ["t_statistic", "p_value", "simulated_mean", "reference_mean"]
    for key in required_keys:
        assert key in results, f"Key '{key}' is missing from {RESULTS_FILE}."
        assert isinstance(results[key], (int, float)), f"Value for '{key}' must be a number."

        expected_val = expected[key]
        actual_val = results[key]
        assert math.isclose(actual_val, expected_val, rel_tol=1e-4, abs_tol=1e-5), \
            f"Value for '{key}' is incorrect. Expected approx {expected_val}, got {actual_val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
