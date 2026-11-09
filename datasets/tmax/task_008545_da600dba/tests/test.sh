#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import subprocess
import pytest

def get_expected_lines():
    """
    Computes the expected output using the exact procedure specified in the task.
    We run this in a subprocess to strictly avoid importing third-party libraries
    directly in the test file, while still deriving the truth data dynamically.
    """
    script = """
import pandas as pd
import numpy as np

try:
    df = pd.read_csv('/home/user/perf_logs.csv')
    filtered = df[(df['endpoint'] == '/api/v1/process') & (df['payload_size'] > 500)]
    latencies = filtered['latency_ms'].values

    expected_lines = []
    for N in [1000, 5000, 10000, 50000]:
        np.random.seed(42)
        samples = np.random.choice(latencies, size=(N, 50), replace=True)
        batch_latencies = np.sum(samples, axis=1)
        p99 = np.percentile(batch_latencies, 99)
        expected_lines.append(f"N={N}, P99={p99:.2f}")

    print('\\n'.join(expected_lines))
except Exception as e:
    print(str(e), file=sys.stderr)
    sys.exit(1)
"""
    result = subprocess.run(
        [sys.executable, "-c", script],
        capture_output=True,
        text=True
    )
    if result.returncode != 0:
        pytest.fail(f"Failed to compute expected truth data. Subprocess error: {result.stderr}")

    return [line.strip() for line in result.stdout.strip().split('\n') if line.strip()]

def test_convergence_log_exists_and_correct():
    log_path = "/home/user/convergence_log.txt"

    assert os.path.exists(log_path), f"The output file {log_path} does not exist."
    assert os.path.isfile(log_path), f"The path {log_path} is not a file."

    with open(log_path, 'r') as f:
        actual_lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = get_expected_lines()

    assert len(actual_lines) == len(expected_lines), (
        f"Expected {len(expected_lines)} lines in {log_path}, but found {len(actual_lines)}."
    )

    for i, (actual, expected) in enumerate(zip(actual_lines, expected_lines)):
        assert actual == expected, (
            f"Line {i+1} mismatch in {log_path}.\nExpected: '{expected}'\nActual:   '{actual}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
