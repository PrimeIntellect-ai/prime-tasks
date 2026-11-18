#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import math
import pytest

def compute_expected_errors():
    seq = "AATGCGTAAGCTAGCTAGCATCGATCGATCGATCGAATCGCTAGCTAGCATCGA"
    k = 3
    kmers = [seq[i:i+k] for i in range(len(seq)-k+1)]
    unique_kmers = sorted(list(set(kmers)))
    N = len(unique_kmers)
    kmer_to_idx = {kmer: i for i, kmer in enumerate(unique_kmers)}

    adj = [[0.0] * N for _ in range(N)]
    for i in range(len(seq)-k):
        k1 = seq[i:i+k]
        k2 = seq[i+1:i+k+1]
        adj[kmer_to_idx[k1]][kmer_to_idx[k2]] += 1

    M = [[0.0] * N for _ in range(N)]
    for i in range(N):
        row_sum = sum(adj[i])
        if row_sum > 0:
            M[i] = [x / row_sum for x in adj[i]]
        else:
            M[i] = [1.0 / N for _ in range(N)]

    d = 0.85

    # Compute exact PageRank using a large number of power iterations
    v_exact = [1.0 / N] * N
    for _ in range(2000):
        v_next = [0.0] * N
        for i in range(N):
            s = sum(M[j][i] * v_exact[j] for j in range(N))
            v_next[i] = d * s + (1 - d) / N
        v_exact = v_next

    # Run power iteration to compute expected errors
    v = [1.0 / N] * N
    iterations = [1, 5, 10, 20, 50]
    results = {}

    for k_iter in range(1, 51):
        v_next = [0.0] * N
        for i in range(N):
            s = sum(M[j][i] * v[j] for j in range(N))
            v_next[i] = d * s + (1 - d) / N
        v = v_next

        if k_iter in iterations:
            err = max(abs(v[i] - v_exact[i]) for i in range(N))
            results[str(k_iter)] = err

    return results

def test_convergence_json_exists():
    assert os.path.exists("/home/user/convergence.json"), "The file /home/user/convergence.json does not exist."

def test_convergence_plot_exists():
    assert os.path.exists("/home/user/convergence_plot.png"), "The file /home/user/convergence_plot.png does not exist."

def test_convergence_json_content():
    json_path = "/home/user/convergence.json"
    assert os.path.exists(json_path), f"{json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("The file /home/user/convergence.json is not a valid JSON file.")

    expected_data = compute_expected_errors()

    for key in ["1", "5", "10", "20", "50"]:
        assert key in data, f"Key '{key}' is missing from convergence.json."

        actual_val = float(data[key])
        expected_val = expected_data[key]

        # Check within 1% tolerance or an absolute tolerance for very small numbers
        assert math.isclose(actual_val, expected_val, rel_tol=0.01, abs_tol=1e-7), \
            f"Value for iteration {key} is incorrect. Expected ~{expected_val}, got {actual_val}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
