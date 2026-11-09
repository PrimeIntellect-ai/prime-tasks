#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_fuzz_input(seed):
    random.seed(seed)
    N = random.randint(10, 100)
    M = random.randint(N, N * 5)

    input_lines = [f"{N} {M}"]

    for _ in range(M):
        u = random.randint(0, N - 1)
        v = random.randint(0, N - 1)
        w = random.randint(1, 1000)
        input_lines.append(f"{u} {v} {w}")

    Q = random.randint(10, 50)
    input_lines.append(str(Q))

    for _ in range(Q):
        q_type = random.choice([0, 1])
        if q_type == 0:
            u = random.randint(0, N - 1)
            input_lines.append(f"0 {u}")
        else:
            u = random.randint(0, N - 1)
            v = random.randint(0, N - 1)
            input_lines.append(f"1 {u} {v}")

    return "\n".join(input_lines) + "\n"

def test_agent_executable_exists():
    agent_binary = "/home/user/route_calc"
    assert os.path.exists(agent_binary), f"Agent binary not found at {agent_binary}"
    assert os.path.isfile(agent_binary), f"{agent_binary} is not a file"
    assert os.access(agent_binary, os.X_OK), f"Agent binary at {agent_binary} is not executable"

def test_fuzz_equivalence():
    oracle_binary = "/app/backup_route_calc"
    agent_binary = "/home/user/route_calc"

    assert os.path.exists(oracle_binary), "Oracle binary missing"
    assert os.path.exists(agent_binary), "Agent binary missing"

    num_iterations = 100
    base_seed = 42

    for i in range(num_iterations):
        test_input = generate_fuzz_input(base_seed + i)

        try:
            oracle_proc = subprocess.run(
                [oracle_binary],
                input=test_input,
                capture_output=True,
                text=True,
                check=True,
                timeout=5
            )
            oracle_output = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle binary timed out on iteration {i}")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle binary crashed on iteration {i}: {e.stderr}")

        try:
            agent_proc = subprocess.run(
                [agent_binary],
                input=test_input,
                capture_output=True,
                text=True,
                check=True,
                timeout=5
            )
            agent_output = agent_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent binary timed out on iteration {i}. Ensure efficient algorithms are used.")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Agent binary crashed on iteration {i}: {e.stderr}")

        if oracle_output != agent_output:
            error_msg = (
                f"Output mismatch on iteration {i}.\n"
                f"Input:\n{test_input}\n"
                f"Oracle Output:\n{oracle_output}\n"
                f"Agent Output:\n{agent_output}\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
