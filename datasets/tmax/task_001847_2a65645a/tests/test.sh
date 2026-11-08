#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import filecmp
import glob
import os
import random
import string
import subprocess

ORACLE_PATH = "/app/renamer_utility"


def get_agent_executable():
    candidates = glob.glob("/home/user/new_renamer*")
    executables = [c for c in candidates if os.path.isfile(c) and os.access(c, os.X_OK)]
    assert executables, "Could not find any executable matching /home/user/new_renamer*"

    if "/home/user/new_renamer" in executables:
        return "/home/user/new_renamer"
    return executables[0]


def generate_random_filename(length):
    chars = string.ascii_letters + string.digits + "_-."
    return ''.join(random.choice(chars) for _ in range(length))


def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"

    agent_path = get_agent_executable()
    assert not os.path.samefile(agent_path, ORACLE_PATH), "Submission is the legacy utility"
    assert not filecmp.cmp(agent_path, ORACLE_PATH, shallow=False), \
        "Submission is byte-identical to the legacy utility"

    random.seed(42)
    cases = []
    for _ in range(1000):
        length = random.randint(5, 50)
        input_str = generate_random_filename(length)
        if random.random() < 0.2:
            input_str = input_str.replace('_', ' ')

        oracle_proc = subprocess.run(
            [ORACLE_PATH, input_str],
            capture_output=True,
            text=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input: {input_str!r}"
        cases.append((input_str, oracle_proc.stdout.strip()))

    # The agent was allowed to inspect the legacy utility while solving the task,
    # but its submitted program must not delegate execution to that utility.
    os.unlink(ORACLE_PATH)
    assert not os.path.exists(ORACLE_PATH), "Failed to remove oracle before running submission"

    for input_str, oracle_out in cases:
        agent_proc = subprocess.run(
            [agent_path, input_str],
            capture_output=True,
            text=True
        )
        agent_out = agent_proc.stdout.strip()

        assert agent_proc.returncode == 0, (
            f"Agent failed on input: {input_str!r}. Error: {agent_proc.stderr}"
        )
        assert agent_out == oracle_out, (
            f"Mismatch on input: {input_str!r}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output:  {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
