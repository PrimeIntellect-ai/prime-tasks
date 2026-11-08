#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_fuzz_input(num_lines=10000, seed=42):
    random.seed(seed)
    lines = []

    for _ in range(num_lines):
        seq_id = random.randint(1, 999999)

        op_roll = random.random()
        if op_roll < 0.475:
            op = "EXTRACT"
        elif op_roll < 0.95:
            op = "REMOVE"
        else:
            op = random.choice(["INVALID", "FOO", "BAR", "123"])

        path_len = random.randint(1, 20)
        path_parts = []
        for _ in range(path_len):
            part_roll = random.random()
            if part_roll < 0.3:
                path_parts.append("..")
            elif part_roll < 0.5:
                path_parts.append(".")
            elif part_roll < 0.6:
                path_parts.append("") # will create //
            else:
                path_parts.append(random.choice(["a", "b", "c", "dir", "file.txt"]))

        raw_path = "/".join(path_parts)
        if random.random() < 0.2:
            raw_path = "/" + raw_path

        # Introduce some malformed lines
        if random.random() < 0.01:
            lines.append(f"{seq_id} {op}")
        else:
            lines.append(f"{seq_id} {op} {raw_path}")

    return "\n".join(lines) + "\n"

def test_agent_binary_exists():
    agent_bin = "/home/user/log_sanitizer/target/release/sanitizer"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"
    assert os.access(agent_bin, os.X_OK), f"Agent binary at {agent_bin} is not executable"

def test_fuzz_equivalence():
    agent_bin = "/home/user/log_sanitizer/target/release/sanitizer"
    oracle_bin = "/tests/reference_sanitizer"

    assert os.path.isfile(oracle_bin), f"Oracle binary not found at {oracle_bin}"
    assert os.path.isfile(agent_bin), f"Agent binary not found at {agent_bin}"

    fuzz_input = generate_fuzz_input(10000, seed=1337)
    input_bytes = fuzz_input.encode('utf-8')

    # Run oracle
    oracle_proc = subprocess.run(
        [oracle_bin],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert oracle_proc.returncode == 0, f"Oracle failed with code {oracle_proc.returncode}\nStderr: {oracle_proc.stderr.decode()}"
    oracle_out = oracle_proc.stdout.decode('utf-8')

    # Run agent
    agent_proc = subprocess.run(
        [agent_bin],
        input=input_bytes,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    assert agent_proc.returncode == 0, f"Agent failed with code {agent_proc.returncode}\nStderr: {agent_proc.stderr.decode()}"
    agent_out = agent_proc.stdout.decode('utf-8')

    oracle_lines = oracle_out.splitlines()
    agent_lines = agent_out.splitlines()

    assert len(oracle_lines) == len(agent_lines), f"Output line count mismatch: Oracle={len(oracle_lines)}, Agent={len(agent_lines)}"

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert o_line == a_line, (
            f"Mismatch at output line {i+1}:\n"
            f"Oracle: {o_line}\n"
            f"Agent:  {a_line}\n"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
