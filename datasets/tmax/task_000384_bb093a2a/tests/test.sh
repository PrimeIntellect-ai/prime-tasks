#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import re
import random
import subprocess
import pytest

def get_uris_from_ttl(filepath):
    """Extract all URIs from the Turtle file."""
    with open(filepath, "r", encoding="utf-8") as f:
        content = f.read()
    # Extract URIs enclosed in angle brackets
    uris = re.findall(r'<([^>]+)>', content)
    return sorted(list(set(uris)))

def test_agent_script_exists():
    assert os.path.isfile("/home/user/query_distance.py"), "Agent script /home/user/query_distance.py is missing."

def test_fuzz_equivalence():
    dataset_path = "/home/user/dataset.ttl"
    oracle_path = "/tests/oracle_query_distance"
    agent_script = "/home/user/query_distance.py"

    assert os.path.isfile(dataset_path), f"Missing dataset file: {dataset_path}"
    assert os.path.isfile(oracle_path), f"Missing oracle file: {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle is not executable: {oracle_path}"

    uris = get_uris_from_ttl(dataset_path)
    assert len(uris) >= 2, "Not enough URIs found in the dataset to perform fuzz testing."

    random.seed(42)
    N = 50
    test_pairs = [tuple(random.sample(uris, 2)) for _ in range(N)]

    for u1, u2 in test_pairs:
        oracle_cmd = [oracle_path, u1, u2]
        agent_cmd = ["python3", agent_script, u1, u2]

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed on inputs {u1} {u2}. Stderr: {oracle_res.stderr}"

        if agent_res.returncode != 0:
            pytest.fail(f"Agent script failed with non-zero exit code on inputs {u1} {u2}.\nStderr: {agent_res.stderr}")

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch for source: {u1} and target: {u2}.\n"
            f"Expected (Oracle): '{oracle_out}'\n"
            f"Got (Agent): '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
