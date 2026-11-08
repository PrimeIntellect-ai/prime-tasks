#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import random
import string
import subprocess
import pytest

def generate_random_server_name():
    length = random.randint(5, 15)
    chars = string.ascii_lowercase + string.digits + "-"
    return "".join(random.choice(chars) for _ in range(length))

def test_executable_exists():
    agent_path = "/home/user/uptime-analyzer-fixed"
    assert os.path.isfile(agent_path), f"Agent executable not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent executable at {agent_path} is not executable"

def test_fuzz_equivalence():
    agent_path = "/home/user/uptime-analyzer-fixed"
    oracle_path = "/tests/uptime_oracle.py"

    assert os.path.isfile(oracle_path), f"Oracle script not found at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle script at {oracle_path} is not executable"

    random.seed(42)
    n_iterations = 1000

    for i in range(n_iterations):
        pings = random.randint(100, 100000)
        missed = random.randint(0, pings)
        server = generate_random_server_name()

        payload = {
            "server": server,
            "pings": pings,
            "missed": missed
        }
        json_str = json.dumps(payload)

        oracle_cmd = [oracle_path, json_str]
        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input: {json_str}\nStderr: {oracle_res.stderr}"
        oracle_output = oracle_res.stdout.strip()

        agent_cmd = [agent_path, json_str]
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent failed on input: {json_str}\nStderr: {agent_res.stderr}"
        agent_output = agent_res.stdout.strip()

        assert agent_output == oracle_output, (
            f"Mismatch on iteration {i+1}!\n"
            f"Input: {json_str}\n"
            f"Expected (Oracle): {oracle_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
