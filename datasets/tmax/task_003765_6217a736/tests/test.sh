#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import subprocess
import pytest

def generate_path():
    length = random.randint(5, 20)
    # Ensure a mix of characters, including potential '..', '/', '\\'
    chars = string.ascii_letters + string.digits + ".／".replace("／", "/") + "\\"
    path = ''.join(random.choices(chars, k=length))
    # Occasionally force a '..' to ensure we hit the rejection logic often enough
    if random.random() < 0.3:
        insert_pos = random.randint(0, len(path))
        path = path[:insert_pos] + ".." + path[insert_pos:]
    return path

def generate_line():
    length = random.randint(0, 50)
    # Printable ASCII without newlines/carriage returns
    chars = string.printable.replace('\r', '').replace('\n', '')
    return ''.join(random.choices(chars, k=length))

def generate_input():
    lines = []
    num_blocks = random.randint(1, 10)
    for _ in range(num_blocks):
        # Junk lines before block
        for _ in range(random.randint(0, 3)):
            lines.append(generate_line())

        filepath = generate_path()
        lines.append(f"BEGIN FILE: {filepath}")

        # Content lines
        for _ in range(random.randint(0, 10)):
            lines.append(generate_line())

        lines.append("END FILE")

    # Junk lines after blocks
    for _ in range(random.randint(0, 3)):
        lines.append(generate_line())

    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_script = "/home/user/process_archive.sh"
    oracle_script = "/tests/oracle.sh"

    assert os.path.isfile(agent_script), f"Agent script {agent_script} does not exist."
    assert os.access(agent_script, os.X_OK), f"Agent script {agent_script} is not executable."
    assert os.path.isfile(oracle_script), f"Oracle script {oracle_script} does not exist."

    random.seed(42)

    for i in range(100):
        test_input = generate_input()

        agent_proc = subprocess.run(
            [agent_script],
            input=test_input.encode('utf-8'),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )
        oracle_proc = subprocess.run(
            ["bash", oracle_script],
            input=test_input.encode('utf-8'),
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE
        )

        agent_out = agent_proc.stdout.decode('utf-8')
        oracle_out = oracle_proc.stdout.decode('utf-8')

        if agent_out != oracle_out:
            pytest.fail(
                f"Output mismatch on random input #{i}.\n\n"
                f"--- INPUT ---\n{test_input}\n"
                f"--- EXPECTED OUTPUT (Oracle) ---\n{oracle_out}\n"
                f"--- ACTUAL OUTPUT (Agent) ---\n{agent_out}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
