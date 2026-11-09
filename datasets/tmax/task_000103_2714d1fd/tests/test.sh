#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

def generate_input(seed):
    random.seed(seed)
    C = random.randint(5, 50)
    L = random.randint(150, 1000)
    lines = [f"{C} {L}"]
    for _ in range(C):
        chain = [str(random.randint(-1000, 1000)) for _ in range(L)]
        lines.append(" ".join(chain))
    return "\n".join(lines) + "\n"

def test_trace_processor_fuzz_equivalence():
    agent_executable = "/home/user/trace_processor"
    oracle_executable = "/tests/oracle_processor"

    assert os.path.isfile(agent_executable), f"Agent executable missing: {agent_executable}"
    assert os.access(agent_executable, os.X_OK), f"Agent executable is not executable: {agent_executable}"
    assert os.path.isfile(oracle_executable), f"Oracle executable missing: {oracle_executable}"
    assert os.access(oracle_executable, os.X_OK), f"Oracle executable is not executable: {oracle_executable}"

    num_iterations = 100
    for i in range(num_iterations):
        input_data = generate_input(seed=42+i)

        oracle_proc = subprocess.run(
            [oracle_executable],
            input=input_data,
            text=True,
            capture_output=True,
            check=True
        )
        oracle_output = oracle_proc.stdout.strip()

        try:
            agent_proc = subprocess.run(
                [agent_executable],
                input=input_data,
                text=True,
                capture_output=True,
                timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent program timed out on iteration {i+1}")

        assert agent_proc.returncode == 0, f"Agent program failed with return code {agent_proc.returncode}\nStderr: {agent_proc.stderr}"

        agent_output = agent_proc.stdout.strip()

        if oracle_output != agent_output:
            pytest.fail(
                f"Mismatch on iteration {i+1}\n"
                f"Oracle output: {oracle_output}\n"
                f"Agent output: {agent_output}\n"
                f"Input dimensions (C L): {input_data.split(maxsplit=2)[:2]}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
