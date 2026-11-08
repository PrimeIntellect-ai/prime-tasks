#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

AGENT_SCRIPT = "/home/user/fw_check"
ORACLE_SCRIPT = "/tests/oracle_fw_check"
NUM_TESTS = 2000

def generate_random_ip():
    return f"{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}"

def generate_edge_case_ip():
    return random.choice([
        '256.0.0.1', '172.16.10.5', '192.168.5.10', '192.168.5.20', 'abc', '', '172.16.20.255',
        '172.16.10.0', '172.16.10.255', '192.168.5.0', '192.168.5.15', '192.168.5.16'
    ])

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} is missing."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    random.seed(42)
    services = ['frontend', 'backend', 'database', 'cache', 'admin', 'frontend ', '', 'DROP']

    for _ in range(NUM_TESTS):
        service = random.choice(services)
        if random.random() < 0.5:
            ip = generate_random_ip()
        else:
            ip = generate_edge_case_ip()

        args = [service, ip]

        # Some tests with wrong number of arguments
        if random.random() < 0.05:
            args = [service]
        elif random.random() < 0.05:
            args = [service, ip, "extra"]

        oracle_cmd = [ORACLE_SCRIPT] + args
        agent_cmd = [AGENT_SCRIPT] + args

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Output mismatch for args {args}.\n"
            f"Oracle: {oracle_out!r}\n"
            f"Agent: {agent_out!r}\n"
            f"Agent stderr: {agent_res.stderr!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
