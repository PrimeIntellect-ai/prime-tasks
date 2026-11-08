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

ORACLE_PATH = "/tests/oracle.sh"
AGENT_SCRIPT = "/home/user/process_journal.sh"
NUM_ITERATIONS = 200
SALT = 8392
MODULUS = 9973

def generate_fuzz_input(num_lines):
    lines = []
    actions = ["ADD", "SUB", "MUL"]
    for _ in range(num_lines):
        action = random.choice(actions)
        value = random.randint(1, 1000)

        is_valid = random.random() < 0.70
        if is_valid:
            checksum = (value * SALT) % MODULUS
        else:
            checksum = random.randint(0, 10000)
            # Ensure it's strictly invalid
            if checksum == (value * SALT) % MODULUS:
                checksum += 1

        lines.append(f"{action} {value} {checksum}")
    return "\n".join(lines) + "\n"

def test_process_journal_exists_and_executable():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle script {ORACLE_PATH} missing."

    random.seed(42)

    for i in range(NUM_ITERATIONS):
        num_lines = random.randint(10, 500)
        input_data = generate_fuzz_input(num_lines)

        with tempfile.NamedTemporaryFile(mode='w', delete=False) as tmp:
            tmp.write(input_data)
            tmp_path = tmp.name

        try:
            oracle_cmd = ["bash", ORACLE_PATH, tmp_path]
            agent_cmd = ["bash", AGENT_SCRIPT, tmp_path]

            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, timeout=5)
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, timeout=5)

            assert oracle_res.returncode == 0, f"Oracle failed on iteration {i}"

            oracle_out = oracle_res.stdout.strip()
            agent_out = agent_res.stdout.strip()

            if oracle_out != agent_out:
                error_msg = (
                    f"Mismatch on iteration {i}.\n"
                    f"Input file lines: {num_lines}\n"
                    f"Oracle output: {oracle_out}\n"
                    f"Agent output: {agent_out}\n"
                    f"Input head (up to 5 lines):\n"
                    f"{''.join(input_data.splitlines(True)[:5])}"
                )
                pytest.fail(error_msg)
        finally:
            os.remove(tmp_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
