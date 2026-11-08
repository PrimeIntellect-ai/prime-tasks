#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import math
import pytest

def test_top5_baseline_exists():
    """Check if the student created the top5_baseline.txt file."""
    assert os.path.isfile("/home/user/top5_baseline.txt"), "The file /home/user/top5_baseline.txt does not exist."

def test_top5_baseline_contents():
    """Verify that the top 5 closest items are correctly identified and sorted."""
    vectors_path = "/home/user/vectors.csv"
    assert os.path.isfile(vectors_path), f"Required file {vectors_path} is missing."

    # Parse vectors.csv
    vectors = {}
    with open(vectors_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            item_id = parts[0]
            v = [float(x) for x in parts[1:]]
            vectors[item_id] = v

    assert "target_842" in vectors, "target_842 is missing from vectors.csv."
    target_v = vectors["target_842"]

    # Calculate distances
    distances = []
    for item_id, v in vectors.items():
        if item_id == "target_842":
            continue
        dist = math.sqrt(sum((target_v[j] - v[j])**2 for j in range(5)))
        distances.append((dist, item_id))

    # Sort distances
    distances.sort()
    expected_top5 = [x[1] for x in distances[:5]]

    # Read student output
    baseline_path = "/home/user/top5_baseline.txt"
    assert os.path.isfile(baseline_path), "The file /home/user/top5_baseline.txt does not exist."

    with open(baseline_path, 'r') as f:
        student_output = [line.strip() for line in f if line.strip()]

    assert len(student_output) == 5, f"Expected exactly 5 item_ids in top5_baseline.txt, but found {len(student_output)}."

    for i in range(5):
        assert student_output[i] == expected_top5[i], (
            f"Mismatch at rank {i+1}. "
            f"Expected '{expected_top5[i]}', but got '{student_output[i]}'."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
