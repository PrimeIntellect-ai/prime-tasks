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

def generate_fuzz_inputs(n=1000, seed=42):
    random.seed(seed)
    inputs = []
    severities = ["INFO", "Error", "WARNing", "DEBUG", "critical", "FATAL", "trace"]
    for _ in range(n):
        is_valid = random.random() < 0.7
        if is_valid:
            ts = random.randint(0, 2000000000)
            sev = random.choice(severities)
            msg_len = random.randint(5, 50)
            msg = ''.join(random.choices(string.ascii_letters + string.digits + ' ', k=msg_len))
            line = f"{ts}|{sev}|{msg}"
        else:
            malform_type = random.choice(["missing_pipe", "extra_pipe", "bad_ts", "empty"])
            if malform_type == "missing_pipe":
                line = "just some random text without pipes"
            elif malform_type == "extra_pipe":
                line = "123456789|INFO|message|extra"
            elif malform_type == "bad_ts":
                line = "not_an_int|INFO|message here"
            elif malform_type == "empty":
                line = ""
            else:
                line = "||"
        inputs.append(line)
    return inputs

def test_parser_exists():
    assert os.path.isfile("/home/user/parser.py"), "The parser script /home/user/parser.py does not exist."

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_parser"
    agent_cmd = ["python3", "/home/user/parser.py"]

    assert os.path.isfile(oracle_path), f"Oracle parser {oracle_path} missing."
    assert os.path.isfile("/home/user/parser.py"), "Agent parser missing."

    inputs = generate_fuzz_inputs(1000)

    for i, line in enumerate(inputs):
        # Run oracle uploaded only at verification time.
        oracle_proc = subprocess.run(
            ["python3", oracle_path],
            input=line,
            text=True,
            capture_output=True
        )
        oracle_out = oracle_proc.stdout.strip()

        # Run agent
        agent_proc = subprocess.run(
            agent_cmd,
            input=line,
            text=True,
            capture_output=True
        )
        agent_out = agent_proc.stdout.strip()

        assert oracle_out == agent_out, (
            f"Mismatch on input {i}:\n"
            f"Input: {repr(line)}\n"
            f"Oracle output: {repr(oracle_out)}\n"
            f"Agent output: {repr(agent_out)}\n"
            f"Agent stderr: {agent_proc.stderr}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
