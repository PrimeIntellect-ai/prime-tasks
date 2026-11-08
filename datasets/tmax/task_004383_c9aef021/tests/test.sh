#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import pytest


def test_fuzz_equivalence():
    agent_bin = "/home/user/data_processor/processor"
    repo_dir = "/home/user/data_processor"

    if not os.path.isfile(agent_bin):
        try:
            subprocess.run(["make"], cwd=repo_dir, capture_output=True, check=True, text=True)
        except subprocess.CalledProcessError as e:
            pytest.fail(
                f"Agent binary {agent_bin} not found, and 'make' failed to build it.\n"
                f"Stdout: {e.stdout}\nStderr: {e.stderr}"
            )

    assert os.path.isfile(agent_bin), f"Agent binary {agent_bin} does not exist even after running make."
    assert os.access(agent_bin, os.X_OK), f"Agent binary {agent_bin} is not executable."

    random.seed(42)
    N = 500

    for _ in range(N):
        a = random.randint(-50, 100)
        b = random.randint(-50, 100)
        c = random.randint(-50, 100)
        args = [str(a), str(b), str(c)]

        agent_proc = subprocess.run(
            [agent_bin] + args,
            capture_output=True,
            text=True
        )

        if a < 0 or b < 0 or c < 0:
            expected_returncode = 2
            expected_stdout = ""
        else:
            expected_returncode = 0
            expected_stdout = f"{a * 13 + b * 7 - c * 3 + 42}\n"

        assert agent_proc.returncode == expected_returncode, (
            f"Exit code mismatch on input {args}.\n"
            f"Expected: {expected_returncode}\n"
            f"Got: {agent_proc.returncode}"
        )

        assert agent_proc.stdout == expected_stdout, (
            f"Stdout mismatch on input {args}.\n"
            f"Expected: {expected_stdout!r}\n"
            f"Got: {agent_proc.stdout!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
