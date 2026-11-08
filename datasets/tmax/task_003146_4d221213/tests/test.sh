#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
from collections import defaultdict
import pytest

def get_expected_degrees(log_path):
    assert os.path.exists(log_path), f"{log_path} is missing"
    degrees = defaultdict(int)
    with open(log_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split('|')
            if len(parts) >= 3:
                degrees[parts[1]] += 1
                degrees[parts[2]] += 1

    # Sort by degree descending, then name ascending
    sorted_degrees = sorted(degrees.items(), key=lambda x: (-x[1], x[0]))
    return sorted_degrees

def test_degree_ranking_txt():
    log_path = "/home/user/collisions.log"
    ranking_path = "/home/user/degree_ranking.txt"

    assert os.path.exists(ranking_path), f"The file {ranking_path} is missing."

    sorted_degrees = get_expected_degrees(log_path)
    expected_lines = [f"{mol} {deg}" for mol, deg in sorted_degrees]
    expected_content = "\n".join(expected_lines)

    with open(ranking_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The contents of {ranking_path} are incorrect.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )

def test_top5_bar_txt():
    log_path = "/home/user/collisions.log"
    bar_path = "/home/user/top5_bar.txt"

    assert os.path.exists(bar_path), f"The file {bar_path} is missing."

    sorted_degrees = get_expected_degrees(log_path)
    top5 = sorted_degrees[:5]

    expected_lines = [f"{mol}: {'#' * deg}" for mol, deg in top5]
    expected_content = "\n".join(expected_lines)

    with open(bar_path, 'r') as f:
        actual_content = f.read().strip()

    assert actual_content == expected_content, (
        f"The contents of {bar_path} are incorrect.\n"
        f"Expected:\n{expected_content}\n\nActual:\n{actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
