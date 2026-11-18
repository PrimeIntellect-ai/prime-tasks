#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

ORACLE_PATH = "/tests/streaming_scaler_oracle"
AGENT_PATH = "/home/user/streaming_scaler"
MAKEFILE_PATH = "/app/libwelford-1.0.0/Makefile"
LIB_PATH = "/app/libwelford-1.0.0/libwelford.a"

def test_makefile_fixed():
    assert os.path.isfile(MAKEFILE_PATH), f"{MAKEFILE_PATH} is missing"
    with open(MAKEFILE_PATH, "r") as f:
        content = f.read()
    assert "ar rcs" in content, "Makefile was not fixed to use 'ar rcs'"
    assert "tar rcs" not in content, "Makefile still contains the 'tar rcs' bug"

def test_libwelford_built():
    assert os.path.isfile(LIB_PATH), f"Static library {LIB_PATH} is missing. Did you run make?"

def test_agent_binary_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent binary {AGENT_PATH} is missing"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary {AGENT_PATH} is not executable"

def generate_fuzz_input(n):
    random.seed(42)
    lines = []
    for _ in range(n):
        r = random.random()
        if r < 0.60:
            val = random.uniform(-1000.0, 1000.0)
            lines.append(f"FIT {val}\n")
        elif r < 0.98:
            val = random.uniform(-1000.0, 1000.0)
            lines.append(f"TRANSFORM {val}\n")
        else:
            val = random.uniform(0.0, 10.0)
            lines.append(f"INVALID {val}\n")
    return "".join(lines)

def test_fuzz_equivalence():
    assert os.path.isfile(ORACLE_PATH), f"Oracle {ORACLE_PATH} missing"
    assert os.path.isfile(AGENT_PATH), f"Agent binary {AGENT_PATH} missing"

    input_data = generate_fuzz_input(10000)

    oracle_proc = subprocess.run(
        [ORACLE_PATH],
        input=input_data,
        text=True,
        capture_output=True
    )
    assert oracle_proc.returncode == 0, "Oracle failed to execute"

    agent_proc = subprocess.run(
        [AGENT_PATH],
        input=input_data,
        text=True,
        capture_output=True
    )

    if agent_proc.returncode != 0:
        pytest.fail(f"Agent program exited with non-zero status: {agent_proc.returncode}\nStderr: {agent_proc.stderr}")

    oracle_lines = oracle_proc.stdout.splitlines()
    agent_lines = agent_proc.stdout.splitlines()

    if len(oracle_lines) != len(agent_lines):
        pytest.fail(f"Output line count mismatch. Expected {len(oracle_lines)}, got {len(agent_lines)}")

    input_lines = input_data.splitlines()
    output_idx = 0

    for i, line in enumerate(input_lines):
        if line.startswith("FIT ") or line.startswith("TRANSFORM "):
            if output_idx >= len(oracle_lines) or output_idx >= len(agent_lines):
                break
            expected = oracle_lines[output_idx]
            actual = agent_lines[output_idx]
            if expected != actual:
                pytest.fail(
                    f"Mismatch at input line {i+1}: '{line}'\n"
                    f"Expected output: '{expected}'\n"
                    f"Actual output: '{actual}'"
                )
            output_idx += 1
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
