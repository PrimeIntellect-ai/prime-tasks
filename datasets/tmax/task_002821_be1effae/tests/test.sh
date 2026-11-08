#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def generate_test_case():
    V = random.randint(10, 1000)
    E = random.randint(10, 5000)

    lines = [f"{V} {E}"]
    for _ in range(E):
        u = random.randint(0, V - 1)
        v = random.randint(0, V - 1)
        lines.append(f"{u} {v}")

    Q = random.randint(1, 100)
    lines.append(str(Q))
    for _ in range(Q):
        start = random.randint(0, V - 1)
        end = random.randint(0, V - 1)
        lines.append(f"{start} {end}")

    return "\n".join(lines) + "\n"

def test_executable_exists():
    agent_exe = "/home/user/graph_validator"
    assert os.path.isfile(agent_exe), f"Agent executable not found at {agent_exe}"
    assert os.access(agent_exe, os.X_OK), f"Agent executable at {agent_exe} is not executable"

def test_fuzz_equivalence():
    oracle_exe = "/tests/graph_validator_oracle"
    agent_exe = "/home/user/graph_validator"

    assert os.path.isfile(oracle_exe), f"Oracle executable not found at {oracle_exe}"
    assert os.path.isfile(agent_exe), f"Agent executable not found at {agent_exe}"

    random.seed(42)
    N = 500

    for i in range(N):
        input_data = generate_test_case()

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                [oracle_exe],
                input=input_data,
                text=True,
                capture_output=True,
                check=True,
                timeout=5
            )
            oracle_out = oracle_proc.stdout
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle failed on test case {i}. This should not happen. Stderr: {e.stderr}")
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on test case {i}. This should not happen.")

        # Run agent
        try:
            agent_proc = subprocess.run(
                [agent_exe],
                input=input_data,
                text=True,
                capture_output=True,
                timeout=5
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent executable timed out on test case {i}")

        assert agent_proc.returncode == 0, f"Agent executable failed with return code {agent_proc.returncode} on test case {i}\nStderr: {agent_proc.stderr}"

        if oracle_out != agent_proc.stdout:
            # Truncate for display if too long
            display_input = input_data if len(input_data) < 500 else input_data[:500] + "\n...[truncated]"
            display_oracle = oracle_out if len(oracle_out) < 500 else oracle_out[:500] + "\n...[truncated]"
            display_agent = agent_proc.stdout if len(agent_proc.stdout) < 500 else agent_proc.stdout[:500] + "\n...[truncated]"

            pytest.fail(
                f"Mismatch on test case {i}.\n"
                f"Input:\n{display_input}\n\n"
                f"Oracle output:\n{display_oracle}\n\n"
                f"Agent output:\n{display_agent}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
