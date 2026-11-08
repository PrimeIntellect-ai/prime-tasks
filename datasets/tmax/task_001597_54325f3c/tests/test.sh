#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import pytest

def test_reconstruct_script_exists():
    """Verify that the agent's script exists."""
    script_path = "/home/user/reconstruct.py"
    assert os.path.isfile(script_path), f"Missing agent script at {script_path}"

def test_fuzz_equivalence():
    """
    Fuzz-equivalence verifier:
    Generate 100 random alphanumeric strings of length 16 to 64.
    Run both the oracle and the agent's script on each string.
    Assert exact bit-for-bit output match.
    """
    oracle_path = "/app/payload_encoder"
    agent_script = "/home/user/reconstruct.py"

    assert os.path.isfile(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.isfile(agent_script), f"Agent script missing at {agent_script}"

    # Fixed seed for reproducible fuzzing
    random.seed(42)
    charset = string.ascii_letters + string.digits

    for _ in range(100):
        length = random.randint(16, 64)
        fuzz_input = ''.join(random.choices(charset, k=length))

        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_path, fuzz_input],
            capture_output=True,
            text=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle failed unexpectedly on input '{fuzz_input}'"
        oracle_out = oracle_proc.stdout.strip()

        # Run agent script
        agent_proc = subprocess.run(
            ['python3', agent_script, fuzz_input],
            capture_output=True,
            text=True,
            check=False
        )

        assert agent_proc.returncode == 0, (
            f"Agent script crashed on input '{fuzz_input}'.\n"
            f"Stderr: {agent_proc.stderr.strip()}"
        )

        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch on input '{fuzz_input}'\n"
            f"Expected (Oracle): {oracle_out}\n"
            f"Got (Agent):       {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
