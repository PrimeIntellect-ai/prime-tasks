#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import time
import pytest

def generate_inputs(n):
    random.seed(42)
    lines = []
    for _ in range(n):
        ts = random.randint(1000000000, 1700000000)
        fmt = random.choice([0, 1, 2])
        if fmt == 0:
            ts_str = str(ts)
        elif fmt == 1:
            ts_str = time.strftime('%Y-%m-%dT%H:%M:%SZ', time.gmtime(ts))
        else:
            ts_str = time.strftime('%d/%b/%Y:%H:%M:%S +0000', time.gmtime(ts))

        user_len = random.randint(3, 10)
        user_chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_'
        user = ''.join(random.choices(user_chars, k=user_len))

        action_len = random.randint(3, 15)
        action_chars = 'abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ '
        action = ''.join(random.choices(action_chars, k=action_len)).strip()
        if not action:
            action = "DEFAULT ACTION"

        metric = random.randint(0, 9999)

        lines.append(f"[{ts_str}] User:{user} Action:{action} Metric:{metric}")
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/app/log_processor_legacy"
    agent_script = "/home/user/new_processor.py"

    assert os.path.exists(oracle_path), f"Oracle binary missing at {oracle_path}"
    assert os.path.exists(agent_script), f"Agent script missing at {agent_script}"

    input_data = generate_inputs(500)

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_path],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, f"Oracle failed: {oracle_proc.stderr}"
    oracle_output = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert agent_proc.returncode == 0, f"Agent script failed: {agent_proc.stderr}"
    agent_output = agent_proc.stdout

    oracle_lines = oracle_output.strip().split('\n')
    agent_lines = agent_output.strip().split('\n')

    assert len(oracle_lines) == len(agent_lines), \
        f"Output line count mismatch. Expected {len(oracle_lines)}, got {len(agent_lines)}"

    input_lines = input_data.strip().split('\n')

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert o_line == a_line, \
            f"Mismatch at line {i+1}:\nInput: {input_lines[i]}\nExpected: {o_line}\nGot: {a_line}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
