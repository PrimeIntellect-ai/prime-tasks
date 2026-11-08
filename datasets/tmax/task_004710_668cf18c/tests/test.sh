#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle_bin"
AGENT_PATH = "/home/user/fixed_processor"
NUM_TESTS = 500
MIN_LEN = 1024
MAX_LEN = 8192

def test_fixed_processor_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle {ORACLE_PATH} is not executable"

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_TESTS):
            input_len = random.randint(MIN_LEN, MAX_LEN)
            input_data = bytes(random.getrandbits(8) for _ in range(input_len))

            input_file = os.path.join(tmpdir, f"input_{i}.bin")
            with open(input_file, "wb") as f:
                f.write(input_data)

            oracle_proc = subprocess.run(
                [ORACLE_PATH, input_file],
                capture_output=True
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on input {i} of length {input_len}"
            oracle_out = oracle_proc.stdout

            agent_proc = subprocess.run(
                [AGENT_PATH, input_file],
                capture_output=True
            )

            if agent_proc.returncode != 0:
                pytest.fail(
                    f"Agent program crashed or failed (return code {agent_proc.returncode}) "
                    f"on random input {i} of length {input_len}."
                )

            agent_out = agent_proc.stdout

            if agent_out != oracle_out:
                pytest.fail(
                    f"Output mismatch on random input {i} of length {input_len}.\n"
                    f"Oracle output length: {len(oracle_out)}\n"
                    f"Agent output length: {len(agent_out)}\n"
                    f"Outputs differ."
                )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
