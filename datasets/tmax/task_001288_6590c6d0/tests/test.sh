#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sys
import subprocess
import pytest

def get_expected_values():
    """
    Computes the exact expected values by running a subprocess.
    This allows us to use numpy and pandas for the exact truth computation 
    while keeping the test file itself restricted to the standard library.
    """
    script = """
import json
import pandas as pd
import numpy as np
import re

df = pd.read_csv('/home/user/experiment_data.csv')

valid_times = []
for _, row in df.iterrows():
    try:
        p_class = str(row['predicted_class'])
        if not re.fullmatch(r'[A-Z]{3}', p_class):
            continue

        score = float(row['confidence_score'])
        if not (0.0 <= score <= 1.0):
            continue

        time_ms = float(row['inference_time_ms'])
        if time_ms <= 0 or np.isnan(time_ms):
            continue

        valid_times.append(time_ms)
    except:
        continue

valid_times = np.array(valid_times)

np.random.seed(42)
n_iterations = 10000
n_size = len(valid_times)

stats = list()
for i in range(n_iterations):
    sample = np.random.choice(valid_times, size=n_size, replace=True)
    stats.append(np.percentile(sample, 90))

p90_ci_lower = round(np.percentile(stats, 2.5), 2)
p90_ci_upper = round(np.percentile(stats, 97.5), 2)

expected_output = {
    "valid_count": n_size,
    "p90_ci_lower": p90_ci_lower,
    "p90_ci_upper": p90_ci_upper
}
print(json.dumps(expected_output))
"""
    result = subprocess.run(
        [sys.executable, "-c", script], 
        capture_output=True, 
        text=True, 
        check=True
    )
    return json.loads(result.stdout)

def test_report_exists_and_contains_correct_values():
    report_path = "/home/user/report.json"
    assert os.path.exists(report_path), f"Report file missing: {report_path}"

    with open(report_path, "r") as f:
        try:
            agent_output = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {report_path} is not valid JSON.")

    expected = get_expected_values()

    # Check for keys
    assert "valid_count" in agent_output, "Missing 'valid_count' in report."
    assert "p90_ci_lower" in agent_output, "Missing 'p90_ci_lower' in report."
    assert "p90_ci_upper" in agent_output, "Missing 'p90_ci_upper' in report."

    # Check exact values
    assert agent_output["valid_count"] == expected["valid_count"], \
        f"Expected valid_count {expected['valid_count']}, got {agent_output['valid_count']}"

    assert agent_output["p90_ci_lower"] == expected["p90_ci_lower"], \
        f"Expected p90_ci_lower {expected['p90_ci_lower']}, got {agent_output['p90_ci_lower']}"

    assert agent_output["p90_ci_upper"] == expected["p90_ci_upper"], \
        f"Expected p90_ci_upper {expected['p90_ci_upper']}, got {agent_output['p90_ci_upper']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
