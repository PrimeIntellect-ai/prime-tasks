#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import random
import subprocess
import pytest

def test_fuzz_equivalence():
    oracle_path = "/app/ticket_8831/process_oracle"
    agent_script = "/home/user/ticket_8831/process_signal.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.access(oracle_path, os.X_OK), f"Oracle not executable at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    random.seed(42)
    N = 1000

    for i in range(N):
        length = random.randint(1, 2048)
        # Ensure the specific edge case mentioned in the voicemail is tested
        if i == 0:
            length = 1024

        data = [random.uniform(-100.0, 100.0) for _ in range(length)]
        threshold = random.uniform(-50.0, 50.0)

        arg1 = json.dumps(data)
        arg2 = str(threshold)

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_path, arg1, arg2],
                capture_output=True,
                text=True,
                timeout=5
            )
            oracle_out = oracle_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail("Oracle timed out")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [sys.executable, agent_script, arg1, arg2],
                capture_output=True,
                text=True,
                timeout=5
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail("Agent script timed out")

        assert agent_proc.returncode == 0, f"Agent script failed with return code {agent_proc.returncode}. Stderr: {agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle failed with return code {oracle_proc.returncode}. Stderr: {oracle_proc.stderr}"

        if agent_out != oracle_out:
            pytest.fail(
                f"Output mismatch on fuzz iteration {i}.\n"
                f"Input length: {length}, Threshold: {threshold}\n"
                f"Oracle output (truncated): {oracle_out[:200]}...\n"
                f"Agent output (truncated): {agent_out[:200]}..."
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
