#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def get_fasta_data(fasta_path):
    sequences = {}
    current_seq = None
    with open(fasta_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith(">"):
                current_seq = line[1:]
                sequences[current_seq] = ""
            else:
                sequences[current_seq] += line
    return sequences

def compute_expected_metrics(sequences):
    metrics = []
    for seq_id, seq in sequences.items():
        length = len(seq)
        gc_count = seq.count('G') + seq.count('C')
        gc_content = (gc_count / length) * 100 if length > 0 else 0
        metrics.append((seq_id, length, gc_content))
    return metrics

def compute_expected_regression(metrics):
    X = [m[1] for m in metrics]
    Y = [m[2] for m in metrics]
    n = len(X)
    sum_x = sum(X)
    sum_y = sum(Y)
    sum_xy = sum(x * y for x, y in zip(X, Y))
    sum_xx = sum(x * x for x in X)

    slope = (n * sum_xy - sum_x * sum_y) / (n * sum_xx - sum_x**2)
    intercept = (sum_y / n) - slope * (sum_x / n)
    return slope, intercept

def compute_expected_histogram(metrics):
    bins = {i: 0 for i in range(0, 100, 10)}
    for _, _, gc in metrics:
        bin_start = int(gc // 10) * 10
        if bin_start == 100:
            bin_start = 90
        bins[bin_start] += 1
    return bins

def test_gc_content_tsv():
    fasta_path = "/home/user/sequences.fasta"
    tsv_path = "/home/user/gc_content.tsv"

    assert os.path.isfile(tsv_path), f"Expected output file {tsv_path} is missing."

    sequences = get_fasta_data(fasta_path)
    expected_metrics = compute_expected_metrics(sequences)

    with open(tsv_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_metrics), "Incorrect number of lines in gc_content.tsv"

    expected_dict = {m[0]: (m[1], m[2]) for m in expected_metrics}

    for line in lines:
        parts = line.split('\t')
        assert len(parts) == 3, f"Line in gc_content.tsv does not have 3 tab-separated columns: '{line}'"
        seq_id, length_str, gc_str = parts

        assert seq_id in expected_dict, f"Unexpected sequence ID in gc_content.tsv: {seq_id}"
        exp_length, exp_gc = expected_dict[seq_id]

        assert int(length_str) == exp_length, f"Incorrect length for {seq_id}"
        assert f"{exp_gc:.4f}" == gc_str, f"Incorrect GC content for {seq_id}. Expected {exp_gc:.4f}, got {gc_str}"

def test_regression_log():
    fasta_path = "/home/user/sequences.fasta"
    log_path = "/home/user/regression.log"

    assert os.path.isfile(log_path), f"Expected output file {log_path} is missing."

    sequences = get_fasta_data(fasta_path)
    metrics = compute_expected_metrics(sequences)
    exp_slope, exp_intercept = compute_expected_regression(metrics)

    with open(log_path, "r") as f:
        content = f.read().strip()

    parts = content.split()
    assert len(parts) == 2, f"regression.log must contain exactly two values, found: '{content}'"

    slope_str, intercept_str = parts
    assert slope_str == f"{exp_slope:.4f}", f"Incorrect slope. Expected {exp_slope:.4f}, got {slope_str}"
    assert intercept_str == f"{exp_intercept:.4f}", f"Incorrect intercept. Expected {exp_intercept:.4f}, got {intercept_str}"

def test_histogram_log():
    fasta_path = "/home/user/sequences.fasta"
    log_path = "/home/user/histogram.log"

    assert os.path.isfile(log_path), f"Expected output file {log_path} is missing."

    sequences = get_fasta_data(fasta_path)
    metrics = compute_expected_metrics(sequences)
    expected_bins = compute_expected_histogram(metrics)

    with open(log_path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == 10, f"Expected 10 bins in histogram.log, found {len(lines)}"

    for i, line in enumerate(lines):
        parts = line.split()
        assert len(parts) == 2, f"Line in histogram.log must contain exactly two values: '{line}'"

        bin_start_str, count_str = parts
        expected_bin_start = i * 10
        expected_count = expected_bins[expected_bin_start]

        assert int(bin_start_str) == expected_bin_start, f"Expected bin start {expected_bin_start}, got {bin_start_str}"
        assert int(count_str) == expected_count, f"Expected count {expected_count} for bin {expected_bin_start}, got {count_str}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
