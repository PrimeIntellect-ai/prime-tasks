#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import json
import random
import string
import subprocess
import os
import pytest

ORACLE_PATH = "/tests/oracle.py"
AGENT_PATH = "/home/user/process_loc.py"

def generate_random_string(length=10):
    chars = string.ascii_letters + string.digits + " Ã©Ã¨Ã§"
    return ''.join(random.choices(chars, k=length))

def generate_input():
    name = generate_random_string(random.randint(5, 15))
    num_keys = random.randint(1, 10)
    strings = {}
    for _ in range(num_keys):
        key_type = random.choice(["greeting", "error", "random"])
        if key_type == "random":
            key = ''.join(random.choices(string.ascii_letters, k=random.randint(5, 10)))
        else:
            key = key_type

        val_type = random.choice(["null", "string"])
        if val_type == "null":
            val = None
        else:
            val = generate_random_string(random.randint(5, 20))

        strings[key] = val

    return json.dumps({"name": name, "strings": strings})

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent script missing at {AGENT_PATH}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle script missing at {ORACLE_PATH}"

    random.seed(42)
    inputs = [generate_input() for _ in range(500)]

    for idx, input_json in enumerate(inputs):
        input_bytes = input_json.encode('utf-8')

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", ORACLE_PATH],
            input=input_bytes,
            capture_output=True,
            timeout=5
        )
        oracle_stdout = oracle_proc.stdout.decode('utf-8')
        oracle_stderr = oracle_proc.stderr.decode('utf-8')

        # Run agent
        agent_proc = subprocess.run(
            ["python3", AGENT_PATH],
            input=input_bytes,
            capture_output=True,
            timeout=5
        )
        agent_stdout = agent_proc.stdout.decode('utf-8')
        agent_stderr = agent_proc.stderr.decode('utf-8')

        assert agent_proc.returncode == 0, f"Agent script failed on input {idx}:\nInput: {input_json}\nStderr: {agent_stderr}"

        # Compare stdout (JSON equivalence)
        try:
            oracle_parsed = json.loads(oracle_stdout)
            agent_parsed = json.loads(agent_stdout)
            assert agent_parsed == oracle_parsed, f"JSON output mismatch on input {idx}:\nInput: {input_json}\nExpected: {oracle_stdout}\nGot: {agent_stdout}"
        except json.JSONDecodeError:
            assert oracle_stdout == agent_stdout, f"Stdout mismatch (non-JSON) on input {idx}:\nInput: {input_json}\nExpected: {oracle_stdout}\nGot: {agent_stdout}"

        # Compare stderr
        assert agent_stderr == oracle_stderr, f"Stderr mismatch on input {idx}:\nInput: {input_json}\nExpected: {oracle_stderr}\nGot: {agent_stderr}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
