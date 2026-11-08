#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

AGENT_PROGRAM = "/home/user/fast_hasher"
N_INPUTS = 10000


def checksum(line):
    data = line.encode("utf-8")
    value = 0x811C9DC5
    for byte in data:
        value ^= byte
        value = (value * 0x01000193) & 0xFFFFFFFF
    value ^= len(data)
    return f"{value:08x}"


def test_agent_program_exists_and_executable():
    assert os.path.exists(AGENT_PROGRAM), f"Agent program not found at {AGENT_PROGRAM}"
    assert os.path.isfile(AGENT_PROGRAM), f"{AGENT_PROGRAM} is not a file"
    assert os.access(AGENT_PROGRAM, os.X_OK), f"{AGENT_PROGRAM} is not executable"


def test_fuzz_equivalence():
    random.seed(42)
    charset = [chr(i) for i in range(0x20, 0x7F)]

    inputs = []
    for _ in range(N_INPUTS):
        length = random.randint(1, 1024)
        inputs.append("".join(random.choices(charset, k=length)))

    inputs[10] = "CRASH"
    inputs[100] = "FOOCRASHBAR"
    inputs[1000] = "CRASH" * 10

    input_bytes = ("\n".join(inputs) + "\n").encode("utf-8")
    expected_output = [checksum(value) for value in inputs]

    try:
        agent_proc = subprocess.run(
            [AGENT_PROGRAM],
            input=input_bytes,
            capture_output=True,
            check=False,
            timeout=10,
        )
    except subprocess.TimeoutExpired:
        pytest.fail("Agent program timed out")

    if agent_proc.returncode != 0:
        pytest.fail(
            f"Agent program exited with non-zero code {agent_proc.returncode}. "
            f"Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
        )

    agent_output = agent_proc.stdout.decode("utf-8").splitlines()

    assert len(agent_output) == len(expected_output), \
        f"Output line count mismatch: expected {len(expected_output)}, got {len(agent_output)}"

    for i, (expected_line, agent_line) in enumerate(zip(expected_output, agent_output)):
        if expected_line != agent_line:
            pytest.fail(
                f"Mismatch on input line {i + 1}.\n"
                f"Input: {inputs[i]!r}\n"
                f"Expected output: {expected_line}\n"
                f"Agent output: {agent_line}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
