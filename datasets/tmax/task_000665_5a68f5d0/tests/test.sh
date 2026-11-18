#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_EXECUTABLE = "/home/user/spectro_cli/target/release/spectro_cli"
ORACLE_EXECUTABLE = "/tests/oracle_processor"
N_ITERATIONS = 500

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_EXECUTABLE), f"Agent executable not found at {AGENT_EXECUTABLE}"
    assert os.access(AGENT_EXECUTABLE, os.X_OK), f"Agent executable at {AGENT_EXECUTABLE} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_EXECUTABLE), f"Oracle executable not found at {ORACLE_EXECUTABLE}"
    assert os.access(ORACLE_EXECUTABLE, os.X_OK), f"Oracle executable at {ORACLE_EXECUTABLE} is not executable"

    random.seed(42)

    for i in range(N_ITERATIONS):
        # Generate random length between 1 and 200
        length = random.randint(1, 200)

        # Generate random floats between -1000.0 and 1000.0
        numbers = [random.uniform(-1000.0, 1000.0) for _ in range(length)]
        input_str = " ".join(f"{num:.6f}" for num in numbers) + "\n"

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [ORACLE_EXECUTABLE],
                input=input_str,
                text=True,
                capture_output=True,
                check=True,
                timeout=2
            )
            oracle_out = oracle_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i}. Input: {input_str}\nStderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on iteration {i}.")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [AGENT_EXECUTABLE],
                input=input_str,
                text=True,
                capture_output=True,
                check=True,
                timeout=2
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent executable failed on iteration {i}. Input: {input_str}\nStderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent executable timed out on iteration {i}.")

        # Compare outputs
        assert agent_out == oracle_out, (
            f"Mismatch on iteration {i}.\n"
            f"Input length: {length}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
