#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest
from collections import defaultdict

def test_top_backups_json_exists_and_correct():
    deps_file = "/home/user/backup_deps.csv"
    corrupted_file = "/home/user/corrupted.txt"
    output_file = "/home/user/top_backups.json"

    assert os.path.isfile(deps_file), f"Missing file: {deps_file}"
    assert os.path.isfile(corrupted_file), f"Missing file: {corrupted_file}"
    assert os.path.isfile(output_file), f"Missing output file: {output_file}"

    # Recompute the expected result
    with open(corrupted_file, "r") as f:
        corrupted = set(line.strip() for line in f if line.strip())

    counts = defaultdict(int)
    with open(deps_file, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            parts = line.split(",")
            if len(parts) != 2:
                continue
            dep, base = parts
            if dep in corrupted or base in corrupted:
                continue
            counts[base] += 1

    # Sort by number of dependents (descending), then by backup_id (ascending)
    sorted_backups = sorted(counts.items(), key=lambda x: (-x[1], x[0]))
    top_3 = sorted_backups[:3]

    expected_json = [{"backup_id": b_id, "deps": count} for b_id, count in top_3]

    # Read and parse the actual output
    with open(output_file, "r") as f:
        try:
            actual_json = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON from {output_file}: {e}")

    assert actual_json == expected_json, (
        f"Output JSON does not match expected results.\n"
        f"Expected: {expected_json}\n"
        f"Actual: {actual_json}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
