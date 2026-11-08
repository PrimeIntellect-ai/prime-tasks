#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_PROGRAM = "/home/user/billing_alert"
ORACLE_PROGRAM = "/tests/billing_alert_oracle.py"
REGIONS = ["US_EAST", "US_WEST", "EU_CENTRAL"]
N_TESTS = 100

def generate_fuzz_input():
    num_lines = random.randint(5, 50)
    lines = []
    for _ in range(num_lines):
        region = random.choice(REGIONS)
        hours = random.randint(1, 1000)
        lines.append(f"{region} {hours}")
    return "\n".join(lines) + "\n"

def test_agent_program_exists_and_executable():
    assert os.path.exists(AGENT_PROGRAM), f"Agent program not found at {AGENT_PROGRAM}"
    assert os.path.isfile(AGENT_PROGRAM), f"Agent program {AGENT_PROGRAM} is not a file"
    assert os.access(AGENT_PROGRAM, os.X_OK), f"Agent program {AGENT_PROGRAM} is not executable"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PROGRAM), f"Oracle program not found at {ORACLE_PROGRAM}"

    random.seed(42)  # Fixed seed for reproducibility

    for i in range(N_TESTS):
        test_input = generate_fuzz_input()

        # Run Oracle
        try:
            oracle_proc = subprocess.run(
                [ORACLE_PROGRAM],
                input=test_input,
                text=True,
                capture_output=True,
                check=True,
                timeout=5
            )
            oracle_output = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on test case {i+1}:\nInput:\n{test_input}\nError:\n{e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on test case {i+1}")

        # Run Agent
        try:
            agent_proc = subprocess.run(
                [AGENT_PROGRAM],
                input=test_input,
                text=True,
                capture_output=True,
                check=True,
                timeout=5
            )
            agent_output = agent_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent program failed on test case {i+1}:\nInput:\n{test_input}\nError:\n{e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on test case {i+1}")

        # Compare outputs
        assert agent_output == oracle_output, (
            f"Output mismatch on test case {i+1}.\n"
            f"Input:\n{test_input}\n"
            f"Expected (Oracle):\n{oracle_output}\n"
            f"Got (Agent):\n{agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
