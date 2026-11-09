#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import csv
import pytest

def test_csv_exists_and_correct():
    csv_path = "/home/user/network.csv"
    assert os.path.isfile(csv_path), f"Missing CSV file at {csv_path}"

    with open(csv_path, 'r') as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "CSV is empty"
    assert rows[0] == ["Source", "Destination"], "CSV headers are incorrect"

    expected_edges = {
        ("10", "20"), ("10", "30"), ("20", "40"), ("20", "50"),
        ("30", "60"), ("30", "70"), ("40", "80"), ("40", "90"),
        ("50", "100"), ("50", "110")
    }

    actual_edges = set()
    for row in rows[1:]:
        if len(row) == 2:
            actual_edges.add((row[0].strip(), row[1].strip()))

    assert actual_edges == expected_edges, f"CSV edges do not match expected. Got: {actual_edges}"

def test_query_binary_exists():
    bin_path = "/home/user/query"
    assert os.path.isfile(bin_path), f"Missing compiled binary at {bin_path}"
    assert os.access(bin_path, os.X_OK), f"Binary at {bin_path} is not executable"

def test_fuzz_equivalence():
    agent_bin = "/home/user/query"
    oracle_bin = "/tests/oracle_query"
    csv_path = "/home/user/network.csv"

    assert os.path.isfile(agent_bin), "Agent binary not found"
    assert os.path.isfile(oracle_bin), "Oracle binary not found"
    assert os.access(oracle_bin, os.X_OK), "Oracle binary is not executable"

    nodes = [10, 20, 30, 40, 50, 60, 70, 80, 90, 100, 110, 15, 25]
    random.seed(42)

    inputs = []
    for _ in range(500):
        u = random.choice(nodes)
        v = random.choice(nodes)
        inputs.append(f"{u} {v}")

    input_str = "\n".join(inputs) + "\n"

    # Run oracle supplied only at verification time.
    oracle_cmd = [oracle_bin, csv_path]
    try:
        oracle_proc = subprocess.run(oracle_cmd, input=input_str, text=True, capture_output=True, timeout=5)
        oracle_out = oracle_proc.stdout.strip().split('\n')
    except Exception as e:
        pytest.fail(f"Oracle execution failed: {e}")

    # Run agent
    agent_cmd = [agent_bin, csv_path]
    try:
        agent_proc = subprocess.run(agent_cmd, input=input_str, text=True, capture_output=True, timeout=5)
        agent_out = agent_proc.stdout.strip().split('\n')
    except Exception as e:
        pytest.fail(f"Agent execution failed: {e}")

    assert len(agent_out) == len(oracle_out), f"Output length mismatch. Expected {len(oracle_out)}, got {len(agent_out)}"

    for i, (expected, actual) in enumerate(zip(oracle_out, agent_out)):
        assert expected.strip() == actual.strip(), f"Mismatch on input '{inputs[i]}'. Expected '{expected.strip()}', got '{actual.strip()}'"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
