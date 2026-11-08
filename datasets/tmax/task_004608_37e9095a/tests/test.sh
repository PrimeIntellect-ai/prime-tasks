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

ORACLE_PATH = "/app/loc_oracle"
AGENT_PATH = "/home/user/loc_tool"
NUM_FUZZ_TESTS = 200

def generate_random_csv_input() -> str:
    num_lines = random.randint(1, 20)
    lines = []

    # ASCII printable characters excluding comma and newline to avoid breaking simple CSV parsing
    # Wait, standard CSV allows commas if quoted, but the problem says "wide format CSV without a header. Each row always has exactly 4 columns".
    # To be safe and avoid complex CSV quoting issues in the random input (unless the oracle handles it, but let's stick to safe chars or just remove commas from the random pool for the strings).
    safe_chars = string.ascii_letters + string.digits + string.punctuation.replace(',', '') + ' '

    for _ in range(num_lines):
        id_len = random.randint(5, 10)
        row_id = ''.join(random.choices(string.ascii_letters + string.digits, k=id_len))

        en_len = random.randint(0, 50)
        en_str = ''.join(random.choices(safe_chars, k=en_len))

        es_len = random.randint(0, 50)
        es_str = ''.join(random.choices(safe_chars, k=es_len))

        fr_len = random.randint(0, 50)
        fr_str = ''.join(random.choices(safe_chars, k=fr_len))

        lines.append(f"{row_id},{en_str},{es_str},{fr_str}")

    return "\n".join(lines) + "\n"

def test_agent_executable_exists():
    assert os.path.exists(AGENT_PATH), f"The agent executable {AGENT_PATH} does not exist. Did you compile your Go code?"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file."
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable."

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent missing at {AGENT_PATH}"

    random.seed(42)

    for i in range(NUM_FUZZ_TESTS):
        input_data = generate_random_csv_input()

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data.encode('utf-8'),
            capture_output=True
        )
        oracle_out = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data.encode('utf-8'),
            capture_output=True
        )
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            error_msg = (
                f"Mismatch on fuzz test {i+1}/{NUM_FUZZ_TESTS}.\n"
                f"Input data:\n{input_data}\n"
                f"Oracle output (len {len(oracle_out)}):\n{oracle_out.decode('utf-8', errors='replace')}\n"
                f"Agent output (len {len(agent_out)}):\n{agent_out.decode('utf-8', errors='replace')}\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
