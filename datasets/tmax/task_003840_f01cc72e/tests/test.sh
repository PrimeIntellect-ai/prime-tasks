#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import string
import pytest

def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = []
    for _ in range(n):
        id_val = random.randint(1, 9999)

        # To ensure a good mix of inside and outside the range [-15.5, 84.2]
        # Let's pick values from -30.00 to 100.00
        val = round(random.uniform(-30.0, 100.0), 2)

        # The regex requires -?[0-9]{1,2}\.[0-9]{1,2}
        # So we format it carefully
        val_str = f"{val:.2f}"

        category = random.choice(string.ascii_uppercase)

        input_str = f"{id_val},{val_str},{category}"
        inputs.append(input_str)
    return inputs

def test_executable_exists():
    agent_executable = "/home/user/cleaner"
    assert os.path.isfile(agent_executable), f"Executable not found at {agent_executable}"
    assert os.access(agent_executable, os.X_OK), f"File at {agent_executable} is not executable"

def test_fuzz_equivalence():
    agent_executable = "/home/user/cleaner"
    oracle_executable = "/tests/cleaner_oracle"

    assert os.path.isfile(oracle_executable), f"Oracle not found at {oracle_executable}"
    assert os.path.isfile(agent_executable), f"Agent executable not found at {agent_executable}"

    inputs = generate_fuzz_inputs(1000)

    for input_str in inputs:
        # Run oracle
        oracle_proc = subprocess.run(
            [oracle_executable, input_str],
            capture_output=True,
            text=True
        )
        oracle_out = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [agent_executable, input_str],
            capture_output=True,
            text=True
        )
        agent_out = agent_proc.stdout

        assert oracle_out == agent_out, (
            f"Mismatch on input: '{input_str}'\n"
            f"Expected (Oracle): {repr(oracle_out)}\n"
            f"Got (Agent): {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
