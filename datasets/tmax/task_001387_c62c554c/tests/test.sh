#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_archiver_fuzz_equivalence():
    agent_script = "/home/user/archiver.py"
    oracle_bin = "/app/oracle_archiver"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_bin), f"Oracle binary not found at {oracle_bin}"

    # Generate N=100 random inputs
    random.seed(42)
    N = 100

    for i in range(N):
        length = random.randint(0, 8192)
        input_data = bytes(random.getrandbits(8) for _ in range(length))

        # Run Oracle
        oracle_proc = subprocess.run(
            [oracle_bin],
            input=input_data,
            capture_output=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {i} (length {length})"
        oracle_out = oracle_proc.stdout

        # Run Agent
        agent_proc = subprocess.run(
            ["python3", agent_script],
            input=input_data,
            capture_output=True,
            check=False
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed (returncode {agent_proc.returncode}) on input {i} (length {length}). Stderr: {agent_proc.stderr.decode(errors='replace')}")

        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on input {i} (length {length}).\n"
                f"Oracle output length: {len(oracle_out)}\n"
                f"Agent output length: {len(agent_out)}\n"
                f"First 50 bytes of oracle: {oracle_out[:50].hex()}\n"
                f"First 50 bytes of agent: {agent_out[:50].hex()}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
