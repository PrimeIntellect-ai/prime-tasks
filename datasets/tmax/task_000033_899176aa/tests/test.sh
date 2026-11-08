#!/bin/bash
set -e
mkdir -p /logs/verifier
chmod +x /tests/oracle_decompressor

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

ORACLE_PATH = "/tests/oracle_decompressor"
AGENT_PATH = "/home/user/decompressor"
NUM_ITERATIONS = 1000  # scaled down slightly from 10,000 to ensure test completes within reasonable time limits, while still providing strong fuzzing
MIN_LEN = 100
MAX_LEN = 500000

def test_agent_binary_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"

def generate_random_input(seed, length):
    rng = random.Random(seed)
    # Ensure even length for pairs
    if length % 2 != 0:
        length += 1
    return bytearray(rng.getrandbits(8) for _ in range(length))

@pytest.mark.parametrize("seed", range(NUM_ITERATIONS))
def test_fuzz_equivalence(seed):
    # Determine length for this iteration
    rng = random.Random(seed + 10000)
    length = rng.randint(MIN_LEN, MAX_LEN)

    # To speed up fuzzing, we use smaller lengths mostly, and a few large ones
    if seed > 50:
        length = rng.randint(100, 1000)

    input_data = generate_random_input(seed, length)

    # Run oracle
    try:
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            capture_output=True,
            timeout=2,
            check=False
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Oracle timed out on seed {seed}")

    # Run agent
    try:
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            capture_output=True,
            timeout=2,
            check=False
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Agent timed out on seed {seed}")

    # Compare return codes
    assert oracle_proc.returncode == agent_proc.returncode, \
        f"Return code mismatch on seed {seed}. Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"

    # Compare stdout
    if oracle_proc.stdout != agent_proc.stdout:
        # Truncate output for display if it's too long
        oracle_out = oracle_proc.stdout[:100]
        agent_out = agent_proc.stdout[:100]
        pytest.fail(f"Output mismatch on seed {seed} (len {length}).\nOracle (first 100 bytes): {oracle_out}\nAgent (first 100 bytes): {agent_out}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
