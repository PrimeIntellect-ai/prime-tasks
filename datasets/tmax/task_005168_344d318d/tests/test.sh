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

def generate_random_message():
    words = []
    for _ in range(random.randint(5, 20)):
        if random.random() < 0.1:
            words.append(f"user{random.randint(1,100)}@domain{random.randint(1,10)}.com")
        else:
            words.append(''.join(random.choices(string.ascii_lowercase, k=random.randint(3, 8))))
    return " ".join(words) + ("!" if random.random() < 0.5 else ".")

def generate_inputs(n=1000):
    random.seed(42)
    inputs = []
    for _ in range(n):
        if random.random() < 0.2:
            uid = random.choice([10, 42, 99, 100])
        else:
            uid = random.randint(1, 1000)

        msg = generate_random_message()
        ts = f"2023-10-01T12:{random.randint(10,59)}:{random.randint(10,59)}Z"

        inputs.append(json.dumps({
            "user_id": uid,
            "message": msg,
            "timestamp": ts
        }))
    return "\n".join(inputs) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_process_stream.py"
    agent_path = "/home/user/process_stream.py"

    assert os.path.isfile(agent_path), f"Agent script not found at {agent_path}"

    input_data = generate_inputs(1000)

    # Run oracle
    oracle_proc = subprocess.run(
        ["python3", oracle_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed to run. Did you fix and install the text_cleaner_lib package? Error: {oracle_proc.stderr}"

    # Run agent
    agent_proc = subprocess.run(
        ["python3", agent_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent script failed. Error: {agent_proc.stderr}"

    oracle_lines = [l for l in oracle_proc.stdout.strip().split('\n') if l]
    agent_lines = [l for l in agent_proc.stdout.strip().split('\n') if l]

    assert len(agent_lines) == len(oracle_lines), f"Expected {len(oracle_lines)} output lines, got {len(agent_lines)}."

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        try:
            o_json = json.loads(o_line)
        except Exception:
            pytest.fail(f"Oracle produced invalid JSON at line {i+1}: {o_line}")
        try:
            a_json = json.loads(a_line)
        except Exception:
            pytest.fail(f"Agent produced invalid JSON at line {i+1}: {a_line}")

        assert a_json == o_json, f"Mismatch at output line {i+1}.\nExpected: {o_json}\nGot: {a_json}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
