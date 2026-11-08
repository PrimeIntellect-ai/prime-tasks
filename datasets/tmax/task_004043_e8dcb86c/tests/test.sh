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

ORACLE_PATH = "/tests/sanitizer_oracle"
AGENT_PATH = "/home/user/sanitizer"
N_RECORDS = 1000

def generate_username():
    length = random.randint(3, 10)
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_path():
    base_options = [
        "/mnt/storage",
        "/mnt/storage/logs",
        "/mnt/storage/data",
        "/mnt/other",
        "/etc",
        "/",
        "/var/log",
        "mnt/storage"
    ]

    components = [random.choice(base_options)]

    num_parts = random.randint(0, 5)
    for _ in range(num_parts):
        choice = random.choice(["..", ".", "dir1", "dir2", "subdir"])
        components.append(choice)

    filename = "file" + ''.join(random.choices(string.ascii_lowercase, k=4))
    ext = random.choice([".txt", ".log", ".tmp", ".csv", ""])
    components.append(filename + ext)

    return "/".join(components).replace("//", "/")

def generate_fuzz_input(n):
    random.seed(42)
    records = []
    for _ in range(n):
        user = generate_username()
        path = generate_path()
        record = f"RECORD START\nUser: {user}\nPath: {path}\nRECORD END\n"
        records.append(record)
    return "\n".join(records)

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent file at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle file at {ORACLE_PATH} is not executable"

    fuzz_input = generate_fuzz_input(N_RECORDS)

    oracle_proc = subprocess.run(
        [ORACLE_PATH],
        input=fuzz_input.encode('utf-8'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    oracle_out = oracle_proc.stdout.decode('utf-8')

    agent_proc = subprocess.run(
        [AGENT_PATH],
        input=fuzz_input.encode('utf-8'),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10
    )
    agent_out = agent_proc.stdout.decode('utf-8')

    oracle_lines = oracle_out.strip().split('\n')
    agent_lines = agent_out.strip().split('\n')

    # We compare line by line to give a clear error message
    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert o_line == a_line, (
            f"Mismatch at record {i + 1}.\n"
            f"Expected (Oracle): {o_line}\n"
            f"Got (Agent):       {a_line}\n"
        )

    assert len(oracle_lines) == len(agent_lines), (
        f"Output line count mismatch. Oracle produced {len(oracle_lines)} lines, "
        f"Agent produced {len(agent_lines)} lines."
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
