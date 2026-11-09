#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import random
import string
import subprocess
import pytest

def generate_random_email():
    length = random.randint(5, 64)
    chars = string.ascii_letters + string.digits + "._-"
    # Ensure exactly one '@'
    if length < 2:
        return "@"
    at_pos = random.randint(1, length - 2)
    res = []
    for i in range(length):
        if i == at_pos:
            res.append('@')
        else:
            res.append(random.choice(chars))
    return "".join(res)

def test_router_fuzz_equivalence():
    agent_script = "/home/user/router.py"
    oracle_bin = "/app/email_router_bin"

    assert os.path.exists(agent_script), f"Agent script {agent_script} does not exist."
    assert os.path.exists(oracle_bin), f"Oracle binary {oracle_bin} does not exist."

    random.seed(42)
    emails = [generate_random_email() for _ in range(1000)]

    for email in emails:
        # Run oracle
        oracle_res = subprocess.run([oracle_bin, email], capture_output=True, text=True)
        assert oracle_res.returncode == 0, f"Oracle failed on input: {email}"
        oracle_out = oracle_res.stdout

        # Run agent
        agent_res = subprocess.run([sys.executable, agent_script, email], capture_output=True, text=True)
        assert agent_res.returncode == 0, f"Agent script failed on input: {email}\nStderr: {agent_res.stderr}"
        agent_out = agent_res.stdout

        assert oracle_out == agent_out, (
            f"Output mismatch on input '{email}'.\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output:  {repr(agent_out)}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
