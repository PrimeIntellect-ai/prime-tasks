#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_decoder_exists_and_executable():
    """Verify that the agent compiled the decoder program to the correct path and it's executable."""
    agent_bin = "/home/user/decoder"
    assert os.path.exists(agent_bin), f"Agent binary {agent_bin} does not exist."
    assert os.path.isfile(agent_bin), f"{agent_bin} is not a file."
    assert os.access(agent_bin, os.X_OK), f"{agent_bin} is not executable."

def test_decoder_fuzz_equivalence():
    """Fuzz test the agent's decoder against the oracle decoder."""
    agent_bin = "/home/user/decoder"
    oracle_bin = "/tests/oracle_decoder"

    assert os.path.exists(oracle_bin), f"Oracle binary {oracle_bin} missing."

    random.seed(42)
    hex_chars = "0123456789ABCDEF"

    for i in range(5000):
        # Even length between 4 and 128
        length = random.choice(range(4, 129, 2))
        hex_input = "".join(random.choice(hex_chars) for _ in range(length))

        # Run oracle
        try:
            oracle_result = subprocess.run(
                [oracle_bin, hex_input],
                capture_output=True,
                timeout=2,
                check=False
            )
            oracle_stdout = oracle_result.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input: {hex_input}")

        # Run agent
        try:
            agent_result = subprocess.run(
                [agent_bin, hex_input],
                capture_output=True,
                timeout=2,
                check=False
            )
            agent_stdout = agent_result.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent binary timed out on input: {hex_input}")

        assert agent_stdout == oracle_stdout, (
            f"Output mismatch on input {hex_input}\n"
            f"Expected (Oracle): {oracle_stdout!r}\n"
            f"Got (Agent): {agent_stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
