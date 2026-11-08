#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import math

EXPECTED_TARGET = "ATGCACGTGACTAGCTACGATCGATCGTACGATCGATCGATCG"
EXPECTED_BACKGROUND = "ATATATATATGCGCATATATATATATATATATATATATATATA"

def get_complexity(seq: str) -> float:
    """
    The singular values of a 15x4 one-hot encoded matrix are the square roots
    of the column sums (i.e., the counts of each nucleotide).
    The nuclear norm is the sum of these singular values.
    """
    return sum(math.sqrt(seq.count(c)) for c in "ACGT")

def test_candidates_file_correctness():
    json_path = "/home/user/sequences.json"
    assert os.path.exists(json_path), f"Input file {json_path} is missing."

    with open(json_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} is not valid JSON."

    assert "target" in data and "background" in data, "Input JSON missing required keys."

    target = data["target"]
    background = data["background"]

    assert target == EXPECTED_TARGET, "The supplied target sequence was modified."
    assert background == EXPECTED_BACKGROUND, "The supplied background sequence was modified."

    # 1. Compute B_max from background
    b_max = max(get_complexity(background[i:i+15]) for i in range(len(background) - 14))

    # 2. Find valid windows in target
    expected_candidates = set()
    for i in range(len(target) - 14):
        window = target[i:i+15]
        if get_complexity(window) > b_max:
            expected_candidates.add(window)

    expected_sorted = sorted(list(expected_candidates))

    out_path = "/home/user/candidates.txt"
    assert os.path.exists(out_path), f"Output file {out_path} was not created."

    with open(out_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_sorted, (
        f"Contents of {out_path} do not match the expected output.\n"
        f"Expected: {expected_sorted}\n"
        f"Got: {actual_lines}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
