#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

def generate_random_path(length):
    alphabet = string.ascii_letters + string.digits + "_-"
    components = []
    current_len = 0
    while current_len < length:
        comp_len = random.randint(1, 10)
        comp = ''.join(random.choices(alphabet, k=comp_len))
        # Introduce relative path components randomly
        if random.random() < 0.15:
            comp = random.choice(["..", "."])
        # Introduce target keywords randomly
        if random.random() < 0.1:
            comp = "qemu"
        elif random.random() < 0.1:
            comp = "cicd"
        components.append(comp)
        current_len += len(comp) + 1

    path = "/".join(components)
    if random.random() < 0.5:
        path = "/" + path
    return path[:length]

def test_allocate_script_exists_and_executable():
    """Ensure the agent's script exists and is executable."""
    path = "/home/user/allocate.sh"
    assert os.path.isfile(path), f"Missing agent script at {path}"
    assert os.access(path, os.X_OK), f"Agent script at {path} is not executable"

def test_fuzz_equivalence():
    """Fuzz both the oracle and the agent's script to ensure outputs match exactly."""
    oracle_path = "/tests/oracle_allocate"
    agent_path = "/home/user/allocate.sh"

    assert os.path.isfile(oracle_path), f"Oracle script missing at {oracle_path}"

    random.seed(42)

    for _ in range(500):
        length = random.randint(5, 256)
        test_path = generate_random_path(length)

        oracle_cmd = ["/bin/bash", oracle_path, test_path]
        agent_cmd = ["/bin/bash", agent_path, test_path]

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True)
            oracle_out = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            oracle_out = e.stdout.strip()

        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, check=True)
            agent_out = agent_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            agent_out = e.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input path: '{test_path}'\n"
            f"Oracle output: '{oracle_out}'\n"
            f"Agent output:  '{agent_out}'"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
