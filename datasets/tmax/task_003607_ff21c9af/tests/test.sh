#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def test_fixed_query_exists():
    path = "/home/user/fixed_query.py"
    assert os.path.isfile(path), f"Agent's script is missing: {path}"

def test_fuzz_equivalence():
    agent_script = "/home/user/fixed_query.py"

    assert os.path.isfile(agent_script), f"Agent's script is missing: {agent_script}"

    # Generate 1000 random 32-bit unsigned integers
    random.seed(42)
    test_inputs = [random.randint(0, 4294967295) for _ in range(1000)]

    for val in test_inputs:
        val_str = str(val)
        expected_output = str(((val ^ 0xA589325B) + 1354) & 0xFFFFFFFF)

        try:
            agent_res = subprocess.run(
                ["python3", agent_script, val_str],
                capture_output=True,
                text=True,
                check=True,
                timeout=2
            )
            agent_output = agent_res.stdout.strip()
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent's script timed out on input {val_str}")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent's script failed on input {val_str} with error: {e.stderr}")

        assert agent_output == expected_output, (
            f"Mismatch on input {val_str}.\n"
            f"Expected: {expected_output}\n"
            f"Got (Agent): {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
