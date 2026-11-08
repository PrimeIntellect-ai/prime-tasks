#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random

def compute_expected_values():
    alpha_vals = []
    beta_vals = []

    for i in range(1, 101):
        random.seed(i * 123)
        alpha_vals.append(round(5.0 + random.random(), 4))
        random.seed(i * 456)
        beta_vals.append(round(4.2 + random.random() * 1.5, 4))

    alpha_mean = sum(alpha_vals) / 100
    beta_mean = sum(beta_vals) / 100
    alpha_p95 = sorted(alpha_vals)[94]
    beta_p95 = sorted(beta_vals)[94]

    faster = "Alpha" if alpha_mean < beta_mean else "Beta"

    return {
        "Alpha Mean": f"{alpha_mean:.2f}",
        "Alpha P95": f"{alpha_p95:.2f}",
        "Beta Mean": f"{beta_mean:.2f}",
        "Beta P95": f"{beta_p95:.2f}",
        "Faster Solver": faster
    }

def test_perf_report_exists():
    """Test that the performance report file exists."""
    assert os.path.isfile("/home/user/perf_report.txt"), "The file /home/user/perf_report.txt does not exist."

def test_perf_report_contents():
    """Test that the performance report contains the correct calculations."""
    expected_values = compute_expected_values()

    with open("/home/user/perf_report.txt", "r") as f:
        content = f.read().strip().splitlines()

    parsed_report = {}
    for line in content:
        if ":" in line:
            key, val = line.split(":", 1)
            parsed_report[key.strip()] = val.strip()

    for key, expected_val in expected_values.items():
        assert key in parsed_report, f"Missing key '{key}' in /home/user/perf_report.txt"
        assert parsed_report[key] == expected_val, f"Incorrect value for '{key}'. Expected {expected_val}, got {parsed_report[key]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
