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

ORACLE_PATH = "/tests/my_archiver"
AGENT_PATH = "/home/user/my_archiver"
N_ITERATIONS = 20

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(N_ITERATIONS):
        with tempfile.TemporaryDirectory() as tmpdir:
            num_files = random.randint(1, 20)
            paths = []
            for j in range(num_files):
                file_path = os.path.join(tmpdir, f"file_{j}.bin")
                size = random.randint(0, 256 * 1024)
                with open(file_path, "wb") as f:
                    f.write(os.urandom(size))
                paths.append(file_path)

            # Add some invalid paths
            num_invalid = random.randint(0, 5)
            for j in range(num_invalid):
                paths.append(os.path.join(tmpdir, f"invalid_{j}.bin"))

            random.shuffle(paths)

            input_data = "\n".join(paths) + "\n"
            input_bytes = input_data.encode("utf-8")

            oracle_proc = subprocess.run(
                [ORACLE_PATH],
                input=input_bytes,
                capture_output=True,
                timeout=10
            )
            assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i} with stderr: {oracle_proc.stderr.decode('utf-8', errors='replace')}"

            agent_proc = subprocess.run(
                [AGENT_PATH],
                input=input_bytes,
                capture_output=True,
                timeout=10
            )

            assert agent_proc.returncode == 0, f"Agent failed on iteration {i} with stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"

            if oracle_proc.stdout != agent_proc.stdout:
                pytest.fail(f"Output mismatch on iteration {i}.\nInput paths:\n{input_data}\nOracle output length: {len(oracle_proc.stdout)}\nAgent output length: {len(agent_proc.stdout)}")
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
