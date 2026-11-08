#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import struct
import random
import subprocess
import pytest

ORACLE_PATH = "/app/decode_artb"
AGENT_PATH = "/home/user/decode_artb.py"
NUM_FUZZ_TESTS = 100

def generate_artb(seed):
    random.seed(seed)
    data = bytearray(b"ARTB")
    num_chunks = random.randint(1, 20)
    data.extend(struct.pack('<I', num_chunks))

    for _ in range(num_chunks):
        num_pairs = random.randint(1, 100)
        orig_size = 0
        comp_size = num_pairs * 2
        comp_data = bytearray()
        for _ in range(num_pairs):
            count = random.randint(1, 255)
            val = random.randint(0, 255)
            orig_size += count
            comp_data.append(count)
            comp_data.append(val)

        data.extend(struct.pack('<I', orig_size))
        data.extend(struct.pack('<I', comp_size))
        data.extend(comp_data)

    return bytes(data)

def test_agent_script_exists():
    assert os.path.exists(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"

def test_fuzz_equivalence():
    assert os.path.exists(ORACLE_PATH), f"Oracle not found at {ORACLE_PATH}"
    assert os.access(ORACLE_PATH, os.X_OK), f"Oracle at {ORACLE_PATH} is not executable"

    for i in range(NUM_FUZZ_TESTS):
        input_data = generate_artb(seed=42 + i)

        # Run Oracle
        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            capture_output=True,
            timeout=5
        )
        assert oracle_proc.returncode == 0, f"Oracle failed on input {i}"

        # Run Agent
        agent_proc = subprocess.run(
            ["python3", AGENT_PATH],
            input=input_data,
            capture_output=True,
            timeout=5
        )

        if agent_proc.returncode != 0:
            pytest.fail(f"Agent script failed on input {i}. Stderr:\n{agent_proc.stderr.decode('utf-8', errors='replace')}")

        if oracle_proc.stdout != agent_proc.stdout:
            pytest.fail(
                f"Output mismatch on input {i} (seed {42+i}).\n"
                f"Input length: {len(input_data)} bytes\n"
                f"Oracle output length: {len(oracle_proc.stdout)} bytes\n"
                f"Agent output length: {len(agent_proc.stdout)} bytes"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
