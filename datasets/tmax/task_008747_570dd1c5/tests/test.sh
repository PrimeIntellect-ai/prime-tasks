#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math
import numpy as np


def test_report_json_exists_and_valid():
    file_path = '/home/user/report.json'
    assert os.path.isfile(file_path), f"Output file {file_path} is missing."

    with open(file_path, 'r', encoding='utf-8') as f:
        try:
            report = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {file_path} is not a valid JSON."

    expected_keys = {
        "decay_constant",
        "dominant_frequency",
        "bootstrap_ci_lower",
        "bootstrap_ci_upper"
    }

    missing_keys = expected_keys - set(report.keys())
    assert not missing_keys, f"Missing keys in report.json: {missing_keys}"

    # Validate decay_constant
    decay = report.get("decay_constant")
    assert isinstance(decay, (int, float)), "decay_constant must be a number"
    assert math.isclose(decay, 0.150, abs_tol=0.005), f"decay_constant {decay} is incorrect. Expected ~0.150"

    # Validate dominant_frequency
    freq = report.get("dominant_frequency")
    assert isinstance(freq, (int, float)), "dominant_frequency must be a number"
    assert math.isclose(freq, 2.50, abs_tol=0.01), f"dominant_frequency {freq} is incorrect. Expected ~2.50"

    # Validate bootstrap_ci_lower
    ci_lower = report.get("bootstrap_ci_lower")
    assert isinstance(ci_lower, (int, float)), "bootstrap_ci_lower must be a number"
    assert math.isclose(ci_lower, 43.51, abs_tol=0.1), f"bootstrap_ci_lower {ci_lower} is incorrect. Expected ~43.51"

    # Derive the instructed upper bound from the supplied data using exactly
    # 10,000 bootstrap resamples and NumPy's seed 42.
    response_times = np.genfromtxt(
        '/home/user/perf_log.csv', delimiter=',', names=True
    )['response_time']
    np.random.seed(42)
    bootstrap_means = np.empty(10000)
    for i in range(10000):
        bootstrap_means[i] = np.random.choice(
            response_times, size=len(response_times), replace=True
        ).mean()
    expected_ci_upper = round(float(np.percentile(bootstrap_means, 97.5)), 2)

    # Validate bootstrap_ci_upper
    ci_upper = report.get("bootstrap_ci_upper")
    assert isinstance(ci_upper, (int, float)), "bootstrap_ci_upper must be a number"
    assert math.isclose(ci_upper, expected_ci_upper, abs_tol=0.1), f"bootstrap_ci_upper {ci_upper} is incorrect. Expected ~{expected_ci_upper:.2f}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
