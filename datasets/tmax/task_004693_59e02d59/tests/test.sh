#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import string
import subprocess
import pytest

def test_config_exists():
    config_path = '/app/tokenizer/config.json'
    assert os.path.exists(config_path), f"Config file {config_path} is missing."
    with open(config_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Config file {config_path} is not valid JSON.")

    assert data.get("max_length") == 50, "Config max_length is not 50."
    assert data.get("strip_punctuation") is True, "Config strip_punctuation is not true."

def test_fuzz_equivalence():
    oracle_path = '/tests/oracle_infer.py'
    agent_path = '/home/user/infer.py'

    assert os.path.exists(oracle_path), f"Oracle program {oracle_path} missing."
    assert os.path.exists(agent_path), f"Agent program {agent_path} missing."
    assert os.access(agent_path, os.X_OK), f"Agent program {agent_path} is not executable."

    random.seed(42)
    # Add extra spaces and punctuation to test the tokenizer and logic well
    chars = string.ascii_letters + string.digits + " " * 10 + string.punctuation

    for i in range(500):
        length = random.randint(5, 200)
        test_str = "".join(random.choice(chars) for _ in range(length))

        oracle_proc = subprocess.run(['python3', oracle_path, test_str], capture_output=True, text=True)
        agent_proc = subprocess.run([agent_path, test_str], capture_output=True, text=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on input: {repr(test_str)}"
        assert agent_proc.returncode == 0, f"Agent failed on input: {repr(test_str)}\nError: {agent_proc.stderr}"

        oracle_out = oracle_proc.stdout.strip()
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input: {repr(test_str)}\n"
            f"Oracle output: {oracle_out}\n"
            f"Agent output: {agent_out}"
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
