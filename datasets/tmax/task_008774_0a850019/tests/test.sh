#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import itertools
import numpy as np

def test_top_singular_values_exists_and_format():
    """Test that top_singular_values.txt exists and has exactly two float values."""
    file_path = "/home/user/top_singular_values.txt"
    assert os.path.isfile(file_path), f"File missing: {file_path}"

    with open(file_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 2, f"Expected exactly 2 lines in {file_path}, found {len(lines)}"

    try:
        s1 = float(lines[0])
        s2 = float(lines[1])
    except ValueError:
        assert False, f"Values in {file_path} are not valid floats."

    assert math.isfinite(s1) and math.isfinite(s2), "Singular values must be finite."
    assert s1 >= s2, "Singular values should be sorted in descending order."

def test_norms_exists_and_format():
    """Test that norms.txt exists and has two comma-separated float values."""
    file_path = "/home/user/norms.txt"
    assert os.path.isfile(file_path), f"File missing: {file_path}"

    with open(file_path, 'r') as f:
        content = f.read().strip()

    parts = content.split(',')
    assert len(parts) == 2, f"Expected 2 comma-separated values in {file_path}, found {len(parts)}"

    try:
        full_norm = float(parts[0])
        rank2_norm = float(parts[1])
    except ValueError:
        assert False, f"Values in {file_path} are not valid floats."

    assert math.isfinite(full_norm) and math.isfinite(rank2_norm), "Norm values must be finite."

def test_correctness_of_values():
    """
    Recompute the k-mer matrix, its singular values, and its Frobenius norms
    to validate the student's results.
    """
    fasta_path = "/home/user/sequences.fasta"
    assert os.path.isfile(fasta_path), f"File missing: {fasta_path}"

    with open(fasta_path, 'r') as f:
        lines = f.readlines()

    seqs = [lines[i].strip() for i in range(1, len(lines), 2)]

    kmers = ["".join(p) for p in itertools.product('ACGT', repeat=3)]
    kmer_idx = {k: i for i, k in enumerate(kmers)}

    # Build matrix
    N = len(seqs)
    M = [[0.0] * 64 for _ in range(N)]
    for i, seq in enumerate(seqs):
        for j in range(len(seq) - 2):
            kmer = seq[j:j+3]
            if kmer in kmer_idx:
                M[i][kmer_idx[kmer]] += 1.0

    # Center matrix
    col_means = [0.0] * 64
    for j in range(64):
        col_sum = sum(M[i][j] for i in range(N))
        col_means[j] = col_sum / N

    frobenius_sq = 0.0
    centered = np.empty((N, 64), dtype=float)
    for i in range(N):
        for j in range(64):
            val = M[i][j] - col_means[j]
            centered[i, j] = val
            frobenius_sq += val * val

    expected_full_norm = math.sqrt(frobenius_sq)
    expected_singular_values = np.linalg.svd(centered, compute_uv=False)
    expected_s1 = float(expected_singular_values[0])
    expected_s2 = float(expected_singular_values[1])
    expected_rank2_from_svd = math.sqrt(expected_s1**2 + expected_s2**2)

    # Read student's outputs
    with open("/home/user/norms.txt", 'r') as f:
        parts = f.read().strip().split(',')
        student_full_norm = float(parts[0])
        student_rank2_norm = float(parts[1])

    with open("/home/user/top_singular_values.txt", 'r') as f:
        lines = [line.strip() for line in f if line.strip()]
        s1 = float(lines[0])
        s2 = float(lines[1])

    assert math.isfinite(student_full_norm) and math.isfinite(student_rank2_norm)
    assert math.isfinite(s1) and math.isfinite(s2)

    # Check full norm
    assert math.isclose(student_full_norm, expected_full_norm, rel_tol=1e-3), \
        f"Expected full Frobenius norm to be approx {expected_full_norm:.4f}, but got {student_full_norm}"

    # Preserve the submitted-values consistency check.
    expected_rank2_norm = math.sqrt(s1**2 + s2**2)
    assert math.isclose(student_rank2_norm, expected_rank2_norm, rel_tol=1e-3), \
        f"Rank-2 norm ({student_rank2_norm}) does not match sqrt(s1^2 + s2^2) = {expected_rank2_norm:.4f}"

    # Independently verify both singular values and the resulting rank-2 norm.
    rounding_tolerance = 0.00051
    assert math.isclose(s1, expected_s1, rel_tol=0.0, abs_tol=rounding_tolerance), \
        f"Expected top singular value {expected_s1:.4f}, but got {s1}"
    assert math.isclose(s2, expected_s2, rel_tol=0.0, abs_tol=rounding_tolerance), \
        f"Expected second singular value {expected_s2:.4f}, but got {s2}"
    assert math.isclose(student_rank2_norm, expected_rank2_from_svd, rel_tol=0.0, abs_tol=rounding_tolerance), \
        f"Expected rank-2 Frobenius norm {expected_rank2_from_svd:.4f}, but got {student_rank2_norm}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
