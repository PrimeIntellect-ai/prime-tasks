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

def generate_inputs(n=10000, seed=42):
    random.seed(seed)
    lines = []
    for _ in range(n):
        choice = random.randint(0, 2)
        if choice == 0:
            # Single semantic version
            if random.random() < 0.8:
                lines.append(f"{random.randint(0, 50)}.{random.randint(0, 50)}.{random.randint(0, 50)}")
            else:
                # Invalid semver format
                lines.append(f"{random.randint(0, 50)}.{random.randint(0, 50)}")
        elif choice == 1:
            # Migration syntax
            if random.random() < 0.8:
                # Valid spacing
                lines.append(f"{random.randint(0, 50)}.{random.randint(0, 50)}.{random.randint(0, 50)} -> {random.randint(0, 50)}.{random.randint(0, 50)}.{random.randint(0, 50)}")
            else:
                # Invalid spacing
                lines.append(f"{random.randint(0, 50)}.{random.randint(0, 50)}.{random.randint(0, 50)}->{random.randint(0, 50)}.{random.randint(0, 50)}.{random.randint(0, 50)}")
        else:
            # Random ASCII noise
            length = random.randint(1, 20)
            chars = string.ascii_letters + string.digits + string.punctuation + " "
            lines.append(''.join(random.choices(chars, k=length)))
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/app/schema_migrator"
    agent_path = "/home/user/migrator_rebuilt.py"

    assert os.path.exists(oracle_path), f"Oracle binary {oracle_path} does not exist."
    assert os.path.exists(agent_path), f"Agent script {agent_path} does not exist. Did you create it?"

    input_data = generate_inputs(n=10000, seed=1337)

    oracle_proc = subprocess.run(
        [oracle_path], 
        input=input_data, 
        text=True, 
        capture_output=True
    )

    agent_proc = subprocess.run(
        ["python3", agent_path], 
        input=input_data, 
        text=True, 
        capture_output=True
    )

    assert oracle_proc.returncode == 0, f"Oracle failed with return code {oracle_proc.returncode}"

    oracle_out = oracle_proc.stdout.splitlines()
    agent_out = agent_proc.stdout.splitlines()

    input_lines = input_data.splitlines()

    assert len(oracle_out) == len(input_lines), "Oracle did not output exactly one line per input line."
    assert len(agent_out) == len(input_lines), f"Agent output {len(agent_out)} lines, expected {len(input_lines)}."

    for i, (o_line, a_line) in enumerate(zip(oracle_out, agent_out)):
        assert o_line == a_line, (
            f"Mismatch at line {i+1}!\n"
            f"Input:  {repr(input_lines[i])}\n"
            f"Oracle: {repr(o_line)}\n"
            f"Agent:  {repr(a_line)}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
