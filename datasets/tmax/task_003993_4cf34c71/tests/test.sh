#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/log_filter.sh"
ORACLE_SCRIPT = "/tests/log_filter_oracle.sh"

def generate_random_ip():
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"

def generate_csv_data(num_lines):
    services = ["billing-svc", "auth-daemon", "web-frontend", "db-worker"]
    lines = []
    for _ in range(num_lines):
        timestamp = random.randint(1600000000, 1700000000)
        service = random.choice(services)
        ip = generate_random_ip()
        response_time = random.randint(50, 800)
        lines.append(f"{timestamp},{service},{ip},{response_time}")
    return "\n".join(lines) + "\n"

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script missing at {ORACLE_SCRIPT}"

    random.seed(42)
    N = 500

    for i in range(N):
        num_lines = random.randint(1, 50)
        input_data = generate_csv_data(num_lines)

        oracle_proc = subprocess.run(
            ["bash", ORACLE_SCRIPT],
            input=input_data,
            text=True,
            capture_output=True
        )

        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=input_data,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == oracle_proc.returncode, (
            f"Run {i+1}: Exit code mismatch. "
            f"Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}\n"
            f"Input data:\n{input_data}"
        )

        assert agent_proc.stdout == oracle_proc.stdout, (
            f"Run {i+1}: Output mismatch.\n"
            f"Input data:\n{input_data}\n"
            f"Oracle output:\n{oracle_proc.stdout}\n"
            f"Agent output:\n{agent_proc.stdout}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
