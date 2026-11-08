#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import pytest

def test_agent_script_exists_and_executable():
    agent_path = "/home/user/run_report.sh"
    assert os.path.isfile(agent_path), f"Agent script {agent_path} does not exist."
    assert os.access(agent_path, os.X_OK), f"Agent script {agent_path} is not executable."

def test_mo_fixed():
    mo_path = "/app/mo-3.0.2/mo"
    assert os.path.isfile(mo_path), f"mo script {mo_path} does not exist."
    with open(mo_path, 'r') as f:
        content = f.read()

    # Ensure the perturbation is fixed by checking for an uncommented shopt -s extglob
    lines = content.split('\n')
    found_uncommented = any(line.strip() == "shopt -s extglob" for line in lines)
    assert found_uncommented, f"Could not find uncommented 'shopt -s extglob' in {mo_path}."

def test_fuzz_equivalence():
    oracle_path = "/tests/run_report_oracle.sh"
    agent_path = "/home/user/run_report.sh"

    assert os.path.isfile(oracle_path), f"Oracle script {oracle_path} does not exist."
    assert os.access(oracle_path, os.X_OK), f"Oracle script {oracle_path} is not executable."

    random.seed(42)
    test_inputs = [random.randint(1, 1000) for _ in range(50)]

    for user_id in test_inputs:
        str_user_id = str(user_id)

        oracle_proc = subprocess.run([oracle_path, str_user_id], capture_output=True, text=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on input {str_user_id}:\n{oracle_proc.stderr}"

        agent_proc = subprocess.run([agent_path, str_user_id], capture_output=True, text=True)
        assert agent_proc.returncode == 0, f"Agent script failed on input {str_user_id}:\n{agent_proc.stderr}"

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Mismatch on input {str_user_id}.\n"
            f"Oracle output:\n{oracle_proc.stdout}\n"
            f"Agent output:\n{agent_proc.stdout}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
