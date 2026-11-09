#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import math
import pytest

def get_expected_results(csv_path):
    # Parse CSV
    data = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            n = int(row['N'])
            t = float(row['time_ms'])
            if n not in data:
                data[n] = []
            data[n].append(t)

    # Calculate means
    n_vals = []
    t_means = []
    for n in sorted(data.keys()):
        n_vals.append(n)
        t_means.append(sum(data[n]) / len(data[n]))

    # Calculate c
    sum_x_t = 0.0
    sum_x_x = 0.0
    for n, t in zip(n_vals, t_means):
        x = n ** 2
        sum_x_t += x * t
        sum_x_x += x * x

    c = sum_x_t / sum_x_x

    # Calculate R^2
    ss_res = 0.0
    for n, t in zip(n_vals, t_means):
        x = n ** 2
        predicted = c * x
        ss_res += (t - predicted) ** 2

    mean_t = sum(t_means) / len(t_means)
    ss_tot = 0.0
    for t in t_means:
        ss_tot += (t - mean_t) ** 2

    r_squared = 1.0 - (ss_res / ss_tot)

    return round(c, 6), round(r_squared, 6)

def test_fit_results_exists():
    """Test that the fit_results.json file exists."""
    file_path = '/home/user/fit_results.json'
    assert os.path.exists(file_path), f"File {file_path} is missing. Did you create it?"
    assert os.path.isfile(file_path), f"{file_path} is not a valid file."

def test_fit_results_content():
    """Test that the fit_results.json contains the correct calculated values."""
    csv_path = '/home/user/profiling_data.csv'
    json_path = '/home/user/fit_results.json'

    assert os.path.exists(csv_path), "Original data file is missing."
    assert os.path.exists(json_path), "JSON results file is missing."

    expected_c, expected_r2 = get_expected_results(csv_path)

    with open(json_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{json_path} is not a valid JSON file.")

    assert "c" in results, "Key 'c' is missing from the JSON output."
    assert "r_squared" in results, "Key 'r_squared' is missing from the JSON output."

    actual_c = results["c"]
    actual_r2 = results["r_squared"]

    assert isinstance(actual_c, (int, float)), "'c' must be a numeric value."
    assert isinstance(actual_r2, (int, float)), "'r_squared' must be a numeric value."

    assert math.isclose(actual_c, expected_c, rel_tol=1e-5), f"Expected c to be {expected_c}, but got {actual_c}"
    assert math.isclose(actual_r2, expected_r2, rel_tol=1e-5), f"Expected r_squared to be {expected_r2}, but got {actual_r2}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
