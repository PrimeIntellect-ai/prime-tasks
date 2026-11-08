#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import string
import pytest

ORACLE_PATH = "/tests/oracle_dft_tool"
AGENT_PATH = "/home/user/dft_tool"
NUM_ITERATIONS = 1000

def generate_random_input(seed):
    random.seed(seed)
    num_lines = random.randint(0, 500)
    lines = []
    for _ in range(num_lines):
        if random.random() < 0.8:
            atom_id = random.randint(1, 99999)
            x = random.uniform(-1000.0, 1000.0)
            y = random.uniform(-1000.0, 1000.0)
            z = random.uniform(-1000.0, 1000.0)
            lines.append(f"ATOM {atom_id} {x:.6f} {y:.6f} {z:.6f}")
        else:
            # Garbage line
            length = random.randint(0, 50)
            garbage = ''.join(random.choices(string.ascii_letters + string.digits + " \t", k=length))
            # Sometimes add malformed ATOM lines
            if random.random() < 0.5:
                lines.append(f"ATOM {garbage}")
            else:
                lines.append(garbage)
    return "\n".join(lines) + "\n"

def test_agent_executable_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable at {AGENT_PATH} is not executable"

def test_oracle_executable_exists():
    assert os.path.isfile(ORACLE_PATH), f"Oracle executable not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle executable at {ORACLE_PATH} is not executable"

@pytest.mark.parametrize("iteration", range(NUM_ITERATIONS))
def test_fuzz_equivalence(iteration):
    input_data = generate_random_input(iteration)
    input_bytes = input_data.encode('utf-8')

    try:
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_bytes,
            capture_output=True,
            timeout=5,
            check=True
        )
        oracle_output = oracle_proc.stdout.decode('utf-8').strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Oracle failed on iteration {iteration}.\nInput:\n{input_data}\nError:\n{e.stderr.decode('utf-8')}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Oracle timed out on iteration {iteration}.")

    try:
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_bytes,
            capture_output=True,
            timeout=5,
            check=True
        )
        agent_output = agent_proc.stdout.decode('utf-8').strip()
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Agent failed on iteration {iteration}.\nInput:\n{input_data}\nError:\n{e.stderr.decode('utf-8')}")
    except subprocess.TimeoutExpired:
        pytest.fail(f"Agent timed out on iteration {iteration}.")

    assert agent_output == oracle_output, (
        f"Mismatch on iteration {iteration}.\n"
        f"Input:\n{input_data}\n"
        f"Oracle Output: {oracle_output}\n"
        f"Agent Output:  {agent_output}"
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
