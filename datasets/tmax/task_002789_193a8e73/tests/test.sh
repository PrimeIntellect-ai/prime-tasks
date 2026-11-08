#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
from collections import defaultdict
import pytest

def test_graph_edges_output():
    jsonl_path = "/home/user/graph_edges.jsonl"

    assert os.path.exists(jsonl_path), f"Output file {jsonl_path} does not exist."

    # Immutable truth data from the dataset originally provided to the agent.
    # Do not trust the agent-writable input file during verification.
    expected_data = """192.168.1.1,10.0.0.5,443,1610000000
192.168.1.2,10.0.0.6,80,1610000005
192.168.1.1,10.0.0.5,443,1610000010
192.168.1.1,10.0.0.5,80,1610000015
10.0.0.5,192.168.1.100,22,1610000020
192.168.1.2,10.0.0.6,80,1610000025
192.168.1.2,10.0.0.6,80,1610000030
10.0.0.5,192.168.1.100,22,1610000035
172.16.0.1,192.168.1.1,8080,1610000040"""

    # Recompute the expected aggregation
    counts = defaultdict(int)
    for line in expected_data.strip().split('\n'):
        line = line.strip()
        if not line:
            continue
        parts = line.split(',')
        if len(parts) >= 3:
            src, dst, port = parts[0], parts[1], int(parts[2])
            counts[(src, dst, port)] += 1

    expected_records = []
    for (src, dst, port), weight in counts.items():
        expected_records.append({
            "source": src,
            "target": dst,
            "properties": {
                "port": port,
                "weight": weight
            }
        })

    # Sort lexicographically by source, then target, then numerically by port
    expected_records.sort(key=lambda x: (x["source"], x["target"], x["properties"]["port"]))

    # Read and parse actual output
    actual_records = []
    with open(jsonl_path, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                record = json.loads(line)
                actual_records.append(record)
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {jsonl_path} is not valid JSON: {line}")

    # Validate overall count
    assert len(actual_records) == len(expected_records), (
        f"Expected {len(expected_records)} records, but found {len(actual_records)} in {jsonl_path}."
    )

    # Validate each record and its types
    for i, (actual, expected) in enumerate(zip(actual_records, expected_records)):
        # Check structure and values
        assert actual == expected, (
            f"Record at line {i+1} does not match expected.\n"
            f"Actual: {actual}\nExpected: {expected}"
        )

        # Strict type checks for integers
        actual_port = actual.get("properties", {}).get("port")
        actual_weight = actual.get("properties", {}).get("weight")

        assert isinstance(actual_port, int) and not isinstance(actual_port, bool), (
            f"Port at line {i+1} must be an integer, but got {type(actual_port).__name__}."
        )
        assert isinstance(actual_weight, int) and not isinstance(actual_weight, bool), (
            f"Weight at line {i+1} must be an integer, but got {type(actual_weight).__name__}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
