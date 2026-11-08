#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/solution.py"


def expected_output(hex_str, offset):
    return "".join(
        f"{(int(hex_str[i:i+2], 16) ^ offset) & 0xFF:02X}"
        for i in range(0, len(hex_str), 2)
    )


def run_agent(test_input, offset):
    env = os.environ.copy()
    env["INGESTION_OFFSET"] = str(offset)
    try:
        result = subprocess.run(
            ["/usr/bin/python3", AGENT_SCRIPT, test_input],
            env=env,
            capture_output=True,
            text=True,
            timeout=2,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Agent script timed out on input {test_input}")

    if result.returncode != 0:
        pytest.fail(
            f"Agent script failed with return code {result.returncode} on input {test_input}.\n"
            f"Stderr: {result.stderr}"
        )
    return result.stdout.strip()


def test_solution_exists():
    """Verify that the user created the solution script."""
    assert os.path.isfile(AGENT_SCRIPT), "Missing solution script at /home/user/solution.py"


def test_fuzz_equivalence():
    """Fuzz the agent's solution against independently derived legacy outputs."""
    random.seed(42)
    hex_chars = "0123456789ABCDEF"

    for _ in range(5000):
        length = random.randint(16, 1024)
        if length % 2 != 0:
            length += 1
        test_input = "".join(random.choices(hex_chars, k=length))

        agent_output = run_agent(test_input, 137)
        expected = expected_output(test_input, 137)
        assert agent_output == expected, (
            f"Mismatch on input {test_input}\n"
            f"Expected: {expected}\n"
            f"Got:      {agent_output}"
        )


def test_reads_ingestion_offset():
    """Ensure the processor uses INGESTION_OFFSET rather than hardcoding 137."""
    test_input = "0011227F80A5FEFF"
    for offset in (0, 1, 42, 136, 137, 200, 255):
        agent_output = run_agent(test_input, offset)
        expected = expected_output(test_input, offset)
        assert agent_output == expected, (
            f"Mismatch with INGESTION_OFFSET={offset}\n"
            f"Expected: {expected}\n"
            f"Got:      {agent_output}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
