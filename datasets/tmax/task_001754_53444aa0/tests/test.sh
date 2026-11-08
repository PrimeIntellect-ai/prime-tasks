#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import base64
import subprocess
import pytest

def generate_arg1():
    roll = random.random()
    if roll < 0.25:
        # Valid base64, malicious payload
        malicious = random.choice(["<script>", "javascript:", "onerror="])
        prefix = "".join(random.choices(string.ascii_letters, k=random.randint(0, 20)))
        suffix = "".join(random.choices(string.ascii_letters, k=random.randint(0, 20)))
        payload = prefix + malicious + suffix
        return base64.b64encode(payload.encode()).decode()
    elif roll < 0.50:
        # Valid base64, benign payload
        payload = "".join(random.choices(string.ascii_letters + string.digits, k=random.randint(10, 50)))
        return base64.b64encode(payload.encode()).decode()
    else:
        # Invalid base64
        return "".join(random.choices(string.ascii_letters + string.digits + "!@#$%^&*", k=random.randint(10, 50)))

def generate_arg2():
    roll_prefix = random.random()
    if roll_prefix < 0.5:
        prefix = "/var/www/uploads/"
    else:
        prefix = "/var/www/other/"

    roll_dotdot = random.random()
    if roll_dotdot < 0.3:
        dotdot = "../"
    else:
        dotdot = ""

    suffix = "".join(random.choices(string.ascii_letters + string.digits + " _-", k=random.randint(5, 20)))
    return prefix + dotdot + suffix

def test_validator_fuzz_equivalence():
    agent_script = "/home/user/validator.sh"
    oracle_script = "/tests/oracle.sh"

    assert os.path.isfile(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.isfile(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)
    N = 500

    for i in range(N):
        arg1 = generate_arg1()
        arg2 = generate_arg2()

        oracle_cmd = ["bash", oracle_script, arg1, arg2]
        agent_cmd = ["bash", agent_script, arg1, arg2]

        oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True)
        agent_res = subprocess.run(agent_cmd, capture_output=True, text=True)

        oracle_out = oracle_res.stdout.strip()
        agent_out = agent_res.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input {i}:\n"
            f"arg1: {arg1!r}\n"
            f"arg2: {arg2!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
