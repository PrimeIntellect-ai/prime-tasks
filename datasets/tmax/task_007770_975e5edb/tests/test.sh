#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
from collections import defaultdict
import pytest

INPUT_FILE = "/home/user/config_updates.csv"
OUTPUT_FILE = "/home/user/flapping_report.csv"

def compute_expected_flaps(input_path):
    # Read input file
    updates = defaultdict(list)
    with open(input_path, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            if not row or len(row) < 4:
                continue
            timestamp, env, key, value = row
            updates[(env, key)].append(value)

    # Calculate flaps per (env, key)
    flap_counts = defaultdict(int)
    for (env, key), values in updates.items():
        flaps = 0
        for i in range(2, len(values)):
            if values[i] == values[i-2] and values[i] != values[i-1]:
                flaps += 1
        flap_counts[(env, key)] = flaps

    # Find max per Env
    env_max = {}
    for (env, key), count in flap_counts.items():
        if count == 0:
            continue
        if env not in env_max:
            env_max[env] = (key, count)
        else:
            current_best_key, current_max_count = env_max[env]
            if count > current_max_count:
                env_max[env] = (key, count)
            elif count == current_max_count:
                if key < current_best_key:
                    env_max[env] = (key, count)

    # Format expected output
    expected_rows = []
    for env in sorted(env_max.keys()):
        key, count = env_max[env]
        expected_rows.append([env, key, str(count)])

    return expected_rows

def test_output_file_exists():
    assert os.path.exists(OUTPUT_FILE), f"The expected output file {OUTPUT_FILE} does not exist."
    assert os.path.isfile(OUTPUT_FILE), f"The path {OUTPUT_FILE} is not a file."

def test_output_file_contents():
    assert os.path.exists(INPUT_FILE), f"The input file {INPUT_FILE} is missing."

    expected_data = compute_expected_flaps(INPUT_FILE)

    with open(OUTPUT_FILE, "r") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, f"The output file {OUTPUT_FILE} is empty."

    header = rows[0]
    assert header == ["Env", "Key", "Flaps"], f"The header in {OUTPUT_FILE} is incorrect. Expected ['Env', 'Key', 'Flaps'], got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_data), f"Expected {len(expected_data)} data rows, but found {len(data_rows)}."

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        assert actual == expected, f"Row {i+1} mismatch. Expected {expected}, but got {actual}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
