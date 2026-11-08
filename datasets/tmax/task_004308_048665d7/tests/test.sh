#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import csv
import math
import cmath
import pytest

def get_stable_ids(reference_path):
    stable_ids = set()
    with open(reference_path, 'r') as f:
        reader = csv.reader(f)
        header = next(reader)
        for row in reader:
            if row:
                stable_ids.add(row[0])
    return stable_ids

def compute_wiener_index(adj):
    n = len(adj)
    total_dist = 0
    for i in range(n):
        # BFS
        visited = {i: 0}
        queue = [i]
        while queue:
            curr = queue.pop(0)
            dist = visited[curr]
            for j in range(n):
                if adj[curr][j] and j not in visited:
                    visited[j] = dist + 1
                    queue.append(j)
        total_dist += sum(visited.values())
    return total_dist // 2

def compute_dft_and_denoise(signal):
    N = len(signal)
    # Only compute DFT for k in 0..19 and 1004..1023
    kept_k = list(range(20)) + list(range(1004, 1024))
    X = {}
    for k in kept_k:
        X[k] = sum(signal[n] * cmath.exp(-2j * math.pi * k * n / N) for n in range(N))

    # Compute IDFT using only kept_k
    denoised = []
    for n in range(N):
        val = sum(X[k] * cmath.exp(2j * math.pi * k * n / N) for k in kept_k) / N
        denoised.append(val.real)
    return max(denoised)

def test_results_json():
    base_dir = "/home/user/spectro_graphs"
    results_path = os.path.join(base_dir, "results.json")
    molecules_path = os.path.join(base_dir, "molecules.json")
    reference_path = os.path.join(base_dir, "reference.csv")

    assert os.path.isfile(results_path), f"Results file {results_path} is missing."

    stable_ids = get_stable_ids(reference_path)

    with open(molecules_path, 'r') as f:
        molecules = json.load(f)

    W_list = []
    P_list = []

    for mol in molecules:
        if mol['id'] not in stable_ids:
            continue
        W = compute_wiener_index(mol['adjacency_matrix'])
        P = compute_dft_and_denoise(mol['raw_signal'])
        W_list.append(W)
        P_list.append(P)

    # Compute OLS beta and condition number
    M = len(W_list)
    sum_W = sum(W_list)
    sum_W2 = sum(w * w for w in W_list)
    sum_P = sum(P_list)
    sum_WP = sum(w * p for w, p in zip(W_list, P_list))

    beta = (M * sum_WP - sum_W * sum_P) / (M * sum_W2 - sum_W**2)

    # Condition number of X
    # X^T X = [[M, sum_W], [sum_W, sum_W2]]
    a = M
    b = sum_W
    c = sum_W
    d = sum_W2

    trace = a + d
    det = a * d - b * c

    lambda1 = (trace + math.sqrt(trace**2 - 4 * det)) / 2
    lambda2 = (trace - math.sqrt(trace**2 - 4 * det)) / 2

    cond = math.sqrt(lambda1 / lambda2)

    with open(results_path, 'r') as f:
        try:
            results = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("results.json is not a valid JSON file.")

    assert "beta" in results, "Key 'beta' missing in results.json"
    assert "condition_number" in results, "Key 'condition_number' missing in results.json"

    assert abs(results["beta"] - beta) <= 0.001, f"Expected beta ~ {beta:.4f}, got {results['beta']}"
    assert abs(results["condition_number"] - cond) <= 0.001, f"Expected condition_number ~ {cond:.4f}, got {results['condition_number']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
