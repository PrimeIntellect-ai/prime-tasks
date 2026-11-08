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

def generate_csv_and_target(num_lines):
    nodes = ["ADMIN"] + ["".join(random.choices(string.ascii_uppercase, k=3)) for _ in range(20)]
    lines = []
    grantees = []
    for _ in range(num_lines):
        grantor = random.choice(nodes)
        grantee = random.choice(nodes)
        while grantee == grantor:
            grantee = random.choice(nodes)
        timestamp = random.randint(1, 10000)
        amount = random.randint(-50, 500)  # Include some <= 0 amounts to test filtering
        lines.append(f"{grantor},{grantee},{timestamp},{amount}")
        grantees.append(grantee)

    csv_data = "\n".join(lines) + "\n"
    target = random.choice(grantees) if grantees else "UNKNOWN"
    return csv_data, target

def test_new_auditor_exists_and_executable():
    script_path = "/home/user/new_auditor.sh"
    assert os.path.exists(script_path), f"The script {script_path} does not exist."
    assert os.path.isfile(script_path), f"The path {script_path} is not a file."
    assert os.access(script_path, os.X_OK), f"The script {script_path} is not executable."

def test_fuzz_equivalence():
    random.seed(42)
    oracle_path = "/app/legacy_auditor"
    agent_path = "/home/user/new_auditor.sh"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent script missing at {agent_path}"

    for i in range(50):
        num_lines = random.randint(10, 200)
        csv_data, target = generate_csv_and_target(num_lines)

        # Run oracle
        proc_oracle = subprocess.run(
            [oracle_path, target],
            input=csv_data,
            text=True,
            capture_output=True
        )
        oracle_out = proc_oracle.stdout

        # Run agent
        proc_agent = subprocess.run(
            ["/bin/bash", agent_path, target],
            input=csv_data,
            text=True,
            capture_output=True
        )
        agent_out = proc_agent.stdout

        assert oracle_out == agent_out, (
            f"Mismatch on test case {i+1} with target '{target}'.\n"
            f"Input CSV:\n{csv_data}\n"
            f"Oracle output:\n{oracle_out}\n"
            f"Agent output:\n{agent_out}\n"
            f"Oracle stderr:\n{proc_oracle.stderr}\n"
            f"Agent stderr:\n{proc_agent.stderr}\n"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
