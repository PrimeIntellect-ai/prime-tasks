#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/tests/legacy_encoder_oracle"
AGENT_SCRIPT = "/home/user/encoder.py"
N_ITERATIONS = 10000

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script is missing at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle binary not executable: {ORACLE_PATH}"

    # Printable ASCII from 0x20 to 0x7E
    charset = [chr(i) for i in range(0x20, 0x7F)]

    # We use a fixed seed for reproducibility
    rng = random.Random(42)

    # To avoid excessive test times, we'll do 1000 iterations instead of 10000 if 10000 takes too long,
    # but the prompt requested N=10000. We will do 10000 as requested.
    for i in range(N_ITERATIONS):
        length = rng.randint(5, 1024)
        test_input = "".join(rng.choices(charset, k=length))
        input_bytes = test_input.encode('ascii')

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_bytes,
            capture_output=True,
            timeout=5
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"

        # Run agent
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_bytes,
            capture_output=True,
            timeout=5
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed with exit code {agent_proc.returncode} on iteration {i}.\nInput: {test_input!r}\nStderr: {agent_proc.stderr.decode(errors='replace')}")

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on iteration {i}!\n"
                f"Input length: {length}\n"
                f"Input (repr): {test_input!r}\n"
                f"Oracle output: {oracle_out!r}\n"
                f"Agent output: {agent_out!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
