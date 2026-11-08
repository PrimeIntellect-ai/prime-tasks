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

ORACLE_PATH = "/app/oracle_builder"
AGENT_PATH = "/home/user/doc_builder"
NUM_TESTS = 500

def generate_random_path():
    depth = random.randint(1, 5)
    segments = []
    for _ in range(depth):
        if random.random() < 0.1:
            segments.append(".")
        elif random.random() < 0.1:
            segments.append("..")
        else:
            length = random.randint(1, 10)
            chars = string.ascii_letters + string.digits + "_-"
            segments.append("".join(random.choice(chars) for _ in range(length)))

    path = "/".join(segments)
    if random.random() < 0.5:
        path = "/" + path
    return path

def generate_random_manifest():
    num_lines = random.randint(0, 200)
    lines = []
    for _ in range(num_lines):
        r = random.random()
        if r < 0.10:
            lines.append(" " * random.randint(0, 5))
        elif r < 0.30:
            lines.append(" " * random.randint(0, 3) + "# " + generate_random_path())
        elif r < 0.65:
            lines.append("+ " + generate_random_path())
        else:
            lines.append("- " + generate_random_path())
    return "\n".join(lines) + "\n"

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent file at {AGENT_PATH} is not executable"

def test_fuzz_equivalence():
    random.seed(42)

    for i in range(NUM_TESTS):
        manifest = generate_random_manifest()

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=manifest,
            text=True,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on test {i}"

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=manifest,
            text=True,
            capture_output=True
        )

        if agent_proc.returncode != 0 or agent_proc.stdout != oracle_proc.stdout:
            error_msg = f"Mismatch on fuzz test {i}!\n"
            error_msg += f"Input Manifest:\n{manifest}\n"
            error_msg += f"Oracle Output:\n{oracle_proc.stdout}\n"
            error_msg += f"Agent Output:\n{agent_proc.stdout}\n"
            if agent_proc.stderr:
                error_msg += f"Agent Stderr:\n{agent_proc.stderr}\n"
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
