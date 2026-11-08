#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

ORACLE_PATH = "/app/legacy_parser"
AGENT_CMD = ["/usr/bin/python3", "/home/user/parser/fast_parser.py"]
CHARSET = "ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789()"
N = 500
MIN_LEN = 10
MAX_LEN = 2000

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing: {ORACLE_PATH}"
    assert os.path.exists(AGENT_CMD[1]), f"Agent script missing: {AGENT_CMD[1]}"

    random.seed(42)

    for i in range(N):
        length = random.randint(MIN_LEN, MAX_LEN)
        input_str = "".join(random.choices(CHARSET, k=length))
        input_bytes = input_str.encode('utf-8')

        try:
            oracle_proc = subprocess.run(
                [ORACLE_PATH],
                input=input_bytes,
                capture_output=True,
                timeout=2,
                check=True
            )
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            pytest.fail(f"Oracle timed out on input {input_str}")
        except subprocess.CalledProcessError as e:
            pytest.fail(f"Oracle crashed on input {input_str}: {e.stderr}")

        try:
            agent_proc = subprocess.run(
                AGENT_CMD,
                input=input_bytes,
                capture_output=True,
                timeout=2
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Agent timed out on input: {input_str}")

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent crashed on input: {input_str}\nStderr: {agent_proc.stderr.decode('utf-8', errors='replace')}")

        agent_out = agent_proc.stdout

        if oracle_out != agent_out:
            pytest.fail(
                f"Mismatch on input: {input_str}\n"
                f"Oracle output length: {len(oracle_out)}\n"
                f"Agent output length: {len(agent_out)}\n"
                f"Oracle output (first 100 bytes): {oracle_out[:100]}\n"
                f"Agent output (first 100 bytes): {agent_out[:100]}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
