#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import pytest
import os
import random
import string
import json
import subprocess

def generate_random_input():
    length = random.randint(10, 200)
    data = []
    types = ["USER", "SYSTEM", "ADMIN", "GUEST"]
    for _ in range(length):
        src = "".join(random.choices(string.ascii_uppercase, k=2))
        dst = "".join(random.choices(string.ascii_uppercase, k=2))
        edge_type = random.choice(types)
        weight = random.randint(1, 1000)
        data.append({
            "src": src,
            "dst": dst,
            "type": edge_type,
            "weight": weight
        })
    return data

def test_fuzz_equivalence():
    agent_script = "/home/user/process_graph.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)

    for i in range(100):
        input_data = generate_random_input()
        input_str = json.dumps(input_data)

        oracle_proc = subprocess.run(
            ["python3", oracle_script],
            input=input_str,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}. Error: {oracle_proc.stderr}"

        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_str,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i}\nError: {agent_proc.stderr}"

        try:
            oracle_out = json.loads(oracle_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Oracle returned invalid JSON on iteration {i}: {oracle_proc.stdout}")

        try:
            agent_out = json.loads(agent_proc.stdout)
        except json.JSONDecodeError:
            pytest.fail(f"Agent returned invalid JSON on iteration {i}: {agent_proc.stdout}")

        assert oracle_out == agent_out, (
            f"Mismatch on iteration {i}.\n"
            f"Input: {input_str}\n"
            f"Expected: {oracle_out}\n"
            f"Got: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
