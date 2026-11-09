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

def compute_expected_metrics(csv_path):
    valid_temps = []
    valid_pressures = []

    with open(csv_path, "r", encoding="utf-8") as f:
        reader = csv.DictReader(f)
        for row in reader:
            try:
                t = float(row['temperature'])
                p = float(row['pressure'])
            except (ValueError, TypeError):
                continue

            # Apply the stated strict comparisons literally. In particular,
            # NaN is not less than or greater than either bound and is retained.
            if t < -50.0 or t > 50.0:
                continue
            if p < 900.0 or p > 1100.0:
                continue

            valid_temps.append(t)
            valid_pressures.append(p)

    n = len(valid_temps)
    if n == 0:
        return {}

    mean_t = sum(valid_temps) / n
    mean_p = sum(valid_pressures) / n

    cov = sum((t - mean_t) * (p - mean_p) for t, p in zip(valid_temps, valid_pressures)) / (n - 1)

    var_t = sum((t - mean_t)**2 for t in valid_temps) / (n - 1)
    var_p = sum((p - mean_p)**2 for p in valid_pressures) / (n - 1)

    std_t = math.sqrt(var_t)
    std_p = math.sqrt(var_p)

    corr = cov / (std_t * std_p)

    margin = 1.96 * (std_t / math.sqrt(n))

    return {
        "valid_records": n,
        "temp_mean": round(mean_t, 4),
        "covariance": round(cov, 4),
        "correlation": round(corr, 4),
        "temp_ci_lower": round(mean_t - margin, 4),
        "temp_ci_upper": round(mean_t + margin, 4)
    }

def test_analysis_results_exists():
    """Test that the analysis_results.json file exists."""
    file_path = "/home/user/analysis_results.json"
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"Path {file_path} is not a file."

def test_analysis_results_content():
    """Test that the analysis_results.json contains the correct metrics."""
    results_path = "/home/user/analysis_results.json"
    csv_path = "/home/user/sensor_data.csv"

    assert os.path.exists(results_path), f"File {results_path} is missing."
    assert os.path.exists(csv_path), f"File {csv_path} is missing."

    with open(results_path, "r", encoding="utf-8") as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {results_path} does not contain valid JSON.")

    expected = compute_expected_metrics(csv_path)

    # Check keys
    expected_keys = set(expected.keys())
    actual_keys = set(results.keys())
    assert expected_keys == actual_keys, f"JSON keys mismatch. Expected {expected_keys}, got {actual_keys}"

    # Check valid_records (exact integer match)
    assert isinstance(results["valid_records"], int), "valid_records must be an integer."
    assert results["valid_records"] == expected["valid_records"], f"valid_records mismatch. Expected {expected['valid_records']}, got {results['valid_records']}"

    # Check float values (within 0.0001, or NaN when the stated rules produce NaN)
    float_keys = ["temp_mean", "covariance", "correlation", "temp_ci_lower", "temp_ci_upper"]
    for key in float_keys:
        actual_val = results[key]
        expected_val = expected[key]
        assert isinstance(actual_val, (int, float)), f"Value for {key} must be a number."
        if isinstance(expected_val, float) and math.isnan(expected_val):
            assert isinstance(actual_val, float) and math.isnan(actual_val), f"{key} mismatch. Expected NaN, got {actual_val}"
        else:
            assert abs(actual_val - expected_val) <= 0.00015, f"{key} mismatch. Expected {expected_val}, got {actual_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
