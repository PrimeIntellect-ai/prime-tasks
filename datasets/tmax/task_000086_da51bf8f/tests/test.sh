#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import pytest

def compute_expected_matches():
    edges_path = "/home/user/edges.csv"
    knows = []
    lives_in = {}

    if not os.path.exists(edges_path):
        return []

    with open(edges_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            if len(parts) == 3:
                u, v, r = map(int, parts)
                if r == 1:
                    knows.append((u, v))
                elif r == 2:
                    lives_in.setdefault(u, set()).add(v)

    matches = []
    for a, b in knows:
        a_cities = lives_in.get(a, set())
        b_cities = lives_in.get(b, set())
        common = a_cities.intersection(b_cities)
        for c in common:
            matches.append((a, b, c))

    matches.sort()
    return matches

def test_matches_csv_exists_and_correct():
    output_path = "/home/user/matches.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist. Did you run the C program?"

    expected_matches = compute_expected_matches()

    actual_matches = []
    with open(output_path, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(',')
            assert len(parts) == 3, f"Invalid format in {output_path}: line '{line}' does not have exactly 3 comma-separated values."
            try:
                a, b, c = map(int, parts)
                actual_matches.append((a, b, c))
            except ValueError:
                pytest.fail(f"Invalid format in {output_path}: line '{line}' contains non-integer values.")

    assert actual_matches == expected_matches, (
        f"The contents of {output_path} do not match the expected output.\n"
        f"Expected: {expected_matches}\n"
        f"Actual: {actual_matches}\n"
        "Ensure you are finding the correct pattern and sorting the output correctly."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
