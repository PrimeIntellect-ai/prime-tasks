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
import sys
from datetime import datetime, timedelta

def generate_random_iso8601():
    start = datetime(2020, 1, 1)
    end = datetime(2024, 1, 1)
    delta = end - start
    random_seconds = random.randint(0, int(delta.total_seconds()))
    dt = start + timedelta(seconds=random_seconds)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def generate_unicode_string(length):
    chars = string.ascii_letters + string.digits + " !@#$%^&*()_+"
    # Add some complex unicode and surrogate pairs
    complex_chars = ["😀", "🚀", "こんにちは", "你好", "안녕하세요", "\\uD83D\\uDE00", "\\uD83D\\uDE80"]

    result = []
    for _ in range(length):
        if random.random() < 0.1:
            result.append(random.choice(complex_chars))
        else:
            result.append(random.choice(chars))
    return "".join(result)

def generate_json_lines(n):
    lines = []
    for _ in range(n):
        obj = {
            "timestamp": generate_random_iso8601(),
            "user_name": generate_unicode_string(random.randint(1, 50)),
            "message": generate_unicode_string(random.randint(10, 100))
        }
        if random.random() < 0.5:
            obj["extra_data"] = {
                "key1": generate_unicode_string(10),
                "key2": random.randint(1, 100)
            }

        # Dump to JSON but don't escape unicode, except for the manually added escapes
        line = json.dumps(obj, ensure_ascii=False)
        # Fix the double escaped manual surrogate pairs
        line = line.replace("\\\\u", "\\u")
        lines.append(line)
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_anonymizer"
    agent_path = "/home/user/anonymizer"

    assert os.path.exists(oracle_path), f"Oracle missing at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent binary missing at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent binary {agent_path} is not executable"

    random.seed(42)
    input_data = generate_json_lines(5000)

    # Run oracle from the verifier-only tests directory.
    oracle_proc = subprocess.run(
        [sys.executable, oracle_path],
        input=input_data.encode('utf-8'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with error: {oracle_proc.stderr.decode('utf-8')}"
    oracle_output = oracle_proc.stdout.decode('utf-8')

    # Run agent
    agent_proc = subprocess.run(
        [agent_path],
        input=input_data.encode('utf-8'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE
    )
    assert agent_proc.returncode == 0, f"Agent failed with error: {agent_proc.stderr.decode('utf-8')}"
    agent_output = agent_proc.stdout.decode('utf-8')

    # Compare
    oracle_lines = oracle_output.strip().split('\n')
    agent_lines = agent_output.strip().split('\n')

    assert len(oracle_lines) == len(agent_lines), f"Line count mismatch: Oracle={len(oracle_lines)}, Agent={len(agent_lines)}"

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        if o_line != a_line:
            input_line = input_data.strip().split('\n')[i]
            assert False, (
                f"Mismatch at line {i + 1}:\n"
                f"Input:  {input_line}\n"
                f"Oracle: {o_line}\n"
                f"Agent:  {a_line}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
