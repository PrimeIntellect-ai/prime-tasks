#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess

def test_new_dedup_fuzz_equivalence():
    oracle_path = "/app/legacy_dedup"
    agent_path = "/home/user/new_dedup"

    assert os.path.exists(agent_path), f"Agent binary {agent_path} does not exist."
    assert os.path.isfile(agent_path), f"{agent_path} is not a file."
    assert os.access(agent_path, os.X_OK), f"{agent_path} is not executable."
    assert os.path.exists(oracle_path), f"Oracle binary {oracle_path} does not exist."

    random.seed(42)

    # Run 100 iterations to keep the test runtime reasonable while testing up to 50k bytes.
    N = 100

    for i in range(N):
        length = random.randint(0, 50000)
        # Generate random ASCII bytes (0x01 to 0x7F)
        input_bytes = bytes(random.choices(range(1, 128), k=length))

        try:
            oracle_proc = subprocess.run(
                [oracle_path],
                input=input_bytes,
                capture_output=True,
                timeout=5,
                check=False
            )
            oracle_out = oracle_proc.stdout
        except subprocess.TimeoutExpired:
            continue

        try:
            agent_proc = subprocess.run(
                [agent_path],
                input=input_bytes,
                capture_output=True,
                timeout=5,
                check=False
            )
            agent_out = agent_proc.stdout
        except subprocess.TimeoutExpired:
            assert False, f"Agent binary timed out on iteration {i} with input length {length}."

        if oracle_out != agent_out:
            # Provide a helpful error message without dumping 50KB to the console
            error_msg = (
                f"Output mismatch on iteration {i} (input length {length} bytes).\n"
                f"Oracle output length: {len(oracle_out)} bytes\n"
                f"Agent output length: {len(agent_out)} bytes\n"
                f"Oracle output snippet: {oracle_out[:100]!r}...\n"
                f"Agent output snippet: {agent_out[:100]!r}..."
            )
            assert False, error_msg
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
