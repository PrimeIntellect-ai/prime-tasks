#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import subprocess
import pytest

def test_decoder_fuzz_equivalence():
    oracle_path = "/app/backup_decoder"
    agent_path = "/home/user/decoder.py"

    assert os.path.exists(agent_path), f"Agent script {agent_path} is missing."
    assert os.path.isfile(agent_path), f"{agent_path} is not a file."
    assert os.path.exists(oracle_path), f"Oracle binary {oracle_path} is missing."

    random.seed(1337)
    inputs = []

    # 20% of inputs: Completely random bytes (length 1 to 100)
    for _ in range(200):
        length = random.randint(1, 100)
        inputs.append(bytes(random.choices(range(256), k=length)))

    # 80% of inputs: Valid magic header 'BKP1' + 0 to 500 random bytes
    for _ in range(800):
        length = random.randint(0, 500)
        payload = bytes(random.choices(range(256), k=length))
        inputs.append(b"BKP1" + payload)

    # Add a few specific edge cases just to be sure
    inputs.append(b"")
    inputs.append(b"BKP")
    inputs.append(b"BKP1")

    random.shuffle(inputs)

    for i, data in enumerate(inputs):
        oracle_proc = subprocess.run([oracle_path], input=data, capture_output=True)
        agent_proc = subprocess.run(["python3", agent_path], input=data, capture_output=True)

        error_msg = f"Mismatch on iteration {i} with input length {len(data)} (starts with {data[:10]!r})."

        assert oracle_proc.returncode == agent_proc.returncode, \
            f"{error_msg} Exit code oracle={oracle_proc.returncode}, agent={agent_proc.returncode}"

        assert oracle_proc.stdout == agent_proc.stdout, \
            f"{error_msg} stdout oracle={oracle_proc.stdout!r}, agent={agent_proc.stdout!r}"

        assert oracle_proc.stderr == agent_proc.stderr, \
            f"{error_msg} stderr oracle={oracle_proc.stderr!r}, agent={agent_proc.stderr!r}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
