#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import string
import subprocess
import pytest

AGENT_PROGRAM = "/home/user/loc_processor"
ORACLE_PROGRAM = "/tests/oracle_processor"

def generate_translation_key():
    length = random.randint(5, 15)
    chars = string.ascii_lowercase + "."
    return "".join(random.choice(chars) for _ in range(length))

def generate_csv_data(num_lines):
    lines = []
    regions = ["ES", "DE", "BR", "US", "FR", "JP", "MX"]
    for _ in range(num_lines):
        ts = random.randint(1600000000, 1700000000)
        region = random.choice(regions)
        key = generate_translation_key()
        count = random.randint(1, 100)
        lines.append(f"{ts},{region},{key},{count}")
    return "\n".join(lines) + "\n" if lines else ""

def test_agent_program_exists():
    assert os.path.exists(AGENT_PROGRAM), f"Agent program not found at {AGENT_PROGRAM}"
    assert os.path.isfile(AGENT_PROGRAM), f"Agent program {AGENT_PROGRAM} is not a file"
    assert os.access(AGENT_PROGRAM, os.X_OK), f"Agent program {AGENT_PROGRAM} is not executable"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PROGRAM), f"Oracle program not found at {ORACLE_PROGRAM}"
    assert os.access(ORACLE_PROGRAM, os.X_OK), f"Oracle program {ORACLE_PROGRAM} is not executable"

    random.seed(42)
    num_iterations = 100

    for i in range(num_iterations):
        num_lines = random.randint(0, 10000)
        # Keep the tests fast by using smaller sizes for most, but ensure at least one large test
        if i == 0:
            num_lines = 10000
        elif i > 10:
            num_lines = random.randint(0, 100)

        csv_input = generate_csv_data(num_lines)
        input_bytes = csv_input.encode('utf-8')

        oracle_proc = subprocess.run(
            [ORACLE_PROGRAM],
            input=input_bytes,
            capture_output=True,
            timeout=10
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on iteration {i}"
        oracle_output = oracle_proc.stdout

        agent_proc = subprocess.run(
            [AGENT_PROGRAM],
            input=input_bytes,
            capture_output=True,
            timeout=10
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent program failed with return code {agent_proc.returncode} on iteration {i}.\nStderr: {agent_proc.stderr.decode('utf-8', errors='replace')}")

        agent_output = agent_proc.stdout

        if oracle_output != agent_output:
            # Output a snippet if it's too large
            in_snippet = csv_input[:500] + ("..." if len(csv_input) > 500 else "")
            oracle_snippet = oracle_output.decode('utf-8', errors='replace')[:500]
            agent_snippet = agent_output.decode('utf-8', errors='replace')[:500]
            pytest.fail(
                f"Mismatch on iteration {i} (lines: {num_lines}).\n"
                f"Input snippet:\n{in_snippet}\n"
                f"Oracle output snippet:\n{oracle_snippet}\n"
                f"Agent output snippet:\n{agent_snippet}\n"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
