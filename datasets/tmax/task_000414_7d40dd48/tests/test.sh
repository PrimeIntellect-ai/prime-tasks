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

AGENT_SCRIPT = "/home/user/generate_token.py"
ORACLE_SCRIPT = "/tests/oracle_token.py"
NUM_TESTS = 1000

def generate_random_string(min_len=3, max_len=15, force_db_prefix=False):
    length = random.randint(min_len, max_len)
    chars = string.ascii_letters + string.digits
    if force_db_prefix:
        length = max(3, length)
        return "db" + ''.join(random.choice(chars) for _ in range(length - 2))
    return ''.join(random.choice(chars) for _ in range(length))

def generate_test_cases(n):
    random.seed(42)
    cases = []
    for _ in range(n):
        # 20% chance to force "db" prefix to ensure that branch is well-tested
        force_db = random.random() < 0.2
        service_name = generate_random_string(force_db_prefix=force_db)
        timestamp = str(random.randint(10000, 99999))
        cases.append((service_name, timestamp))
    return cases

def test_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    test_cases = generate_test_cases(NUM_TESTS)

    for service_name, timestamp in test_cases:
        # Run Oracle
        oracle_cmd = ["python3", ORACLE_SCRIPT, service_name, timestamp]
        oracle_result = subprocess.run(oracle_cmd, capture_output=True, text=True)
        assert oracle_result.returncode == 0, f"Oracle failed on input {service_name} {timestamp}"
        oracle_output = oracle_result.stdout.strip()

        # Run Agent
        agent_cmd = ["python3", AGENT_SCRIPT, service_name, timestamp]
        agent_result = subprocess.run(agent_cmd, capture_output=True, text=True)

        if agent_result.returncode != 0:
            pytest.fail(f"Agent script failed (return code {agent_result.returncode}) on input:\n"
                        f"SERVICE_NAME: {service_name}\nTIMESTAMP: {timestamp}\n"
                        f"Stderr: {agent_result.stderr.strip()}")

        agent_output = agent_result.stdout.strip()

        if agent_output != oracle_output:
            pytest.fail(f"Mismatch found!\n"
                        f"Input SERVICE_NAME: {service_name}\n"
                        f"Input TIMESTAMP: {timestamp}\n"
                        f"Expected (Oracle): {oracle_output}\n"
                        f"Got (Agent): {agent_output}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
