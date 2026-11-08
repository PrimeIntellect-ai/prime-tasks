#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import pytest

AGENT_BIN = "/home/user/processor/target/release/processor"
SEED = 54321


def expected_output(input_lines):
    x = SEED
    p = [[0.0] * 3 for _ in range(8)]
    for i in range(8):
        for j in range(3):
            x = (1103515245 * x + 12345) % 2147483648
            p[i][j] = (x / 2147483648.0) * 2.0 - 1.0

    output = []
    for line in input_lines:
        values = [float(part) for part in line.split()]
        w = [0.0, 0.0, 0.0]
        for j in range(3):
            for i in range(8):
                w[j] += values[i] * p[i][j]
        output.append(f"{w[0]:.4f} {w[1]:.4f} {w[2]:.4f}")
    return output


def test_executable_exists():
    assert os.path.isfile(AGENT_BIN), f"Agent executable not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent executable at {AGENT_BIN} is not executable"


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_BIN), f"Agent executable not found at {AGENT_BIN}"

    random.seed(42)
    num_lines = 50
    input_lines = []
    for _ in range(num_lines):
        floats = [random.uniform(-10.0, 10.0) for _ in range(8)]
        line = " ".join(f"{f:.6f}" for f in floats)
        input_lines.append(line)

    input_text = "\n".join(input_lines) + "\n"
    expected_lines = expected_output(input_lines)

    try:
        agent_proc = subprocess.run(
            [AGENT_BIN],
            input=input_text,
            text=True,
            capture_output=True,
            check=True,
            timeout=5
        )
        agent_output = agent_proc.stdout
    except subprocess.CalledProcessError as e:
        pytest.fail(f"Agent program failed to run: {e.stderr}")

    agent_lines = agent_output.strip().split("\n")

    assert len(agent_lines) == len(expected_lines), f"Output line count mismatch. Expected {len(expected_lines)}, got {len(agent_lines)}"

    for i, (expected_line, agent_line) in enumerate(zip(expected_lines, agent_lines)):
        assert agent_line.strip() == expected_line, (
            f"Mismatch at line {i+1}.\n"
            f"Input: {input_lines[i]}\n"
            f"Expected: {expected_line}\n"
            f"Got:      {agent_line.strip()}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
