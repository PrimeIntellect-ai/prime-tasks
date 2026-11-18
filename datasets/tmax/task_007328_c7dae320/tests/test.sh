#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
from collections import Counter
import pytest

def get_expected_data():
    file_path = "/home/user/config_changes.csv"
    if not os.path.exists(file_path):
        return [], 0

    max_conn_values = []
    with open(file_path, 'r') as f:
        for line in f:
            parts = line.split('|')
            if len(parts) >= 4:
                role = parts[2].strip()
                if role == 'web_server':
                    config_data = parts[3]
                    pairs = config_data.split(';')
                    for pair in pairs:
                        kv = pair.split(':')
                        if len(kv) == 2:
                            key = kv[0].strip().lower()
                            if key == 'max_connections':
                                val = int(kv[1].strip())
                                max_conn_values.append(val)

    counts = Counter(max_conn_values)
    # Sort by count descending, then value descending
    sorted_counts = sorted(counts.items(), key=lambda x: (x[1], x[0]), reverse=True)
    top_3 = sorted_counts[:3]

    total_sum = sum(max_conn_values)

    return top_3, total_sum

def test_top_configs_output():
    top_configs_path = "/home/user/top_configs.txt"
    assert os.path.exists(top_configs_path), f"Output file {top_configs_path} is missing."

    expected_top_3, _ = get_expected_data()

    with open(top_configs_path, 'r') as f:
        lines = [line.strip() for line in f if line.strip()]

    assert len(lines) == len(expected_top_3), f"Expected {len(expected_top_3)} lines in {top_configs_path}, but found {len(lines)}."

    for i, (expected_val, expected_count) in enumerate(expected_top_3):
        # Format is COUNT VALUE
        expected_line = f"{expected_count} {expected_val}"
        # Normalize whitespace in student's line
        actual_line = " ".join(lines[i].split())
        assert actual_line == expected_line, f"Line {i+1} in {top_configs_path} is incorrect. Expected '{expected_line}', got '{actual_line}'."

def test_config_sum_output():
    config_sum_path = "/home/user/config_sum.txt"
    assert os.path.exists(config_sum_path), f"Output file {config_sum_path} is missing."

    _, expected_sum = get_expected_data()

    with open(config_sum_path, 'r') as f:
        content = f.read().strip()

    assert content.isdigit(), f"The content of {config_sum_path} is not a valid integer."
    assert int(content) == expected_sum, f"The sum in {config_sum_path} is incorrect. Expected {expected_sum}, got {content}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
