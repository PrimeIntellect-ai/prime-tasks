#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
from collections import defaultdict

def test_curated_features_exists():
    file_path = "/home/user/curated_features.tsv"
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a regular file."

def test_curated_features_content():
    raw_path = "/home/user/raw_alignments.tsv"
    out_path = "/home/user/curated_features.tsv"

    assert os.path.exists(raw_path), f"Input file {raw_path} is missing."
    assert os.path.exists(out_path), f"Output file {out_path} is missing."

    # Compute expected result dynamically
    groups = defaultdict(list)
    with open(raw_path, "r") as f:
        lines = f.read().strip().splitlines()

    # Skip header if it exists
    if lines and lines[0].startswith("AlignmentID"):
        lines = lines[1:]

    for line in lines:
        if not line.strip():
            continue
        parts = line.split("\t")
        if len(parts) >= 3:
            target_seq = parts[1]
            score = parts[2]
            if target_seq.startswith("GATTACA"):
                seq_len = len(target_seq)
                groups[seq_len].append(float(score))

    expected_lines = []
    for seq_len in sorted(groups.keys()):
        scores = groups[seq_len]
        match_count = len(scores)
        # Sort numerically descending, format as strings
        sorted_scores = sorted(scores, reverse=True)
        # Re-convert to original string format (e.g. 9.99, not 9.9900000)
        # Actually, we can just sort as floats and format to 2 decimal places as in the input
        sorted_scores_str = ",".join(f"{s:.2f}" for s in sorted_scores)
        expected_lines.append(f"{seq_len}\t{match_count}\t{sorted_scores_str}")

    expected_content = "\n".join(expected_lines)

    with open(out_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The content of {out_path} does not match the expected output.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
