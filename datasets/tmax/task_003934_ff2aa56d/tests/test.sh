#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/process_gcode.py"
ORACLE_SCRIPT = "/tests/oracle.py"

def generate_gcode_line():
    commands = ['G1', 'G28', 'M104', 'M109', 'M140']
    cmd = random.choice(commands)

    parts = [cmd]

    if cmd == 'G1':
        if random.random() < 0.5:
            f_val = random.randint(1000, 5000)
            parts.append(f"F{f_val}")
    elif cmd == 'M104':
        if random.random() < 0.5:
            s_val = random.randint(100, 300)
            parts.append(f"S{s_val}")

    line = " ".join(parts)

    if random.random() < 0.3:
        comment = " " + ";" + "".join(random.choices("abcdefghijklmnopqrstuvwxyz ", k=random.randint(5, 15)))
        line += comment

    if random.random() < 0.5:
        line += " " * random.randint(1, 5)

    return line

def generate_gcode_input():
    num_lines = random.randint(10, 100)
    lines = [generate_gcode_line() for _ in range(num_lines)]
    for _ in range(random.randint(0, 5)):
        lines.insert(random.randint(0, len(lines)), " " * random.randint(0, 5))
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script {AGENT_SCRIPT} does not exist."
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script {AGENT_SCRIPT} is not executable."

    random.seed(42)

    for i in range(500):
        gcode_input = generate_gcode_input()

        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT],
            input=gcode_input,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_output = oracle_proc.stdout

        agent_proc = subprocess.run(
            [AGENT_SCRIPT],
            input=gcode_input,
            text=True,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed with return code {agent_proc.returncode} on input:\n{gcode_input}\nStderr:\n{agent_proc.stderr}")

        agent_output = agent_proc.stdout

        if agent_output != oracle_output:
            pytest.fail(
                f"Mismatch found on test case {i+1}!\n\n"
                f"Input:\n{gcode_input}\n\n"
                f"Expected (Oracle):\n{oracle_output}\n\n"
                f"Got (Agent):\n{agent_output}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
