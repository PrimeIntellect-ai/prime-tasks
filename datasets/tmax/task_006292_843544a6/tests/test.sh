#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest
from collections import defaultdict

def test_tvd_result():
    reads_path = "/home/user/reads.tsv"
    tvd_path = "/home/user/tvd_result.txt"

    assert os.path.isfile(reads_path), f"Input file {reads_path} is missing."
    assert os.path.isfile(tvd_path), f"Output file {tvd_path} is missing."

    # Compute expected TVD
    sample_lengths = defaultdict(list)
    with open(reads_path, "r") as f:
        for line in f:
            parts = line.strip().split("\t")
            if len(parts) >= 3:
                sample = parts[0]
                seq = parts[2]
                sample_lengths[sample].append(len(seq))

    assert "SampleA" in sample_lengths and "SampleB" in sample_lengths, "Missing required samples in reads.tsv"

    def get_prob_dist(lengths):
        total = len(lengths)
        dist = defaultdict(float)
        for L in lengths:
            dist[L] += 1.0 / total
        return dist

    p_a = get_prob_dist(sample_lengths["SampleA"])
    p_b = get_prob_dist(sample_lengths["SampleB"])

    all_lengths = set(p_a.keys()).union(set(p_b.keys()))
    tvd = 0.5 * sum(abs(p_a.get(L, 0.0) - p_b.get(L, 0.0)) for L in all_lengths)
    expected_tvd_str = f"{tvd:.4f}"

    with open(tvd_path, "r") as f:
        actual_tvd_str = f.read().strip()

    assert actual_tvd_str == expected_tvd_str, f"Expected TVD {expected_tvd_str}, but got {actual_tvd_str} in {tvd_path}"

def test_high_gc_bins():
    fasta_path = "/home/user/reference.fasta"
    gc_path = "/home/user/high_gc_bins.txt"

    assert os.path.isfile(fasta_path), f"Input file {fasta_path} is missing."
    assert os.path.isfile(gc_path), f"Output file {gc_path} is missing."

    # Compute expected high GC bins
    seq_parts = []
    with open(fasta_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line.startswith(">"):
                seq_parts.append(line)

    full_seq = "".join(seq_parts)

    expected_bins = []
    for i in range(len(full_seq) // 50):
        bin_seq = full_seq[i*50 : (i+1)*50]
        gc_count = bin_seq.count('G') + bin_seq.count('C')
        gc_percent = (gc_count / 50.0) * 100.0
        if gc_percent >= 60.0:
            expected_bins.append(str(i + 1))

    with open(gc_path, "r") as f:
        actual_bins = [line.strip() for line in f if line.strip()]

    assert actual_bins == expected_bins, f"Expected high GC bins {expected_bins}, but got {actual_bins} in {gc_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
