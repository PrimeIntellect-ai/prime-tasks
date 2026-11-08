#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/release_parser.py"
ORACLE_SCRIPT = "/tests/oracle.py"
NUM_ITERATIONS = 500

LOG_CHOICES = [
    "VALIDATION_FAILED",
    "STATE: INIT",
    "STATE: BUILD",
    "STATE: LINK",
    "STATE: TEST",
    "STATE: DEPLOYED",
    "STATE: INVALID",
    "GARBAGE_LOG_LINE"
]

def generate_random_input(seed):
    rng = random.Random(seed)
    num_lines = rng.randint(1, 20)
    lines = [rng.choice(LOG_CHOICES) for _ in range(num_lines)]
    return "\n".join(lines) + "\n"

def run_script(script_path, input_data):
    try:
        result = subprocess.run(
            [sys.executable, script_path],
            input=input_data,
            text=True,
            capture_output=True,
            timeout=2
        )
        return result.returncode, result.stdout, result.stderr
    except subprocess.TimeoutExpired:
        return -1, "", "TimeoutExpired"

def test_agent_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), "Agent script missing"
    assert os.path.isfile(ORACLE_SCRIPT), "Oracle script missing"

    for i in range(NUM_ITERATIONS):
        input_data = generate_random_input(seed=42 + i)

        oracle_code, oracle_out, _ = run_script(ORACLE_SCRIPT, input_data)
        agent_code, agent_out, agent_err = run_script(AGENT_SCRIPT, input_data)

        error_msg = (
            f"Mismatch on iteration {i}!\n"
            f"Input:\n{input_data}\n"
            f"Oracle Exit Code: {oracle_code}\n"
            f"Oracle Output: {oracle_out.strip()}\n"
            f"Agent Exit Code: {agent_code}\n"
            f"Agent Output: {agent_out.strip()}\n"
            f"Agent Stderr: {agent_err.strip()}"
        )

        assert oracle_code == agent_code, f"Exit code mismatch: {error_msg}"
        assert oracle_out.strip() == agent_out.strip(), f"Output mismatch: {error_msg}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
