#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import itertools
import pytest

def transpose(M):
    return [[M[j][i] for j in range(len(M))] for i in range(len(M[0]))]

def matmul(A, B):
    return [[sum(A[i][k] * B[k][j] for k in range(len(A[0]))) for j in range(len(B[0]))] for i in range(len(A))]

def matvec(A, v):
    return [sum(A[i][k] * v[k] for k in range(len(A[0]))) for i in range(len(A))]

def invert_matrix(M):
    n = len(M)
    A = [row[:] + [1.0 if i == j else 0.0 for j in range(n)] for i, row in enumerate(M)]
    for i in range(n):
        pivot = i
        for j in range(i+1, n):
            if abs(A[j][i]) > abs(A[pivot][i]):
                pivot = j
        A[i], A[pivot] = A[pivot], A[i]

        pivot_val = A[i][i]
        if abs(pivot_val) < 1e-12:
            raise ValueError("Matrix is singular")

        for j in range(i, 2*n):
            A[i][j] /= pivot_val

        for j in range(n):
            if i != j:
                factor = A[j][i]
                for k in range(i, 2*n):
                    A[j][k] -= factor * A[i][k]

    return [row[n:] for row in A]

def test_kmer_weights():
    output_file = "/home/user/kmer_weights.csv"
    data_file = "/home/user/binding_data.txt"

    assert os.path.exists(output_file), f"Output file {output_file} does not exist."
    assert os.path.exists(data_file), f"Input file {data_file} does not exist."

    kmers = [''.join(p) for p in itertools.product('ACGT', repeat=3)]
    kmer_to_idx = {k: i for i, k in enumerate(kmers)}

    X = []
    y = []

    with open(data_file, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            seq, score = line.strip().split(',')
            if seq.startswith('ATGCGATCG'):
                trimmed = seq[9:]
                counts = [0.0] * 64
                for i in range(len(trimmed) - 2):
                    kmer = trimmed[i:i+3]
                    if kmer in kmer_to_idx:
                        counts[kmer_to_idx[kmer]] += 1.0
                X.append(counts)
                y.append(float(score))

    XT = transpose(X)
    XTX = matmul(XT, X)

    lam = 2.0
    for i in range(64):
        XTX[i][i] += lam

    XTX_inv = invert_matrix(XTX)
    XTy = matvec(XT, y)
    w = matvec(XTX_inv, XTy)

    expected_output = {kmers[i]: w[i] for i in range(64)}

    agent_output = {}
    with open(output_file, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            parts = line.strip().split(',')
            assert len(parts) == 2, f"Invalid format in {output_file}: '{line.strip()}'"
            agent_output[parts[0]] = float(parts[1])

    assert len(agent_output) == 64, f"Expected exactly 64 lines in {output_file}, found {len(agent_output)}"

    for k in kmers:
        assert k in agent_output, f"Missing 3-mer in output: {k}"
        expected_val = expected_output[k]
        agent_val = agent_output[k]
        assert abs(expected_val - agent_val) <= 1e-3, f"Mismatch for {k}: expected {expected_val:.4f}, got {agent_val}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
