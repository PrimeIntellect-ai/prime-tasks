#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

ORACLE_PATH = "/app/oracle_augment"
AGENT_PATH = "/home/user/spectral_augment.py"
FUZZ_ITERATIONS = 1000
INPUT_LENGTH = 4096

def test_spectral_augment_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable."
    assert os.path.isfile(ORACLE_PATH), f"Oracle {ORACLE_PATH} does not exist."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle {ORACLE_PATH} is not executable."

    random.seed(1337)

    for i in range(FUZZ_ITERATIONS):
        # Generate random bytes
        input_data = bytes(random.getrandbits(8) for _ in range(INPUT_LENGTH))

        # Run Oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            capture_output=True,
            timeout=5
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with stderr: {oracle_proc.stderr}"
        oracle_output = oracle_proc.stdout

        # Run Agent
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            capture_output=True,
            timeout=5
        )
        assert agent_proc.returncode == 0, f"Agent script failed on iteration {i} with stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
        agent_output = agent_proc.stdout

        assert oracle_output == agent_output, (
            f"Output mismatch on iteration {i}.\n"
            f"Input (hex): {input_data.hex()[:64]}...\n"
            f"Oracle output (hex): {oracle_output.hex()[:64]}...\n"
            f"Agent output (hex): {agent_output.hex()[:64]}..."
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
