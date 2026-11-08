#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import subprocess
import random
import string
import pytest

AGENT_SCRIPT = "/home/user/stream_processor.py"
ORACLE_SCRIPT = "/tests/oracle_processor.py"
N_TESTS = 100

def generate_random_input(seed):
    random.seed(seed)
    length = random.randint(0, 5000)
    # Generate random ASCII text
    chars = string.ascii_letters + string.digits + string.punctuation + " \t\r\n"
    raw_text = "".join(random.choice(chars) for _ in range(length))

    lines = raw_text.split('\n')
    modified_lines = []
    for line in lines:
        if random.random() < 0.20:
            line = "CMD: " + line
        if random.random() < 0.20:
            insert_pos = random.randint(0, len(line))
            line = line[:insert_pos] + "TODO" + line[insert_pos:]
        modified_lines.append(line)

    return '\n'.join(modified_lines).encode('utf-8')

def test_script_exists_and_executable():
    """Check that the agent created the script and made it executable."""
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.access(AGENT_SCRIPT, os.X_OK), f"Agent script at {AGENT_SCRIPT} is not executable"

def test_fuzz_equivalence():
    """Fuzz the agent's script against the oracle script to ensure bit-exact equivalence."""
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    for i in range(N_TESTS):
        input_data = generate_random_input(seed=42 + i)

        # Run oracle
        oracle_proc = subprocess.run(
            ["python3", ORACLE_SCRIPT],
            input=input_data,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on seed {i}"
        oracle_output = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            ["python3", AGENT_SCRIPT],
            input=input_data,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent script failed (exit code {agent_proc.returncode}) on seed {i}.\n"
                f"Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
            )

        agent_output = agent_proc.stdout

        if oracle_output != agent_output:
            # Provide a helpful failure message
            pytest.fail(
                f"Output mismatch on seed {i}.\n"
                f"Input length: {len(input_data)} bytes\n"
                f"Oracle output length: {len(oracle_output)} bytes\n"
                f"Agent output length: {len(agent_output)} bytes\n"
                f"Oracle output (first 200 chars): {oracle_output[:200]!r}\n"
                f"Agent output (first 200 chars): {agent_output[:200]!r}\n"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
