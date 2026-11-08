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

ORACLE_PATH = "/tests/reference_process_logs.sh"
AGENT_PATH = "/home/user/process_logs_fixed.sh"
N_TESTS = 500

def generate_input():
    actions = ["LOGIN", "LOGOUT", "UPLOAD", "DOWNLOAD"]
    num_lines = random.randint(100, 10000)
    lines = []
    for _ in range(num_lines):
        uid_len = random.randint(5, 10)
        uid = ''.join(random.choices(string.ascii_letters + string.digits, k=uid_len))
        action = random.choice(actions)
        lines.append(f"{uid} {action}")
    return "\n".join(lines) + "\n"

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_PATH), f"Agent script {AGENT_PATH} does not exist."
    assert os.access(AGENT_PATH, os.X_OK), f"Agent script {AGENT_PATH} is not executable."

def test_fuzz_equivalence():
    random.seed(42)

    assert os.path.isfile(ORACLE_PATH), f"Oracle script {ORACLE_PATH} missing."
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle script {ORACLE_PATH} not executable."

    for i in range(N_TESTS):
        input_data = generate_input()

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            text=True,
            capture_output=True
        )

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert oracle_proc.returncode == agent_proc.returncode, (
            f"Return code mismatch on test {i}.\n"
            f"Oracle: {oracle_proc.returncode}\n"
            f"Agent: {agent_proc.returncode}\n"
            f"Oracle stderr: {oracle_proc.stderr}\n"
            f"Agent stderr: {agent_proc.stderr}\n"
            f"Input preview (first 5 lines):\n"
            f"{chr(10).join(input_data.splitlines()[:5])}"
        )

        assert oracle_proc.stdout == agent_proc.stdout, (
            f"Output mismatch on test {i}.\n"
            f"Oracle output:\n{oracle_proc.stdout}\n"
            f"Agent output:\n{agent_proc.stdout}\n"
            f"Input preview (first 5 lines):\n"
            f"{chr(10).join(input_data.splitlines()[:5])}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
