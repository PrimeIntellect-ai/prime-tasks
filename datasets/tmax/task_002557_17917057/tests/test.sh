#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import struct
import random
import subprocess
import pytest

AGENT_SCRIPT = "/home/user/compact_wal.py"
ORACLE_SCRIPT = "/tests/oracle_compactor.py"
TARGET_APP_ID = 0x8BADF00D
MAGIC = b"WALOGv1\0"

def generate_wal_stream(seed):
    rng = random.Random(seed)
    num_records = rng.randint(0, 5000)

    stream = bytearray(MAGIC)

    for _ in range(num_records):
        length = rng.randint(0, 1024)
        if rng.random() < 0.2:
            app_id = TARGET_APP_ID
        else:
            app_id = rng.randint(0, 0xFFFFFFFF)

        payload = bytes(rng.getrandbits(8) for _ in range(length))

        header = struct.pack('<II', length, app_id)
        stream.extend(header)
        stream.extend(payload)

    return bytes(stream)

def test_agent_script_exists():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"

@pytest.mark.parametrize("seed", range(100))
def test_fuzz_equivalence(seed):
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_SCRIPT), f"Oracle script not found at {ORACLE_SCRIPT}"

    input_data = generate_wal_stream(seed)

    # Run oracle
    oracle_proc = subprocess.run(
        [sys.executable, ORACLE_SCRIPT],
        input=input_data,
        capture_output=True,
        check=True
    )
    oracle_output = oracle_proc.stdout

    # Run agent
    agent_proc = subprocess.run(
        [sys.executable, AGENT_SCRIPT],
        input=input_data,
        capture_output=True
    )

    assert agent_proc.returncode == 0, f"Agent script failed with return code {agent_proc.returncode}. Stderr: {agent_proc.stderr.decode(errors='replace')}"

    agent_output = agent_proc.stdout

    if agent_output != oracle_output:
        pytest.fail(f"Mismatch on seed {seed}. Oracle output length: {len(oracle_output)}, Agent output length: {len(agent_output)}")
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
