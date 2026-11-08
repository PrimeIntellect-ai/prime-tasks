#!/bin/bash
set -e
mkdir -p /logs/verifier

chmod +x /tests/oracle_normalizer

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest

AGENT_SCRIPT = "/home/user/normalize.py"
ORACLE_BINARY = "/tests/oracle_normalizer"

def generate_fuzz_input():
    num_pairs = random.randint(1, 8)
    pairs = []
    for _ in range(num_pairs):
        key = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(1, 5)))
        if random.choice([True, False]):
            # alphanumeric value
            val = ''.join(random.choices(string.ascii_letters + string.digits, k=random.randint(1, 5)))
        else:
            # math expression
            op = random.choice(['+', '-', '*'])
            val = f"{random.randint(0, 999)}{op}{random.randint(0, 999)}"
        pairs.append(f"{key}={val}")
    return "&".join(pairs)

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_BINARY), f"Oracle binary {ORACLE_BINARY} is missing."
    assert os.access(ORACLE_BINARY, os.X_OK), f"Oracle binary {ORACLE_BINARY} is not executable."

    random.seed(42)
    inputs = [generate_fuzz_input() for _ in range(100)]

    for i, fuzz_input in enumerate(inputs):
        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [ORACLE_BINARY, fuzz_input],
                capture_output=True,
                text=True,
                timeout=2,
                check=True
            )
            oracle_out = oracle_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input {fuzz_input!r}: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {fuzz_input!r}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                ["/usr/bin/python3", AGENT_SCRIPT, fuzz_input],
                capture_output=True,
                text=True,
                timeout=2
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out on input {fuzz_input!r}")

        assert agent_proc.returncode == 0, (
            f"Agent script failed with return code {agent_proc.returncode} on input {fuzz_input!r}.\n"
            f"Stderr: {agent_proc.stderr.strip()}"
        )

        assert agent_out == oracle_out, (
            f"Mismatch on fuzz iteration {i+1}.\n"
            f"Input:  {fuzz_input!r}\n"
            f"Oracle: {oracle_out!r}\n"
            f"Agent:  {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
