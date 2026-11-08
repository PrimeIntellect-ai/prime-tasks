#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import urllib.parse
from collections import defaultdict

def test_c_source_exists():
    """Check if the C source file was created."""
    file_path = "/home/user/pipeline/scorer.c"
    assert os.path.isfile(file_path), f"C source file {file_path} does not exist."

def test_executable_exists():
    """Check if the C program was compiled to the expected executable."""
    file_path = "/home/user/pipeline/scorer"
    assert os.path.isfile(file_path), f"Executable {file_path} does not exist."
    assert os.access(file_path, os.X_OK), f"File {file_path} is not executable."

def test_scores_csv_correct():
    """Check if the generated scores.csv matches the expected computed output."""
    csv_path = "/home/user/pipeline/scores.csv"
    assert os.path.isfile(csv_path), f"Output file {csv_path} does not exist."

    graph_path = "/home/user/pipeline/access_graph.txt"
    assert os.path.isfile(graph_path), f"Input file {graph_path} is missing."

    incoming_weights = defaultdict(float)
    all_assets = set()

    # Parse the input graph to compute the expected truth
    with open(graph_path, "r") as f:
        for line in f:
            line = line.strip()
            if not line:
                continue

            parts = line.split()
            assert len(parts) == 3, f"Unexpected line format in graph: {line}"
            req_url, tgt_url, weight_str = parts
            weight = float(weight_str)

            # Extract 'asset' parameter from requesting URL
            req_parsed = urllib.parse.urlparse(req_url)
            req_qs = urllib.parse.parse_qs(req_parsed.query)
            req_asset = req_qs.get('asset', [None])[0]

            # Extract 'asset' parameter from target URL
            tgt_parsed = urllib.parse.urlparse(tgt_url)
            tgt_qs = urllib.parse.parse_qs(tgt_parsed.query)
            tgt_asset = tgt_qs.get('asset', [None])[0]

            if req_asset:
                all_assets.add(req_asset)
            if tgt_asset:
                all_assets.add(tgt_asset)
                incoming_weights[tgt_asset] += weight

    # Generate expected output lines
    expected_lines = []
    for asset in sorted(all_assets):
        score = 0.15 + 0.85 * incoming_weights[asset]
        expected_lines.append(f"{asset},{score:.4f}")

    # Read actual output lines
    with open(csv_path, "r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    # Compare
    assert actual_lines == expected_lines, (
        f"The contents of {csv_path} do not match the expected computed scores.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n\n"
        f"Actual:\n{chr(10).join(actual_lines)}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
