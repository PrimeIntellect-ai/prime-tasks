#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import tempfile
import pytest

AGENT_SCRIPT = "/home/user/archive_extractor.py"
ORACLE_SCRIPT = "/tests/oracle_extractor.py"
NUM_FUZZ_TESTS = 50

def generate_fuzz_input(seed):
    """Generate a single fuzz input file."""
    random.seed(seed)

    # Generate random string length
    length = random.randint(100, 1000)

    # Generate random characters
    chars = string.ascii_letters + string.digits + " "
    text = "".join(random.choices(chars, k=length))

    # Insert 'ERROR' 0 to 5 times
    num_errors = random.randint(0, 5)
    for _ in range(num_errors):
        insert_pos = random.randint(0, len(text))
        text = text[:insert_pos] + "ERROR" + text[insert_pos:]

    # Encode using cp037
    encoded_text = text.encode('cp037')

    # Generate 512 bytes of random binary noise
    noise = bytes(random.getrandbits(8) for _ in range(512))

    return noise + encoded_text

def test_agent_script_exists():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(AGENT_SCRIPT), f"{AGENT_SCRIPT} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), "Agent script missing."
    assert os.path.exists(ORACLE_SCRIPT), "Oracle script missing."

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(NUM_FUZZ_TESTS):
            input_data = generate_fuzz_input(seed=42 + i)
            test_file = os.path.join(tmpdir, f"test_{i}.dat")

            with open(test_file, 'wb') as f:
                f.write(input_data)

            # Run Oracle
            oracle_cmd = ["python3", ORACLE_SCRIPT, test_file]
            oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)
            assert oracle_proc.returncode == 0, f"Oracle failed on test {i}:\n{oracle_proc.stderr}"
            oracle_out = oracle_proc.stdout

            # Run Agent
            agent_cmd = ["python3", AGENT_SCRIPT, test_file]
            agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)

            # Check exit code
            assert agent_proc.returncode == 0, f"Agent script failed on test {i}:\n{agent_proc.stderr}"

            # Check output
            agent_out = agent_proc.stdout
            assert agent_out == oracle_out, (
                f"Output mismatch on test {i}.\n"
                f"Oracle output length: {len(oracle_out)}\n"
                f"Agent output length: {len(agent_out)}\n"
                f"Oracle output excerpt: {oracle_out[:100]}...\n"
                f"Agent output excerpt: {agent_out[:100]}..."
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
