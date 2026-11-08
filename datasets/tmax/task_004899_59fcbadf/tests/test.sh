#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import cmath
import math
import pytest

def fft(x):
    """Radix-2 Cooley-Tukey FFT"""
    N = len(x)
    if N <= 1:
        return x
    even = fft(x[0::2])
    odd = fft(x[1::2])
    T = [cmath.exp(-2j * math.pi * k / N) * odd[k] for k in range(N // 2)]
    return [even[k] + T[k] for k in range(N // 2)] + \
           [even[k] - T[k] for k in range(N // 2)]

def cholesky(A):
    """Cholesky decomposition for a symmetric positive-definite matrix."""
    n = len(A)
    L = [[0.0] * n for _ in range(n)]
    for i in range(n):
        for j in range(i + 1):
            s = sum(L[i][k] * L[j][k] for k in range(j))
            if i == j:
                L[i][j] = math.sqrt(A[i][i] - s)
            else:
                L[i][j] = (A[i][j] - s) / L[j][j]
    return L

def compute_expected_diagonals(seqs_file):
    with open(seqs_file, "r") as f:
        seqs = [line.strip() for line in f if line.strip()]

    mapping = {'A': 1.0, 'C': 2.0, 'G': 3.0, 'T': 4.0}
    P = []

    for seq in seqs:
        x = [mapping[c] for c in seq]
        X = fft(x)
        # r2c equivalent: take first N//2 + 1 elements
        X_r2c = X[: (len(x) // 2) + 1]
        power = [abs(c)**2 for c in X_r2c]
        total = sum(power)
        P.append([p / total for p in power])

    n_seqs = len(P)
    M = [[0.0] * n_seqs for _ in range(n_seqs)]

    for i in range(n_seqs):
        for j in range(n_seqs):
            M[i][j] = sum(P[i][k] * P[j][k] for k in range(len(P[0])))
            if i == j:
                M[i][j] += 0.01

    L = cholesky(M)
    return [L[i][i] for i in range(n_seqs)]

def test_source_code_exists():
    """Check that the C source code was created."""
    source_path = "/home/user/analyze_spectra.c"
    assert os.path.isfile(source_path), f"Source file {source_path} is missing."

def test_output_file_exists():
    """Check that the output file was created."""
    output_path = "/home/user/cholesky_diag.txt"
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

def test_output_values():
    """Check that the output values match the expected Cholesky diagonals."""
    seqs_path = "/home/user/data/seqs.txt"
    output_path = "/home/user/cholesky_diag.txt"

    assert os.path.isfile(seqs_path), f"Input file {seqs_path} is missing."
    assert os.path.isfile(output_path), f"Output file {output_path} is missing."

    expected_diagonals = compute_expected_diagonals(seqs_path)

    with open(output_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 4, f"Expected exactly 4 lines in {output_path}, but found {len(lines)}."

    for i, (line, expected) in enumerate(zip(lines, expected_diagonals)):
        try:
            val = float(line)
        except ValueError:
            pytest.fail(f"Line {i+1} in {output_path} is not a valid float: '{line}'")

        # The prompt requires 6 decimal places formatted output.
        expected_str = f"{expected:.6f}"
        assert line == expected_str, (
            f"Value at line {i+1} does not match. "
            f"Expected {expected_str}, got {line}."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
