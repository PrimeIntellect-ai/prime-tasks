#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import random
import string
import subprocess
import pytest

def generate_fuzz_input():
    """Generates a random input bytes object following the distribution rules."""
    valid_chars = []
    for i in range(32, 256):
        # Skip undefined/control cp1252 characters and newlines/pipes
        if i in (127, 129, 141, 143, 144, 157):
            continue
        c = chr(i)
        if c not in ('\n', '\r', '|'):
            try:
                c.encode('cp1252')
                valid_chars.append(c)
            except UnicodeEncodeError:
                pass

    out = ["[CONFIG]"]
    num_lines = random.randint(1, 20)
    for _ in range(num_lines):
        key_len = random.randint(3, 15)
        key = ''.join(random.choices(string.ascii_letters + string.digits, k=key_len))
        if random.random() < 0.25:
            key = "SECURE_" + key

        val_len = random.randint(1, 50)
        val = ''.join(random.choices(valid_chars, k=val_len))

        out.append(f"{key}|{val}")

    out.append("")
    return "\n".join(out).encode('cp1252')

def test_fuzz_equivalence():
    """Test that the agent's script matches the oracle script on 500 random inputs."""
    agent_script = "/home/user/parse_config.py"
    oracle_script = "/tests/oracle_parser.py"

    assert os.path.exists(agent_script), f"Agent script not found at {agent_script}"
    assert os.path.exists(oracle_script), f"Oracle script not found at {oracle_script}"

    random.seed(42)

    for i in range(500):
        test_input = generate_fuzz_input()

        oracle_proc = subprocess.run(
            [sys.executable, oracle_script],
            input=test_input,
            capture_output=True
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {test_input!r}"

        agent_proc = subprocess.run(
            [sys.executable, agent_script],
            input=test_input,
            capture_output=True
        )

        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent script failed with return code {agent_proc.returncode} on input: {test_input!r}\n"
                f"Stderr: {agent_proc.stderr.decode(errors='replace')}"
            )

        oracle_out = oracle_proc.stdout
        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on input {test_input!r}.\n"
                f"Expected (Oracle): {oracle_out!r}\n"
                f"Got (Agent): {agent_out!r}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
