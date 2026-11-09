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

def generate_valid_input():
    name_len = random.randint(3, 12)
    name = ''.join(random.choices(string.ascii_letters + string.digits + '_', k=name_len))
    port = random.randint(10, 99999)
    uid = random.randint(100, 9999)
    storage = random.randint(1, 9999)
    return f"{name} {port} {uid} {storage}"

def generate_invalid_input():
    choices = [
        "just_one_word",
        "two words",
        "three words here",
        "five words are in this string",
        "name not_int 100 100",
        "name 8080 not_int 100",
        "name 8080 100 not_int",
        "name 8080 100 100 extra",
    ]
    return random.choice(choices)

def test_setup_workers_script():
    script_path = "/home/user/setup_workers.sh"
    assert os.path.exists(script_path), f"Script {script_path} is missing."

    # Run the script
    result = subprocess.run(["bash", script_path], capture_output=True, text=True)
    assert result.returncode == 0, f"Script {script_path} failed to execute."

    # Check directories
    for i in range(1, 6):
        dir_path = f"/home/user/cicd/worker_{i}"
        assert os.path.isdir(dir_path), f"Directory {dir_path} was not created."

def test_fuzz_equivalence():
    oracle_path = "/app/legacy_net_quota.bin"
    agent_script = "/home/user/quota_router.py"

    assert os.path.exists(oracle_path), f"Oracle {oracle_path} is missing."
    assert os.path.exists(agent_script), f"Agent script {agent_script} is missing."

    random.seed(42)

    inputs = []
    for _ in range(160):
        inputs.append(generate_valid_input())
    for _ in range(40):
        inputs.append(generate_invalid_input())

    random.shuffle(inputs)

    for test_input in inputs:
        # Run oracle
        oracle_res = subprocess.run(
            [oracle_path, test_input],
            capture_output=True,
            text=True
        )

        # Run agent
        agent_res = subprocess.run(
            ["python3", agent_script, test_input],
            capture_output=True,
            text=True
        )

        assert oracle_res.returncode == agent_res.returncode, \
            f"Return code mismatch on input '{test_input}'. Oracle: {oracle_res.returncode}, Agent: {agent_res.returncode}"

        assert oracle_res.stdout == agent_res.stdout, \
            f"Stdout mismatch on input '{test_input}'.\nOracle:\n{oracle_res.stdout}\nAgent:\n{agent_res.stdout}"

        assert oracle_res.stderr == agent_res.stderr, \
            f"Stderr mismatch on input '{test_input}'.\nOracle:\n{oracle_res.stderr}\nAgent:\n{agent_res.stderr}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
