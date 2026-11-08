#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import math
import pytest

def get_counts(fasta_path):
    counts = {b1: {b2: 0 for b2 in 'ACGT'} for b1 in 'ACGT'}
    with open(fasta_path, 'r') as f:
        current_seq = []
        for line in f:
            line = line.strip()
            if line.startswith('>'):
                if current_seq:
                    seq = "".join(current_seq)
                    for i in range(len(seq)-1):
                        counts[seq[i]][seq[i+1]] += 1
                current_seq = []
            else:
                current_seq.append(line)
        if current_seq:
            seq = "".join(current_seq)
            for i in range(len(seq)-1):
                counts[seq[i]][seq[i+1]] += 1
    return counts

def dot_vector_matrix(v, m):
    return [sum(v[i] * m[i][j] for i in range(4)) for j in range(4)]

def l2_norm(v1, v2):
    return math.sqrt(sum((x - y)**2 for x, y in zip(v1, v2)))

def compute_expected(fasta_path):
    counts = get_counts(fasta_path)
    bases = ['A', 'C', 'G', 'T']

    # Transition matrix P
    P = []
    for r in bases:
        row_sum = sum(counts[r][c] for c in bases)
        P.append([counts[r][c] / row_sum for c in bases])

    pi = [0.25, 0.25, 0.25, 0.25]
    iterations = 0
    while True:
        pi_next = dot_vector_matrix(pi, P)
        iterations += 1
        if l2_norm(pi_next, pi) < 1e-7:
            pi = pi_next
            break
        pi = pi_next

    # Chi-square for row A
    row_A = [counts['A'][c] for c in bases]
    total_A = sum(row_A)
    expected = total_A / 4.0
    chi2_stat = sum((obs - expected)**2 / expected for obs in row_A)

    # P-value for chi-square with 3 degrees of freedom
    # p-value = erfc(sqrt(x/2)) + sqrt(2x/pi) * exp(-x/2)
    x = chi2_stat
    p_val = math.erfc(math.sqrt(x / 2)) + math.sqrt(2 * x / math.pi) * math.exp(-x / 2)

    return pi, iterations, p_val

def test_analysis_json_exists():
    assert os.path.exists('/home/user/analysis.json'), "The file /home/user/analysis.json was not created."
    assert os.path.isfile('/home/user/analysis.json'), "/home/user/analysis.json is not a file."

def test_analysis_json_contents():
    with open('/home/user/analysis.json', 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("/home/user/analysis.json does not contain valid JSON.")

    required_keys = {"stationary_distribution", "iterations_to_converge", "row_A_chi2_pvalue"}
    assert required_keys.issubset(set(data.keys())), f"JSON is missing keys. Found: {list(data.keys())}, Expected: {list(required_keys)}"

    expected_pi, expected_iterations, expected_pval = compute_expected('/home/user/sequences.fasta')

    # 1. Check stationary distribution
    pi_actual = data["stationary_distribution"]
    assert isinstance(pi_actual, list) and len(pi_actual) == 4, "stationary_distribution must be a list of 4 floats."
    for act, exp in zip(pi_actual, expected_pi):
        assert math.isclose(act, exp, abs_tol=1e-5), f"Stationary distribution mismatch. Expected {expected_pi}, got {pi_actual}."

    # 2. Check iterations
    iter_actual = data["iterations_to_converge"]
    assert isinstance(iter_actual, int), "iterations_to_converge must be an integer."
    assert iter_actual == expected_iterations, f"Iterations mismatch. Expected {expected_iterations}, got {iter_actual}."

    # 3. Check p-value
    pval_actual = data["row_A_chi2_pvalue"]
    assert isinstance(pval_actual, (int, float)), "row_A_chi2_pvalue must be a float."
    assert math.isclose(pval_actual, expected_pval, abs_tol=1e-5), f"P-value mismatch. Expected {expected_pval}, got {pval_actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
