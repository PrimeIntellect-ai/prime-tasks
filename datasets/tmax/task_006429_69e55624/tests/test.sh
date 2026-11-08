#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import sys
import pytest

def get_expected_result():
    """
    Computes the expected result using a subprocess to avoid importing numpy
    directly in the test file, adhering to the standard library constraint.
    """
    script = """
import numpy as np

runs = {}
diverged = set()
with open('/home/user/integration_logs.txt', 'r') as f:
    for line in f:
        parts = line.strip().split()
        run_id = int(parts[0].split('=')[1][:-1])
        err_val = parts[3].split('=')[1]

        if err_val in ('NaN', 'Inf'):
            diverged.add(run_id)
        else:
            if run_id not in runs:
                runs[run_id] = []
            runs[run_id].append(float(err_val))

valid_maxes = []
for run_id, errs in runs.items():
    if run_id not in diverged:
        valid_maxes.append(max(errs))

valid_maxes.sort() # Ensure deterministic order if needed, though dict order in Python 3.7+ is insertion order

np.random.seed(42)
means = []
for _ in range(10000):
    sample = np.random.choice(valid_maxes, size=len(valid_maxes), replace=True)
    means.append(np.mean(sample))

lower = np.percentile(means, 2.5)
upper = np.percentile(means, 97.5)

print(f"Lower: {lower:.5f}, Upper: {upper:.5f}")
"""
    result = subprocess.run([sys.executable, "-c", script], capture_output=True, text=True, check=True)
    return result.stdout.strip()

def test_ci_results_file_exists():
    """Check that the final results file was created."""
    assert os.path.exists("/home/user/ci_results.txt"), "The file /home/user/ci_results.txt does not exist."
    assert os.path.isfile("/home/user/ci_results.txt"), "/home/user/ci_results.txt is not a file."

def test_ci_results_content():
    """Check that the final results file contains the exact expected confidence interval."""
    expected_content = get_expected_result()

    with open("/home/user/ci_results.txt", "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"Content of /home/user/ci_results.txt is incorrect.\n"
        f"Expected: '{expected_content}'\n"
        f"Actual:   '{actual_content}'"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
