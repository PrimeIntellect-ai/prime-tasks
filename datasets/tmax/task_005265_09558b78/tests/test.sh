#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import struct
import subprocess
import tempfile
import pytest

AGENT_BIN = "/home/user/wal_compactor"
ORACLE_BIN = "/tests/oracle_compactor"

def generate_wal_file(path, corrupt=False):
    with open(path, 'wb') as f:
        if corrupt and random.random() < 0.5:
            # Bad magic
            f.write(b"BADv1\0\0\0")
        else:
            f.write(b"WALv1\0\0\0")

        num_records = random.randint(0, 1000) # Keep it reasonable for testing speed

        for _ in range(num_records):
            length = random.randint(6, 128) # Smaller lengths for speed
            if random.random() < 0.3:
                tx_type = 0x8C
            else:
                tx_type = random.randint(0, 255)

            if random.random() < 0.3:
                status = 0x05
            else:
                status = random.randint(0, 255)

            payload_len = length - 6
            payload = os.urandom(payload_len)

            record = struct.pack("<IBB", length, tx_type, status) + payload
            f.write(record)

        if corrupt:
            # Truncate
            f.seek(0, os.SEEK_END)
            size = f.tell()
            if size > 8:
                f.truncate(random.randint(8, size - 1))

def test_wal_compactor_fuzz_equivalence():
    assert os.path.isfile(AGENT_BIN), f"Agent binary not found at {AGENT_BIN}"
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary at {AGENT_BIN} is not executable"
    assert os.path.isfile(ORACLE_BIN), f"Oracle binary not found at {ORACLE_BIN}"

    random.seed(42)
    N = 200

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(N):
            input_wal = os.path.join(tmpdir, f"input_{i}.wal")
            oracle_out = os.path.join(tmpdir, f"oracle_out_{i}.wal")
            agent_out = os.path.join(tmpdir, f"agent_out_{i}.wal")

            corrupt = i < (N * 0.05)
            generate_wal_file(input_wal, corrupt=corrupt)

            oracle_proc = subprocess.run([ORACLE_BIN, input_wal, oracle_out], capture_output=True)
            agent_proc = subprocess.run([AGENT_BIN, input_wal, agent_out], capture_output=True)

            assert agent_proc.returncode == oracle_proc.returncode, \
                f"Exit code mismatch on test {i} (corrupt={corrupt}). Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"

            if oracle_proc.returncode == 0:
                assert os.path.exists(agent_out), f"Agent did not create output file for test {i}"
                with open(oracle_out, 'rb') as f1, open(agent_out, 'rb') as f2:
                    oracle_data = f1.read()
                    agent_data = f2.read()

                assert agent_data == oracle_data, \
                    f"Output file content mismatch on test {i}. Oracle size: {len(oracle_data)}, Agent size: {len(agent_data)}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
