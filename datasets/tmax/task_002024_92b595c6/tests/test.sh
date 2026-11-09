#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import string
import subprocess
import pytest

def generate_random_word(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length))

def generate_fuzz_input(n=5000, seed=42):
    random.seed(seed)
    lines = []
    for _ in range(n):
        target_length = random.randint(20, 200)
        words = []
        current_length = 0
        while current_length < target_length:
            word = generate_random_word(random.randint(3, 10))
            words.append(word)
            current_length += len(word) + 1

        line = ' '.join(words)[:target_length]

        if random.random() < 0.3:
            line += f" --password {generate_random_word(8)}"
        if random.random() < 0.3:
            line += f" Cookie: {generate_random_word(12)}"
        if random.random() < 0.3:
            line += f" Authorization: Bearer {generate_random_word(16)}"
        if random.random() < 0.3:
            line += " 8443"
        if random.random() < 0.3:
            line += " telemetry.internal.corp"

        line_parts = line.split()
        random.shuffle(line_parts)

        parts = []
        while sum(len(p) for p in parts) + len(parts) < target_length:
            parts.append(generate_random_word(random.randint(3, 10)))

        if random.random() < 0.3:
            parts.append(f"--password {generate_random_word(8)}")
        if random.random() < 0.3:
            parts.append(f"Cookie: {generate_random_word(12)}")
        if random.random() < 0.3:
            parts.append(f"Authorization: Bearer {generate_random_word(16)}")
        if random.random() < 0.3:
            parts.append("8443")
        if random.random() < 0.3:
            parts.append("telemetry.internal.corp")

        random.shuffle(parts)
        lines.append(' '.join(parts) + '\n')

    return ''.join(lines)

def test_redactor_exists():
    assert os.path.isfile("/home/user/redactor.py"), "/home/user/redactor.py is missing"

def test_fuzz_equivalence():
    agent_script = "/home/user/redactor.py"
    oracle_script = "/tests/oracle.py"

    assert os.path.isfile(agent_script), f"{agent_script} does not exist."
    assert os.path.isfile(oracle_script), f"{oracle_script} does not exist."

    input_data = generate_fuzz_input(n=5000, seed=1337)

    oracle_proc = subprocess.run(
        ["python3", oracle_script],
        input=input_data,
        text=True,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout

    agent_proc = subprocess.run(
        ["python3", agent_script],
        input=input_data,
        text=True,
        capture_output=True
    )

    assert agent_proc.returncode == 0, f"Agent script failed with error:\n{agent_proc.stderr}"
    agent_output = agent_proc.stdout

    oracle_lines = oracle_output.splitlines(keepends=True)
    agent_lines = agent_output.splitlines(keepends=True)

    if len(oracle_lines) != len(agent_lines):
        pass

    for i, (o_line, a_line) in enumerate(zip(oracle_lines, agent_lines)):
        assert o_line == a_line, (
            f"Mismatch at output line {i+1}.\n"
            f"Expected (Oracle): {repr(o_line)}\n"
            f"Got (Agent):       {repr(a_line)}\n"
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
