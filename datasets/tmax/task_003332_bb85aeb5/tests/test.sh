#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def test_fuzz_equivalence():
    oracle_path = "/app/suspicious_bin"
    agent_script = "/home/user/decoder.py"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"

    charset = "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789!@#$%^&*()"

    random.seed(42)

    for _ in range(200):
        length = random.randint(5, 128)
        test_input = "".join(random.choices(charset, k=length))

        oracle_cmd = [oracle_path, test_input]
        agent_cmd = ["python3", agent_script, test_input]

        try:
            oracle_res = subprocess.run(oracle_cmd, capture_output=True, text=True, check=True)
            oracle_out = oracle_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on input '{test_input}': {e.stderr}")

        try:
            agent_res = subprocess.run(agent_cmd, capture_output=True, text=True, check=True)
            agent_out = agent_res.stdout.strip()
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent script failed on input '{test_input}'.\nError: {e.stderr}")

        assert oracle_out == agent_out, (
            f"Output mismatch on input: '{test_input}'\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output:  {agent_out}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
