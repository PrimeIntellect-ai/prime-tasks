#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def compute_expected_chain(csv_path):
    latest_state = {}
    with open(csv_path, 'r') as f:
        reader = csv.DictReader(f)
        # Assuming rows are already in chronological order or we just process them
        # The prompt says they are in chronological order by timestamp.
        for row in reader:
            emp = row['employee']
            if row['event_type'] == 'DELETE':
                if emp in latest_state:
                    del latest_state[emp]
            elif row['event_type'] == 'UPDATE':
                latest_state[emp] = row['manager']

    chain = ['EMP_404']
    current = 'EMP_404'

    # Safety against infinite loops in case of bad data
    visited = set([current])

    while current in latest_state:
        manager = latest_state[current]
        chain.append(manager)
        if manager == 'CEO':
            break
        if manager in visited:
            break
        visited.add(manager)
        current = manager

    return ",".join(chain)

def test_management_chain_output():
    csv_path = "/home/user/org_events.csv"
    output_path = "/home/user/management_chain.txt"

    assert os.path.exists(csv_path), f"The source file {csv_path} is missing."
    assert os.path.exists(output_path), f"The output file {output_path} was not created."
    assert os.path.isfile(output_path), f"The path {output_path} is not a file."

    expected_chain = compute_expected_chain(csv_path)

    with open(output_path, "r") as f:
        actual_content = f.read().strip()

    assert actual_content == expected_chain, (
        f"The content of {output_path} is incorrect.\n"
        f"Expected: {expected_chain}\n"
        f"Actual: {actual_content}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
