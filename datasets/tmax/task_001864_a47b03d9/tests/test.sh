#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_filtered_signals_and_report():
    try:
        import numpy as np
    except ImportError:
        pytest.fail("numpy is not installed, but it is required for this test.")

    raw_path = '/home/user/raw_signals.npy'
    filtered_path = '/home/user/filtered_signals.npy'
    report_path = '/home/user/report.txt'

    assert os.path.exists(raw_path), f"Raw data file {raw_path} is missing."
    assert os.path.exists(filtered_path), f"Filtered data file {filtered_path} was not created."
    assert os.path.exists(report_path), f"Report file {report_path} was not created."

    # Load raw data and compute expected filtered data
    raw = np.load(raw_path)
    M = raw.shape[1]
    dx = 1.0 / (M - 1)

    expected_filtered = []
    for row in raw:
        d2 = np.diff(row, n=2) / (dx**2)
        if np.max(np.abs(d2)) < 100.0:
            expected_filtered.append(row)
    expected_filtered = np.array(expected_filtered)

    # Load student's filtered data
    try:
        student_filtered = np.load(filtered_path)
    except Exception as e:
        pytest.fail(f"Failed to load {filtered_path}: {e}")

    assert student_filtered.shape == expected_filtered.shape, \
        f"Expected filtered array shape {expected_filtered.shape}, got {student_filtered.shape}."

    np.testing.assert_allclose(
        student_filtered, 
        expected_filtered, 
        err_msg="The contents of the filtered_signals.npy do not match the expected filtered data."
    )

    # Compute expected SVD top 3 singular values
    _, S, _ = np.linalg.svd(expected_filtered)
    expected_report_str = f"{S[0]:.4f}, {S[1]:.4f}, {S[2]:.4f}"

    # Check report content
    with open(report_path, 'r') as f:
        student_report = f.read().strip()

    assert student_report == expected_report_str, \
        f"Expected report content '{expected_report_str}', but got '{student_report}'."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
