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

ORACLE_PATH = "/app/rogue_auth.elf"
AGENT_SCRIPT = "/home/user/token_generator.py"
N_ITERATIONS = 5000

def generate_random_username():
    length = random.randint(4, 20)
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_random_url():
    length = random.randint(10, 50)
    scheme = random.choice(["http://", "https://"])
    domain_len = random.randint(5, 15)
    domain = ''.join(random.choices(string.ascii_lowercase, k=domain_len)) + ".com"
    path_len = length - len(scheme) - len(domain)
    if path_len > 1:
        path = "/" + ''.join(random.choices(string.ascii_letters + string.digits + "/_-", k=path_len - 1))
    else:
        path = ""
    return scheme + domain + path

def test_token_generator_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_PATH), f"Oracle binary not found at {ORACLE_PATH}"

    random.seed(42)

    for i in range(N_ITERATIONS):
        username = generate_random_username()
        url = generate_random_url()

        # Run oracle
        try:
            oracle_result = subprocess.run(
                [ORACLE_PATH, username, url],
                capture_output=True,
                text=True,
                check=True
            )
            oracle_output = oracle_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input ({username}, {url}): {e.stderr}")

        # Run agent
        try:
            agent_result = subprocess.run(
                ["python3", AGENT_SCRIPT, username, url],
                capture_output=True,
                text=True,
                check=True
            )
            agent_output = agent_result.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input ({username}, {url}): {e.stderr}")

        assert oracle_output == agent_output, (
            f"Mismatch on iteration {i+1}:\n"
            f"Username: {username}\n"
            f"URL: {url}\n"
            f"Oracle output: {oracle_output}\n"
            f"Agent output:  {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
