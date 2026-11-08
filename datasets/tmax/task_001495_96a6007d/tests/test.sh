#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import subprocess
import random
import string
import pytest

def generate_fuzz_input(seed):
    random.seed(seed)
    lines = []
    for _ in range(1000):
        id_val = random.randint(1, 1000000)

        if lines and random.random() < 0.1:
            msg = lines[-1].split(' ', 1)[1]
        else:
            length = random.randint(5, 100)
            chars = string.ascii_letters + string.digits + string.punctuation + " \t\n"
            msg = "".join(random.choice(chars) for _ in range(length)).replace('\n', ' ')

        lines.append(f"{id_val} {msg}")
    return "\n".join(lines) + "\n"

def test_fuzz_equivalence():
    agent_executable = "/home/user/process_logs"
    oracle_executable = "/tests/oracle_process_logs"

    assert os.path.isfile(agent_executable), f"Agent executable not found at {agent_executable}"
    assert os.access(agent_executable, os.X_OK), f"Agent executable at {agent_executable} is not executable"

    assert os.path.isfile(oracle_executable), f"Oracle executable not found at {oracle_executable}"
    assert os.access(oracle_executable, os.X_OK), f"Oracle executable at {oracle_executable} is not executable"

    N = 100
    for i in range(N):
        fuzz_input = generate_fuzz_input(seed=42 + i)

        agent_proc = subprocess.run(
            [agent_executable],
            input=fuzz_input,
            text=True,
            capture_output=True
        )
        oracle_proc = subprocess.run(
            [oracle_executable],
            input=fuzz_input,
            text=True,
            capture_output=True
        )

        assert agent_proc.returncode == 0, f"Agent program failed on fuzz input {i} with return code {agent_proc.returncode}\nstderr: {agent_proc.stderr}"
        assert oracle_proc.returncode == 0, f"Oracle program failed on fuzz input {i} with return code {oracle_proc.returncode}"

        if agent_proc.stdout != oracle_proc.stdout:
            pytest.fail(
                f"Output mismatch on fuzz input {i}.\n"
                f"Input preview: {fuzz_input[:200]}...\n"
                f"Expected (Oracle) preview: {oracle_proc.stdout[:200]}...\n"
                f"Got (Agent) preview: {agent_proc.stdout[:200]}..."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
