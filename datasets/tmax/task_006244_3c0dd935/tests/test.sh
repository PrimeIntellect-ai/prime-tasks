#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

RESULTS_FILE = "/home/user/results.json"

def test_results_file_exists():
    """Check if the results.json file was created."""
    assert os.path.isfile(RESULTS_FILE), f"The file {RESULTS_FILE} does not exist."

def test_results_json_structure():
    """Check if the results.json has the correct keys."""
    with open(RESULTS_FILE, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {RESULTS_FILE} is not valid JSON.")

    assert "abundances" in data, "Missing 'abundances' key in results.json."
    assert "shortest_path_cost" in data, "Missing 'shortest_path_cost' key in results.json."

def test_shortest_path_cost():
    """Check if the shortest path cost is correct."""
    with open(RESULTS_FILE, 'r') as f:
        data = json.load(f)

    cost = data.get("shortest_path_cost")
    assert isinstance(cost, int), f"'shortest_path_cost' must be an integer, got {type(cost)}."
    assert cost == 1680, f"Expected shortest_path_cost to be 1680, but got {cost}."

def test_abundances():
    """Check if the abundances are correctly calculated and rounded."""
    with open(RESULTS_FILE, 'r') as f:
        data = json.load(f)

    abundances = data.get("abundances")
    assert isinstance(abundances, dict), f"'abundances' must be a dictionary, got {type(abundances)}."

    expected_abundances = {
        "T1": 9.85,
        "T2": 10.15,
        "T3": 14.88
    }

    for t_id, expected_val in expected_abundances.items():
        assert t_id in abundances, f"Missing transcript {t_id} in abundances."
        val = abundances[t_id]
        assert isinstance(val, (int, float)), f"Abundance for {t_id} must be a number."
        assert math.isclose(val, expected_val, rel_tol=1e-2), \
            f"Expected abundance for {t_id} to be {expected_val}, but got {val}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
