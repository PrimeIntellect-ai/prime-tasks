#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def test_final_concentration():
    alignments_path = "/home/user/alignments.txt"
    indices_path = "/home/user/random_indices.txt"
    result_path = "/home/user/final_concentration.txt"

    assert os.path.isfile(result_path), f"Missing file: {result_path}"

    with open(alignments_path, "r") as f:
        alignments = [float(x.strip()) for x in f.readlines() if x.strip()]

    with open(indices_path, "r") as f:
        indices = [int(x.strip()) for x in f.readlines() if x.strip()]

    assert len(alignments) == 10, "Alignments file should have 10 entries."
    assert len(indices) >= 10000, "Indices file should have at least 10000 entries."

    means = []
    for i in range(1000):
        sample_indices = indices[i*10 : (i+1)*10]
        sample = [alignments[idx - 1] for idx in sample_indices]
        means.append(sum(sample) / 10.0)

    means.sort()
    upper = means[974]  # 975th value (0-indexed 974)

    k = upper / 100.0
    C = 100.0
    dt = 0.1
    for _ in range(50):
        C = C - k * C * dt

    expected_C = f"{round(C, 4):.4f}"

    with open(result_path, "r") as f:
        actual_C = f.read().strip()

    assert actual_C == expected_C, f"Expected final concentration {expected_C}, but got {actual_C} in {result_path}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
