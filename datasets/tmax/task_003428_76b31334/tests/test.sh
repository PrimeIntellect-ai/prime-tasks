#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

ORACLE_PATH = "/tests/oracle_analyzer"
AGENT_SCRIPT = "/home/user/sequence_analyzer.py"
N_FUZZ = 50

def generate_fuzz_inputs():
    random.seed(42)  # Fixed seed for reproducible fuzzing
    inputs = []
    for _ in range(N_FUZZ):
        length = random.randint(100, 500)
        seq = ''.join(random.choices(['A', 'C', 'G', 'T'], k=length))
        seed = random.randint(0, 10000)
        inputs.append((seq, str(seed)))
    return inputs

def test_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

@pytest.mark.parametrize("seq, seed", generate_fuzz_inputs())
def test_fuzz_equivalence(seq, seed):
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle not executable at {ORACLE_PATH}"

    # Run Oracle
    oracle_cmd = [ORACLE_PATH, seq, seed]
    oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
    assert oracle_res.returncode == 0, f"Oracle failed on input {seq[:20]}... {seed}\nStderr: {oracle_res.stderr}"
    oracle_output = oracle_res.stdout.strip()

    # Run Agent
    agent_cmd = ["python3", AGENT_SCRIPT, seq, seed]
    agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)
    assert agent_res.returncode == 0, f"Agent script failed on input {seq[:20]}... {seed}\nStderr: {agent_res.stderr}"
    agent_output = agent_res.stdout.strip()

    # Compare
    assert oracle_output == agent_output, (
        f"Mismatch on sequence length {len(seq)} (seed {seed}).\n"
        f"Sequence prefix: {seq[:50]}...\n"
        f"Expected (Oracle): '{oracle_output}'\n"
        f"Got (Agent): '{agent_output}'"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
