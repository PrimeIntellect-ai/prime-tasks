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
import pytest

AGENT_BIN = "/home/user/loc_etl/target/release/loc_etl"
ORACLE_BIN = "/tests/reference_dedup"
N_TESTS = 200

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_random_unicode(length):
    # Generating printable unicode characters, simplified for robustness
    return ''.join(chr(random.randint(0x0020, 0x007E)) for _ in range(length))

def generate_input_data():
    num_lines = random.randint(10, 1000)
    keys_pool = [generate_random_string(random.randint(2, 10)) for _ in range(20)]
    langs_pool = [generate_random_string(random.randint(2, 10)) for _ in range(5)]

    lines = []
    for _ in range(num_lines):
        key = random.choice(keys_pool)
        lang = random.choice(langs_pool)
        timestamp = random.randint(-1000000, 1000000)

        text = generate_random_unicode(random.randint(5, 50))

        rand_val = random.random()
        if rand_val < 0.10:
            text += "\uFFFD"
        elif rand_val < 0.20:
            text += "REJECTED"

        record = {
            "timestamp": timestamp,
            "key": key,
            "lang": lang,
            "text": text
        }
        lines.append(json.dumps(record))

    return "\n".join(lines) + "\n"

def test_executable_exists():
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}. Did you build in release mode?"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable."

def test_fuzz_equivalence():
    random.seed(42)

    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"

    for i in range(N_TESTS):
        input_data = generate_input_data()

        # Run agent
        agent_proc = subprocess.run(
            [AGENT_BIN],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert agent_proc.returncode == 0, f"Agent program failed on run {i}:\n{agent_proc.stderr}"
        agent_out = agent_proc.stdout.strip()

        # Run oracle uploaded only at verification time
        oracle_proc = subprocess.run(
            [sys.executable, ORACLE_BIN],
            input=input_data,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle program failed on run {i}:\n{oracle_proc.stderr}"
        oracle_out = oracle_proc.stdout.strip()

        if agent_out != oracle_out:
            pytest.fail(
                f"Mismatch on run {i}.\n"
                f"Input data:\n{input_data[:500]}...\n"
                f"Expected output (Oracle):\n{oracle_out}\n\n"
                f"Actual output (Agent):\n{agent_out}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
