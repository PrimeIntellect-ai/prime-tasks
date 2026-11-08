#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def test_analyze_c_exists():
    """Test that the C program source file was created."""
    file_path = "/home/user/analyze.c"
    assert os.path.exists(file_path), f"File missing: {file_path}"
    assert os.path.isfile(file_path), f"Not a file: {file_path}"

def test_output_txt_exists():
    """Test that the output text file was created."""
    file_path = "/home/user/output.txt"
    assert os.path.exists(file_path), f"File missing: {file_path}"
    assert os.path.isfile(file_path), f"Not a file: {file_path}"

def test_output_correctness():
    """Test that the computed probability and nearest neighbor index are exactly correct."""
    data_path = "/home/user/data.csv"
    assert os.path.exists(data_path), f"Data file missing: {data_path}"

    with open(data_path, "r") as f:
        lines = f.read().strip().split('\n')

    assert len(lines) > 1, "Data file is empty or missing data rows."
    data_lines = lines[1:]

    f1_0, f2_0 = [], []
    f1_1, f2_1 = [], []

    q_f1, q_f2 = 1.5, 2.0

    min_dist = float('inf')
    nearest_idx = -1

    for i, line in enumerate(data_lines):
        parts = line.strip().split(',')
        if len(parts) != 3:
            continue

        f1 = float(parts[0])
        f2 = float(parts[1])
        label = int(parts[2])

        if label == 0:
            f1_0.append(f1)
            f2_0.append(f2)
        elif label == 1:
            f1_1.append(f1)
            f2_1.append(f2)

        dist = math.sqrt((f1 - q_f1)**2 + (f2 - q_f2)**2)
        if dist < min_dist:
            min_dist = dist
            nearest_idx = i

    def calc_mean_var(vals):
        n = len(vals)
        mean = sum(vals) / n
        var = sum((x - mean)**2 for x in vals) / n
        return mean, var

    m_f1_0, v_f1_0 = calc_mean_var(f1_0)
    m_f2_0, v_f2_0 = calc_mean_var(f2_0)
    m_f1_1, v_f1_1 = calc_mean_var(f1_1)
    m_f2_1, v_f2_1 = calc_mean_var(f2_1)

    def gaussian_pdf(x, mean, var):
        return (1.0 / math.sqrt(2 * math.pi * var)) * math.exp(-((x - mean)**2) / (2 * var))

    p_q_given_0 = gaussian_pdf(q_f1, m_f1_0, v_f1_0) * gaussian_pdf(q_f2, m_f2_0, v_f2_0)
    p_q_given_1 = gaussian_pdf(q_f1, m_f1_1, v_f1_1) * gaussian_pdf(q_f2, m_f2_1, v_f2_1)

    p_1_given_q = (p_q_given_1 * 0.5) / (p_q_given_0 * 0.5 + p_q_given_1 * 0.5)

    expected_prob_str = f"{p_1_given_q:.4f}"
    expected_prob_line = f"Probability Class 1: {expected_prob_str}"
    expected_idx_line = f"Nearest Neighbor Index: {nearest_idx}"

    output_path = "/home/user/output.txt"
    with open(output_path, "r") as f:
        output_content = f.read().strip().split('\n')

    assert len(output_content) >= 2, f"Output file {output_path} does not have at least 2 lines."

    prob_line = output_content[0].strip()
    idx_line = output_content[1].strip()

    assert prob_line == expected_prob_line, f"Probability line mismatch. Expected '{expected_prob_line}', got '{prob_line}'"
    assert idx_line == expected_idx_line, f"Nearest neighbor index line mismatch. Expected '{expected_idx_line}', got '{idx_line}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
