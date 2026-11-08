#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/app/bin/oracle"
AGENT_PATH = "/app/recover"
NUM_TESTS = 200

def test_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Executable {AGENT_PATH} not found. Did you compile your code?"
    assert os.access(AGENT_PATH, os.X_OK), f"File {AGENT_PATH} is not executable."

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle binary {ORACLE_PATH} is missing."
    assert os.path.isfile(AGENT_PATH), f"Agent binary {AGENT_PATH} is missing."

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_TESTS):
            file_len = random.randint(64, 1024)
            data = bytes(random.getrandbits(8) for _ in range(file_len))

            test_file = os.path.join(tmpdir, f"test_input_{i}.bin")
            with open(test_file, "wb") as f:
                f.write(data)

            oracle_proc = subprocess.run([ORACLE_PATH, test_file], capture_output=True)
            agent_proc = subprocess.run([AGENT_PATH, test_file], capture_output=True)

            assert oracle_proc.returncode == agent_proc.returncode, (
                f"Return code mismatch on random input {i} (length {file_len} bytes). "
                f"Oracle returned {oracle_proc.returncode}, your program returned {agent_proc.returncode}."
            )

            assert oracle_proc.stdout == agent_proc.stdout, (
                f"Output mismatch on random input {i} (length {file_len} bytes). "
                f"Oracle output length: {len(oracle_proc.stdout)}, your output length: {len(agent_proc.stdout)}."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
