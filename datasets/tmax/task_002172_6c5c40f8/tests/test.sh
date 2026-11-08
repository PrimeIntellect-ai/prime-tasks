#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import json
import random
import string
import pytest

def test_fuzz_equivalence():
    agent_bin = "/home/user/api_handler/target/debug/api_processor"
    oracle_bin = "/tests/reference_oracle"

    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary is not executable at {agent_bin}"
    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.access(oracle_bin, os.X_OK), f"Oracle binary is not executable at {oracle_bin}"

    # Ensure the C module compiled correctly
    lib_path = "/home/user/c_module/libprocessor.so"
    assert os.path.isfile(lib_path), f"Shared library not found at {lib_path}"

    # Set LD_LIBRARY_PATH so the agent binary can find libprocessor.so
    env = os.environ.copy()
    env["LD_LIBRARY_PATH"] = "/home/user/c_module:" + env.get("LD_LIBRARY_PATH", "")

    random.seed(42)

    for i in range(1000):
        # Generate input
        rand_val = random.random()
        if rand_val < 0.1:
            # Invalid endpoint version
            input_json = json.dumps({"endpoint": "/api/v3/process", "payload": "abc123"})
        elif rand_val < 0.2:
            # Invalid JSON
            input_json = '{"endpoint": "/api/v4/process", "payload": "abc'
        else:
            # Valid JSON and endpoint
            length = random.randint(10, 100)
            payload = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
            input_json = json.dumps({"endpoint": "/api/v4/process", "payload": payload})

        # Run oracle
        oracle_proc = subprocess.run([oracle_bin, input_json], capture_output=True, text=True)
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run([agent_bin, input_json], env=env, capture_output=True, text=True)
        agent_out = agent_proc.stdout.strip()

        assert agent_out == oracle_out, (
            f"Output mismatch on input: {input_json}\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent): {agent_out}\n"
            f"Agent stderr: {agent_proc.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
