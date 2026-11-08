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

def test_report_json_exists_and_correct():
    report_path = '/home/user/report.json'
    assert os.path.isfile(report_path), f"File missing: {report_path}"

    with open(report_path, 'r') as f:
        try:
            report_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON")

    expected_keys = [
        "max_absolute_error",
        "mean_absolute_difference",
        "ci_lower",
        "ci_upper"
    ]
    for key in expected_keys:
        assert key in report_data, f"Missing key '{key}' in {report_path}"

    # Recompute expected values using stdlib
    raw_path = '/home/user/raw_sensor_data.csv'
    legacy_path = '/home/user/legacy_daily_summary.csv'

    assert os.path.isfile(raw_path), "Raw data file missing"
    assert os.path.isfile(legacy_path), "Legacy data file missing"

    # 1. Compute true means
    date_sums = {}
    date_counts = {}
    with open(raw_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            d = row['date']
            val = float(row['reading'])
            date_sums[d] = date_sums.get(d, 0.0) + val
            date_counts[d] = date_counts.get(d, 0) + 1

    true_means = {d: date_sums[d] / date_counts[d] for d in date_sums}

    # 2. Read legacy means
    legacy_means = {}
    with open(legacy_path, 'r') as f:
        reader = csv.DictReader(f)
        for row in reader:
            legacy_means[row['date']] = float(row['legacy_mean'])

    # 3. Calculate absolute differences
    abs_diffs = []
    for d in true_means:
        if d in legacy_means:
            abs_diffs.append(abs(true_means[d] - legacy_means[d]))

    n = len(abs_diffs)
    assert n > 1, "Not enough data to compute confidence intervals"

    max_abs_error = max(abs_diffs)
    mean_abs_diff = sum(abs_diffs) / n

    # Sample variance and standard deviation
    variance = sum((x - mean_abs_diff) ** 2 for x in abs_diffs) / (n - 1)
    std_dev = math.sqrt(variance)
    sem = std_dev / math.sqrt(n)

    # Approximate t-value for 95% CI
    # Since n=30 (df=29), t is approx 2.04523
    # If n differs, we use a fallback or an approximate formula, but here n is exactly 30 from setup.
    t_value = 2.045229642132703
    if n != 30:
        # Fallback to normal approximation if somehow n changed
        t_value = 1.96

    ci_lower = mean_abs_diff - t_value * sem
    ci_upper = mean_abs_diff + t_value * sem

    expected_max = round(max_abs_error, 4)
    expected_mean = round(mean_abs_diff, 4)
    expected_ci_lower = round(ci_lower, 4)
    expected_ci_upper = round(ci_upper, 4)

    # Assertions with a small tolerance for floating point rounding differences
    assert math.isclose(report_data["max_absolute_error"], expected_max, abs_tol=1e-3), \
        f"max_absolute_error expected {expected_max}, got {report_data['max_absolute_error']}"

    assert math.isclose(report_data["mean_absolute_difference"], expected_mean, abs_tol=1e-3), \
        f"mean_absolute_difference expected {expected_mean}, got {report_data['mean_absolute_difference']}"

    assert math.isclose(report_data["ci_lower"], expected_ci_lower, abs_tol=1e-3), \
        f"ci_lower expected {expected_ci_lower}, got {report_data['ci_lower']}"

    assert math.isclose(report_data["ci_upper"], expected_ci_upper, abs_tol=1e-3), \
        f"ci_upper expected {expected_ci_upper}, got {report_data['ci_upper']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
