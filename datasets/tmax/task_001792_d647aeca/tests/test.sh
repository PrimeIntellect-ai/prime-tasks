#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import json
import os
import pytest

def test_compliance_report_correct():
    input_file = "/home/user/ownership_data.json"
    output_file = "/home/user/compliance_report.json"

    assert os.path.exists(input_file), f"Input file {input_file} is missing."
    assert os.path.exists(output_file), f"Output file {output_file} is missing."

    with open(input_file, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Input file {input_file} does not contain valid JSON.")

    # Build adjacency list for ownership >= 25%
    adj = {}
    for doc in data:
        entity_id = doc.get("entity_id")
        adj[entity_id] = []
        for target in doc.get("owns", []):
            if target.get("percentage", 0) >= 25:
                adj[entity_id].append(target.get("target_id"))

    # Find distinct cyclic ownership chains of exactly 3 entities
    cycles = set()
    for u in adj:
        for v in adj[u]:
            if v in adj:
                for w in adj[v]:
                    if w in adj and u in adj[w]:
                        # Normalize by sorting alphabetically
                        normalized_cycle = tuple(sorted([u, v, w]))
                        cycles.add(normalized_cycle)

    # Sort lexicographically
    sorted_cycles = sorted(list(cycles))

    # Apply pagination: Page size 5, Page 2 (1-indexed)
    page_size = 5
    page_number = 2
    start_idx = (page_number - 1) * page_size
    end_idx = start_idx + page_size
    expected_page = [list(cycle) for cycle in sorted_cycles[start_idx:end_idx]]

    # Read output file
    with open(output_file, "r") as f:
        try:
            output_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {output_file} does not contain valid JSON.")

    assert isinstance(output_data, list), "Output should be a JSON array."

    assert output_data == expected_page, (
        f"Contents of {output_file} do not match expected Page 2 output.\n"
        f"Expected: {expected_page}\n"
        f"Got: {output_data}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
