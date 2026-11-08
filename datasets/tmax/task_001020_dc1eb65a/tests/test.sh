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

AGENT_SCRIPT = "/home/user/filter_backup.sh"
ORACLE_SCRIPT = "/tests/oracle.sh"

def generate_random_string(length):
    chars = string.ascii_letters + string.digits + " !@#$%^&*()_+-=[]{}|;:',.<>/?"
    return ''.join(random.choice(chars) for _ in range(length))

def generate_fuzz_input(num_lines=500, seed=42):
    random.seed(seed)
    lines = []
    for _ in range(num_lines):
        r = random.random()
        if r < 0.3:
            # Correctly formatted
            data_len = random.randint(1, 200)
            data = generate_random_string(data_len).replace('\n', '')
            lines.append(f"BKP7|{len(data)}|{data}")
        elif r < 0.6:
            # Wrong magic or wrong length
            data_len = random.randint(1, 200)
            data = generate_random_string(data_len).replace('\n', '')
            if random.random() < 0.5:
                magic = random.choice(["BKP8", "TEST", "BAD", "bkp7", ""])
                lines.append(f"{magic}|{len(data)}|{data}")
            else:
                wrong_len = len(data) + random.choice([-1, 1, 5, 10])
                lines.append(f"BKP7|{wrong_len}|{data}")
        else:
            # Malformed
            data = generate_random_string(random.randint(1, 200)).replace('\n', '')
            if random.random() < 0.3:
                data = data.replace('|', '')
            elif random.random() < 0.6:
                data = f"BKP7|not_a_number|{data}"
            lines.append(data)
    return "\n".join(lines) + "\n"

def test_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script {ORACLE_SCRIPT} is missing."

    input_data = generate_fuzz_input(num_lines=500, seed=1337)

    # Run oracle
    oracle_proc = subprocess.run(
        ["bash", ORACLE_SCRIPT],
        input=input_data,
        text=True,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        ["bash", AGENT_SCRIPT],
        input=input_data,
        text=True,
        capture_output=True
    )

    assert agent_proc.returncode == 0, f"Agent script failed with error: {agent_proc.stderr}"
    agent_output = agent_proc.stdout

    # Compare line by line to give a good error message
    oracle_lines = oracle_output.splitlines()
    agent_lines = agent_output.splitlines()
    input_lines = input_data.splitlines()

    assert len(oracle_lines) == len(agent_lines), f"Output line count mismatch: expected {len(oracle_lines)}, got {len(agent_lines)}"

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert o_line == a_line, (
            f"Mismatch at line {i+1}:\n"
            f"Input:    {input_lines[i]}\n"
            f"Expected: {o_line}\n"
            f"Got:      {a_line}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
