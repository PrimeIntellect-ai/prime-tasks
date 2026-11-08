#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import subprocess
import random
import pytest

ORACLE_PATH = "/app/loc_encoder"
AGENT_PATH = "/home/user/loc_encoder.py"

def generate_random_string(length):
    # Mix of ASCII, Latin-1, Cyrillic, CJK, Emojis
    # Avoid null bytes as they terminate C strings
    ranges = [
        (0x0020, 0x007E),   # ASCII
        (0x00A0, 0x00FF),   # Latin-1
        (0x0400, 0x04FF),   # Cyrillic
        (0x4E00, 0x9FFF),   # CJK
        (0x1F300, 0x1F64F)  # Emojis
    ]
    res = []
    for _ in range(length):
        r = random.choice(ranges)
        res.append(chr(random.randint(r[0], r[1])))
    return "".join(res)

def test_fuzz_equivalence():
    """Fuzz the agent's Python script against the oracle binary."""
    assert os.path.exists(ORACLE_PATH), f"Oracle missing: {ORACLE_PATH}"
    assert os.path.exists(AGENT_PATH), f"Agent script missing: {AGENT_PATH}"

    random.seed(42)

    # Run 500 iterations to balance thoroughness and test execution time
    for i in range(500):
        # Lengths ranging from 0 to 4096
        length = random.randint(0, 4096)
        test_str = generate_random_string(length)

        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH, test_str],
            capture_output=True
        )
        oracle_out = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [sys.executable, AGENT_PATH, test_str],
            capture_output=True
        )
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            # Provide a truncated version of the input if it's too long
            display_str = test_str if len(test_str) < 50 else test_str[:50] + "..."
            pytest.fail(
                f"Mismatch found!\n"
                f"Input string: {repr(display_str)}\n"
                f"Oracle output (hex): {oracle_out.hex()}\n"
                f"Agent output (hex):  {agent_out.hex()}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
