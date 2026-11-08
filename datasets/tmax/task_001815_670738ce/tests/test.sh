#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def get_score(c1, c2):
    if c1 == c2: return 5
    if {c1, c2} == {'A', 'G'} or {c1, c2} == {'C', 'T'}: return -1
    return -3

def score_window(m, w):
    return sum(get_score(m[i], w[i]) for i in range(15))

def test_optimization_log_exists():
    log_path = '/home/user/optimization.log'
    assert os.path.isfile(log_path), f"Optimization log not found at {log_path}"
    assert os.path.getsize(log_path) > 0, f"Optimization log at {log_path} is empty"

def test_optimal_motif_score():
    motif_path = '/home/user/optimal_motif.txt'
    assert os.path.isfile(motif_path), f"Motif file not found at {motif_path}"

    with open(motif_path, 'r') as f:
        motif = f.read().strip().upper()

    assert len(motif) == 15, f"Motif must be exactly 15 bases long, got {len(motif)}"
    assert all(c in 'ACGT' for c in motif), "Motif must contain only A, C, G, T characters"

    fasta_path = '/app/sequences.fasta'
    assert os.path.isfile(fasta_path), f"FASTA file not found at {fasta_path}"

    with open(fasta_path, 'r') as f:
        seqs = [line.strip() for line in f if not line.startswith('>')]

    assert len(seqs) > 0, "FASTA file contains no sequences"

    total_score = 0
    for s in seqs:
        best_score = -9999
        for i in range(len(s) - 14):
            best_score = max(best_score, score_window(motif, s[i:i+15]))
        total_score += best_score

    threshold = 5500
    assert total_score >= threshold, f"Motif score {total_score} is below the required threshold of {threshold}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
