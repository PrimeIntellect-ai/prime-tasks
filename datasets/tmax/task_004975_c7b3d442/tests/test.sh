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

ORACLE_PATH = "/app/doc_encoder"
AGENT_SCRIPT = "/home/user/encoder.py"

def generate_fuzz_inputs(n=100, seed=42):
    random.seed(seed)
    inputs = []

    # Edge cases
    inputs.append(b"")
    inputs.append(b"A" * 255)
    inputs.append(b"A" * 256)
    inputs.append(b"A" * 1000)
    inputs.append(b"AB" * 500)

    for _ in range(n - len(inputs)):
        length = random.randint(1, 50000)
        data = bytearray()
        while len(data) < length:
            char = random.randint(0, 255)
            # Bias towards repeated characters
            if random.random() < 0.7:
                repeat = random.randint(1, 300)
            else:
                repeat = 1
            data.extend([char] * min(repeat, length - len(data)))
        inputs.append(bytes(data))

    return inputs

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle missing at {ORACLE_PATH}"
    assert os.path.exists(AGENT_SCRIPT), f"Agent script missing at {AGENT_SCRIPT}"

    inputs = generate_fuzz_inputs(100)

    for i, test_input in enumerate(inputs):
        # Run oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=test_input,
            capture_output=True,
            check=False
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {i}"
        oracle_output = oracle_proc.stdout

        # Run agent
        agent_proc = subprocess.run(
            [sys.executable, AGENT_SCRIPT],
            input=test_input,
            capture_output=True,
            check=False
        )
        assert agent_proc.returncode == 0, f"Agent script failed on input {i}. Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
        agent_output = agent_proc.stdout

        if oracle_output != agent_output:
            # Truncate output for error message if it's too long
            out_oracle_repr = oracle_output[:100].hex() + ("..." if len(oracle_output) > 100 else "")
            out_agent_repr = agent_output[:100].hex() + ("..." if len(agent_output) > 100 else "")
            pytest.fail(
                f"Mismatch on input {i} (length {len(test_input)}).\n"
                f"Oracle output (hex): {out_oracle_repr}\n"
                f"Agent output (hex):  {out_agent_repr}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
