#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_analyzer"
    agent_path = "/home/user/analyzer/analyzer"

    assert os.path.exists(agent_path), f"Agent binary not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable"

    assert os.path.exists(oracle_path), f"Oracle binary not found at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle binary at {oracle_path} is not executable"

    random.seed(42)
    N = 1000
    min_ts = 1577854800
    max_ts = 1893474000

    for _ in range(N):
        ts = random.randint(min_ts, max_ts)
        ts_str = str(ts)

        oracle_res = subprocess.run([oracle_path, ts_str], capture_output=True, text=True)
        agent_res = subprocess.run([agent_path, ts_str], capture_output=True, text=True)

        assert oracle_res.returncode == 0, f"Oracle failed on input {ts_str}"
        assert agent_res.returncode == 0, f"Agent binary failed on input {ts_str}. Stderr: {agent_res.stderr.strip()}"

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, f"Mismatch on input {ts_str}. Expected (Oracle): {oracle_out}, Got (Agent): {agent_out}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
