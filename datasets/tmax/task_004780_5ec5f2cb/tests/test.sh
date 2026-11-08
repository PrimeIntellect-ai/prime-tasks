#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import pytest

ORACLE_PATH = "/app/audit_filter"
AGENT_SCRIPT = "/home/user/filter.sh"

def generate_random_ip():
    return f"{random.randint(1, 255)}.{random.randint(0, 255)}.{random.randint(0, 255)}.{random.randint(1, 254)}"

def generate_random_cmd():
    length = random.randint(5, 30)
    cmd = ''.join(random.choices(string.ascii_letters + string.digits, k=length))
    keywords = ["password=", "token=", "/etc/shadow", "/etc/passwd", "--config", "admin"]
    if random.random() < 0.3:
        cmd += " " + random.choice(keywords) + ''.join(random.choices(string.ascii_letters, k=5))
    return cmd

def generate_test_input(num_lines):
    lines = []
    for _ in range(num_lines):
        ts = random.randint(1600000000, 1700000000)
        ip = generate_random_ip()
        uid = random.choices([0, random.randint(1, 2000)], weights=[0.4, 0.6])[0]
        pid = random.randint(1, 65535)
        cmd = generate_random_cmd()
        lines.append(f"{ts},{ip},{uid},{pid},{cmd}")
    return "\n".join(lines) + "\n"

def test_agent_script_exists_and_executable():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

def test_fuzz_equivalence():
    random.seed(42)
    N = 1000  # Number of fuzzing iterations

    for i in range(N):
        num_lines = random.randint(10, 50)
        test_input = generate_test_input(num_lines)

        oracle_proc = subprocess.run([ORACLE_PATH], input=test_input, text=True, capture_output=True)
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"

        agent_proc = subprocess.run([AGENT_SCRIPT], input=test_input, text=True, capture_output=True)

        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Mismatch on iteration {i}.\n"
                f"Input:\n{test_input}\n"
                f"Oracle Output:\n{oracle_proc.stdout}\n"
                f"Agent Output:\n{agent_proc.stdout}\n"
                f"Agent Stderr:\n{agent_proc.stderr}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
