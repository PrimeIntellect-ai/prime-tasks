#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import random
import subprocess
import pytest

def test_fixed_analyzer_fuzz_equivalence():
    agent_script = "/home/user/fixed_analyzer.py"
    oracle_script = "/tests/oracle_analyzer.py"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)

    for i in range(100):
        length = random.randint(10, 500)
        # Generate floats in [-1.0, 1.0] with up to 6 decimal places
        floats = [round(random.uniform(-1.0, 1.0), 6) for _ in range(length)]
        input_str = ",".join(map(str, floats))

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [sys.executable, oracle_script],
                input=input_str,
                text=True,
                capture_output=True,
                check=True,
                timeout=5
            )
            oracle_out = oracle_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on iteration {i}")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on iteration {i} with error: {e.stderr}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [sys.executable, agent_script],
                input=input_str,
                text=True,
                capture_output=True,
                check=True,
                timeout=5
            )
            agent_out = agent_proc.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent script timed out (possible infinite loop/recursion) on iteration {i}. Input length: {length}.")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script crashed on iteration {i}. Error: {e.stderr}")

        assert agent_out == oracle_out, (
            f"Output mismatch on iteration {i}.\n"
            f"Input (first 100 chars): {input_str[:100]}...\n"
            f"Expected output (first 100 chars):\n{oracle_out[:100]}\n"
            f"Actual output (first 100 chars):\n{agent_out[:100]}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
