#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

def generate_random_date():
    y = random.randint(1990, 2025)
    m = random.randint(1, 12)
    d = random.randint(1, 28)
    return f"{y:04d}-{m:02d}-{d:02d}"

def generate_random_filename():
    ext = random.choice(['.txt', '.log', '.dat', '.bin', '.csv', ''])
    name = ''.join(random.choices(string.ascii_lowercase, k=random.randint(3, 8)))
    return name + ext

def generate_random_path():
    p = random.random()
    if p < 0.20:
        # Deep nested valid paths
        parts = [''.join(random.choices(string.ascii_lowercase, k=4)) for _ in range(random.randint(2, 5))]
        parts.append(generate_random_filename())
        return "/".join(parts)
    elif p < 0.60:
        # Malicious paths escaping root
        parts = [".."] * random.randint(1, 4)
        parts.extend([''.join(random.choices(string.ascii_lowercase, k=4)) for _ in range(random.randint(0, 2))])
        parts.append(generate_random_filename())
        return "/".join(parts)
    elif p < 0.90:
        # Complex obfuscated escapes
        parts = []
        for _ in range(random.randint(3, 8)):
            c = random.choice(['..', '.', ''.join(random.choices(string.ascii_lowercase, k=3))])
            parts.append(c)
        parts.append(generate_random_filename())
        return "/".join(parts)
    else:
        # Absolute paths
        parts = ['', ''.join(random.choices(string.ascii_lowercase, k=4)), generate_random_filename()]
        return "/".join(parts)

def generate_record():
    filepath = generate_random_path()
    size = random.randint(100, 1000000)
    date = generate_random_date()
    return f"File: {filepath}\nSize: {size}\nDate: {date}\n---"

def generate_input():
    num_records = random.randint(1, 50)
    records = [generate_record() for _ in range(num_records)]
    return "\n".join(records) + "\n"

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_sanitizer"
    agent_path = "/home/user/sanitizer/target/release/sanitizer"

    assert os.path.exists(oracle_path), f"Test oracle not found at {oracle_path}."
    assert os.access(oracle_path, os.X_OK), f"Test oracle at {oracle_path} is not executable."
    assert os.path.exists(agent_path), f"Agent binary not found at {agent_path}. Did you compile it in release mode?"
    assert os.access(agent_path, os.X_OK), f"Agent binary at {agent_path} is not executable."

    random.seed(42)
    n_iterations = 500

    for i in range(n_iterations):
        inp = generate_input()

        oracle_proc = subprocess.run([oracle_path], input=inp, text=True, capture_output=True)
        agent_proc = subprocess.run([agent_path], input=inp, text=True, capture_output=True)

        assert oracle_proc.returncode == 0, f"Oracle failed on input:\n{inp}\nStderr: {oracle_proc.stderr}"

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent failed (exit code {agent_proc.returncode}) on input:\n{inp}\nStderr:\n{agent_proc.stderr}")

        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Output mismatch on iteration {i+1}.\n\n"
                f"Input:\n{inp}\n"
                f"Expected Output (Oracle):\n{oracle_proc.stdout}\n"
                f"Actual Output (Agent):\n{agent_proc.stdout}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
