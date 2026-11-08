#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import random
import subprocess
import pytest

ORACLE_PATH = "/tests/oracle_auditor"
AGENT_SCRIPT = "/home/user/policy_auditor.py"
NUM_TESTS = 10000

def generate_random_input():
    # Generate max-age
    # We want values around 31536000 to test the boundary, as well as random other values
    if random.random() < 0.2:
        max_age = 31536000
    elif random.random() < 0.2:
        max_age = 31536000 + random.randint(1, 1000)
    elif random.random() < 0.2:
        max_age = 31536000 - random.randint(1, 1000)
    else:
        max_age = random.randint(0, 100000000)

    csp_header = f"default-src 'self'; max-age={max_age}"
    if random.random() < 0.5:
        csp_header += "; script-src 'none'"

    # Generate elf_metadata
    segments = []
    num_segments = random.randint(1, 5)
    for _ in range(num_segments):
        # Possible flags
        flags = random.choice(["R", "RW", "RE", "RWE", "W", "E", "WE"])
        segments.append(flags)

    elf_metadata = ", ".join(segments)

    return json.dumps({
        "csp_header": csp_header,
        "elf_metadata": elf_metadata
    })

def test_fuzz_equivalence():
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"

    random.seed(42)

    for i in range(NUM_TESTS):
        test_input = generate_random_input()

        # Run oracle
        try:
            oracle_proc = subprocess.run(
                ["python3", ORACLE_PATH, test_input],
                capture_output=True,
                text=True,
                timeout=2
            )
            oracle_out = oracle_proc.stdout.strip()
        except Exception as e:
            pytest.fail(f"Oracle failed to run on input {test_input}: {e}")

        # Run agent
        try:
            agent_proc = subprocess.run(
                ["python3", AGENT_SCRIPT, test_input],
                capture_output=True,
                text=True,
                timeout=2
            )
            agent_out = agent_proc.stdout.strip()
        except Exception as e:
            pytest.fail(f"Agent script failed to run on input {test_input}: {e}")

        assert agent_out == oracle_out, (
            f"Mismatch on input {i+1}/{NUM_TESTS}!\n"
            f"Input: {test_input}\n"
            f"Oracle output: {oracle_out!r}\n"
            f"Agent output: {agent_out!r}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
