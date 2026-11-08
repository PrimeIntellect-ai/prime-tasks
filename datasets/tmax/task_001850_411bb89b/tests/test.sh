#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def get_sequences():
    seq_file = "/home/user/sequences.txt"
    assert os.path.exists(seq_file), f"Missing {seq_file}"
    with open(seq_file, "r") as f:
        return [line.strip() for line in f if line.strip()]

def get_2mer_counts(seq):
    counts = {}
    for i in range(len(seq) - 1):
        kmer = seq[i:i+2]
        counts[kmer] = counts.get(kmer, 0) + 1
    return counts

def manhattan_distance(counts1, counts2):
    keys = set(counts1.keys()).union(set(counts2.keys()))
    return sum(abs(counts1.get(k, 0) - counts2.get(k, 0)) for k in keys)

def test_matrix_csv():
    matrix_file = "/home/user/matrix.csv"
    assert os.path.exists(matrix_file), f"Missing {matrix_file}"

    seqs = get_sequences()
    n = len(seqs)
    counts = [get_2mer_counts(s) for s in seqs]

    expected_matrix = []
    for i in range(n):
        row = []
        for j in range(n):
            row.append(manhattan_distance(counts[i], counts[j]))
        expected_matrix.append(row)

    with open(matrix_file, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == n, f"Expected {n} rows in CSV, got {len(lines)}"

    for i in range(n):
        row_vals = [int(x.strip()) for x in lines[i].split(",")]
        assert row_vals == expected_matrix[i], f"Row {i} in CSV does not match expected distances."

def test_heatmap_pgm():
    pgm_file = "/home/user/heatmap.pgm"
    assert os.path.exists(pgm_file), f"Missing {pgm_file}"

    seqs = get_sequences()
    n = len(seqs)
    counts = [get_2mer_counts(s) for s in seqs]

    distances = []
    for i in range(n):
        for j in range(n):
            distances.append(manhattan_distance(counts[i], counts[j]))

    max_dist = max(distances) if distances else 1
    if max_dist == 0:
        max_dist = 1

    expected_pixels = [(d * 255) // max_dist for d in distances]

    with open(pgm_file, "r") as f:
        content = f.read().split()

    assert len(content) >= 4, "PGM file is missing required headers."
    assert content[0] == "P2", "PGM magic number must be P2."
    assert content[1] == str(n) and content[2] == str(n), f"PGM dimensions must be {n} {n}."
    assert content[3] == "255", "PGM max gray value must be 255."

    actual_pixels = [int(x) for x in content[4:]]
    assert len(actual_pixels) == len(expected_pixels), f"Expected {len(expected_pixels)} pixel values, got {len(actual_pixels)}"

    for i, (actual, expected) in enumerate(zip(actual_pixels, expected_pixels)):
        assert actual == expected, f"Pixel at index {i} is {actual}, expected {expected}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
