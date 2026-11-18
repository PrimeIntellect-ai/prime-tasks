#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

ORACLE = "/app/legacy_audit"
AGENT = "/home/user/audit_rewrite"
N = 10000

def generate_random_input():
    length = random.randint(0, 1000)
    # Avoid null bytes as they terminate command line arguments in C
    b = bytearray(random.randint(1, 255) for _ in range(length))

    # Inject specific substrings occasionally
    if random.random() < 0.1 and length >= 4:
        idx = random.randint(0, length - 4)
        b[idx:idx+4] = b"CSP:"
    if random.random() < 0.1 and length >= 6:
        idx = random.randint(0, length - 6)
        b[idx:idx+6] = b"Secure"
    if random.random() < 0.1 and length >= 8:
        idx = random.randint(0, length - 8)
        b[idx:idx+8] = b"Port: 80"
    if random.random() < 0.1 and length >= 4:
        idx = random.randint(0, length - 4)
        b[idx:idx+4] = b"0600"

    return bytes(b)

def test_agent_executable_exists():
    """Test that the rewritten audit binary exists and is executable."""
    assert os.path.exists(AGENT), f"Agent executable not found at {AGENT}"
    assert os.access(AGENT, os.X_OK), f"Agent executable {AGENT} is not executable"

def test_fuzz_equivalence():
    """Fuzz both binaries with random inputs and assert identical behavior."""
    random.seed(42)
    inputs = [generate_random_input() for _ in range(N)]
    # Ensure edge cases are explicitly covered
    inputs[0] = b""
    inputs[1] = b"A" * 1024
    inputs[2] = b"A" * 1050

    oracle_b = ORACLE.encode('utf-8')
    agent_b = AGENT.encode('utf-8')

    for i, inp in enumerate(inputs):
        # Run oracle
        oracle_proc = subprocess.run([oracle_b, inp], capture_output=True)
        # Run agent
        agent_proc = subprocess.run([agent_b, inp], capture_output=True)

        assert oracle_proc.returncode == agent_proc.returncode, \
            f"Return code mismatch on input length {len(inp)}: oracle={oracle_proc.returncode}, agent={agent_proc.returncode}"
        assert oracle_proc.stdout == agent_proc.stdout, \
            f"Stdout mismatch on input length {len(inp)}:\nOracle: {oracle_proc.stdout}\nAgent: {agent_proc.stdout}"
        assert oracle_proc.stderr == agent_proc.stderr, \
            f"Stderr mismatch on input length {len(inp)}:\nOracle: {oracle_proc.stderr}\nAgent: {agent_proc.stderr}"

def test_no_args_equivalence():
    """Test that both binaries behave identically when no arguments are provided."""
    oracle_proc = subprocess.run([ORACLE], capture_output=True)
    agent_proc = subprocess.run([AGENT], capture_output=True)

    assert oracle_proc.returncode == agent_proc.returncode, "Return code mismatch on no arguments"
    assert oracle_proc.stdout == agent_proc.stdout, "Stdout mismatch on no arguments"
    assert oracle_proc.stderr == agent_proc.stderr, "Stderr mismatch on no arguments"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
