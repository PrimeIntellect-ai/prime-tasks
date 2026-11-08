#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import json
import pytest
from datetime import datetime, timedelta

def generate_random_timestamp():
    start = datetime(2020, 1, 1)
    end = datetime(2025, 1, 1)
    dt = start + timedelta(seconds=random.randint(0, int((end - start).total_seconds())))
    return dt.strftime('%Y-%m-%dT%H:%M:%SZ')

def generate_random_input():
    length = random.randint(500, 5000)
    num_data_points = random.randint(5, 50)

    data_points = []
    for _ in range(num_data_points):
        ts = generate_random_timestamp()
        v = random.randint(-1000, 1000)
        data_points.append(f"[DATA] {ts} v={v}")

    # Calculate required junk length
    junk_len = length - sum(len(dp) for dp in data_points)
    if junk_len < 0:
        junk_len = 0

    junk = ''.join(random.choices(string.ascii_letters + string.digits + " \n\t", k=junk_len))

    # Mix them
    parts = list(junk)
    for dp in data_points:
        insert_idx = random.randint(0, len(parts))
        parts.insert(insert_idx, dp)

    return ''.join(parts)

def test_fuzz_equivalence():
    agent_script = "/home/user/process_telemetry.py"
    oracle_script = "/tests/oracle_process.py"

    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script missing at {oracle_script}"

    random.seed(42)

    for i in range(100):
        test_input = generate_random_input()

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=test_input,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {i}:\n{oracle_proc.stderr}"

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=test_input,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent script failed on input {i}:\n{agent_proc.stderr}"

        try:
            oracle_json = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle produced invalid JSON on input {i}")

        try:
            agent_json = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent produced invalid JSON on input {i}:\n{agent_proc.stdout}")

        assert agent_json == oracle_json, f"Mismatch on input {i}.\nInput:\n{test_input}\nOracle:\n{oracle_json}\nAgent:\n{agent_json}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
