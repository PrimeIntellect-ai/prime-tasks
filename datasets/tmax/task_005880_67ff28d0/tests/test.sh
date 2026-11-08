#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import csv
import pytest
from collections import defaultdict

def get_expected_results(input_file):
    mentions_in = defaultdict(int)
    mentions_out = defaultdict(int)
    follows_in = defaultdict(int)
    nodes = set()

    with open(input_file, 'r') as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            data = json.loads(line)
            src = data['src']
            dst = data['dst']
            rel = data['rel']

            nodes.add(src)
            nodes.add(dst)

            if rel == 'mentions':
                mentions_out[src] += 1
                mentions_in[dst] += 1
            elif rel == 'follows':
                follows_in[dst] += 1

    pure_targets = []
    for node in nodes:
        if mentions_in[node] > 0 and mentions_out[node] == 0:
            pure_targets.append((node, follows_in[node]))

    # Sort primarily by follower_count descending, secondarily by node_id ascending
    pure_targets.sort(key=lambda x: (-x[1], x[0]))

    # Top 3
    return pure_targets[:3]

def test_pure_targets_csv_exists():
    file_path = "/home/user/pure_targets.csv"
    assert os.path.exists(file_path), f"Output file {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."

def test_pure_targets_csv_content():
    input_file = "/home/user/social_graph.jsonl"
    output_file = "/home/user/pure_targets.csv"

    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    expected_top_3 = get_expected_results(input_file)

    with open(output_file, 'r', newline='') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "The CSV file is empty."

    header = rows[0]
    assert header == ['node_id', 'follower_count'], f"Incorrect CSV header. Expected ['node_id', 'follower_count'], got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == len(expected_top_3), f"Expected {len(expected_top_3)} data rows, got {len(data_rows)}"

    for i, (expected_node, expected_count) in enumerate(expected_top_3):
        actual_node = data_rows[i][0]
        actual_count = data_rows[i][1]
        assert actual_node == expected_node, f"Row {i+1}: expected node_id '{expected_node}', got '{actual_node}'"
        assert str(actual_count) == str(expected_count), f"Row {i+1}: expected follower_count '{expected_count}', got '{actual_count}'"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
