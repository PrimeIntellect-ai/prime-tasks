#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import time
import subprocess
import pandas as pd
import pytest

def test_optimized_report_exists():
    path = "/home/user/optimized_report.py"
    assert os.path.isfile(path), f"Optimized report script is missing: {path}"

def test_report_csv_exists():
    path = "/home/user/report.csv"
    assert os.path.isfile(path), f"Output report CSV is missing: {path}"

def test_report_correctness():
    expected_path = "/tests/golden_report.csv"
    actual_path = "/home/user/report.csv"

    assert os.path.isfile(expected_path), f"Expected report missing: {expected_path}"
    assert os.path.isfile(actual_path), f"Actual report missing: {actual_path}"

    expected_df = pd.read_csv(expected_path)
    actual_df = pd.read_csv(actual_path)

    pd.testing.assert_frame_equal(
        actual_df,
        expected_df,
        check_dtype=False,
        check_exact=False,
        obj="Report DataFrames"
    )

def test_performance_speedup():
    naive_script = "/app/naive_report.py"
    opt_script = "/home/user/optimized_report.py"

    assert os.path.isfile(naive_script), f"Naive script missing: {naive_script}"
    assert os.path.isfile(opt_script), f"Optimized script missing: {opt_script}"

    # Benchmark Naive
    start_naive = time.time()
    subprocess.run(["python3", naive_script], stdout=subprocess.DEVNULL, check=True)
    naive_time = time.time() - start_naive

    # Benchmark Optimized
    start_opt = time.time()
    subprocess.run(["python3", opt_script], stdout=subprocess.DEVNULL, check=True)
    opt_time = time.time() - start_opt

    speedup = naive_time / max(opt_time, 0.0001)

    assert speedup >= 15.0, f"Speedup is too low. Expected >= 15.0, got {speedup:.2f} (Naive: {naive_time:.4f}s, Optimized: {opt_time:.4f}s)"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
