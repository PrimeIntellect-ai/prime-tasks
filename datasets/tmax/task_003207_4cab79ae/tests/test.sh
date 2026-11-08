#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
import numpy as np

def align_score(a: str, b: str) -> float:
    score = 0.0
    for i in range(min(len(a), len(b))):
        if a[i] == b[i]:
            score += 1.0
    return score

def test_eigenvalue_result():
    output_path = '/home/user/eigenvalue.txt'
    assert os.path.isfile(output_path), f"Output file not found: {output_path}"

    with open(output_path, 'r') as f:
        content = f.read().strip()

    try:
        student_val = float(content)
    except ValueError:
        pytest.fail(f"Could not parse the content of {output_path} as a float. Content was: '{content}'")

    primer = "ACGTAACCGGTT"
    seqs = [primer, "ACGTACGTACGT", "CCGGTTCCGGTT", "ATGCATGCATGC", "TTTTCCCCGGGG"]

    n = len(seqs)
    M = np.zeros((n, n))
    for i in range(n):
        for j in range(n):
            M[i, j] = align_score(seqs[i], seqs[j])

    # Compute the leading eigenvalue using numpy
    eigenvalues = np.linalg.eigvals(M)
    expected_eigenvalue = np.max(np.real(eigenvalues))

    error = abs(student_val - expected_eigenvalue)
    threshold = 1e-3

    assert error < threshold, (
        f"Absolute error {error} exceeds threshold {threshold}. "
        f"Expected eigenvalue ~{expected_eigenvalue:.5f}, got {student_val:.5f}."
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
