#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import sys
import json
import zlib
import random
import struct
import subprocess
import tempfile
import pytest

ORACLE_PATH = "/tests/oracle_parse_dump"
AGENT_SCRIPT = "/home/user/parse_dump.py"
MAGIC = b'\x7b\x3f'
SALT = b'559102'

def generate_random_string(length):
    return "".join(chr(random.randint(32, 126)) for _ in range(length))

def generate_record(valid=True):
    file_id = random.randint(1, 10000)
    path = f"/path/to/{generate_random_string(10)}"
    symlink_target = f"/target/{generate_random_string(10)}" if random.choice([True, False]) else ""

    payload_dict = {
        "file_id": file_id,
        "path": path,
        "symlink_target": symlink_target
    }
    payload_bytes = json.dumps(payload_dict).encode('utf-8')

    if not valid and random.choice([True, False]):
        # Corrupt JSON
        payload_bytes = payload_bytes[:-1]

    payload_len = len(payload_bytes)

    if valid:
        checksum = zlib.crc32(payload_bytes + SALT) & 0xFFFFFFFF
    else:
        checksum = random.randint(0, 0xFFFFFFFF)

    magic = MAGIC if valid or random.choice([True, False]) else os.urandom(2)

    return magic + struct.pack("<I", payload_len) + payload_bytes + struct.pack("<I", checksum)

def generate_fuzz_file(filepath):
    size = random.randint(1024, 5 * 1024 * 1024)
    with open(filepath, 'wb') as f:
        written = 0
        num_records = random.randint(0, 50)

        # We will write random noise and interspersed records
        records = [generate_record(valid=random.choice([True, False, True])) for _ in range(num_records)]

        while written < size and records:
            noise_len = random.randint(0, min(10000, size - written))
            f.write(os.urandom(noise_len))
            written += noise_len

            if records and written < size:
                rec = records.pop(0)
                f.write(rec)
                written += len(rec)

        if written < size:
            f.write(os.urandom(size - written))

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_SCRIPT), f"Agent script not found at {AGENT_SCRIPT}"
    assert os.path.isfile(ORACLE_PATH), f"Oracle script not found at {ORACLE_PATH}"

    random.seed(42)
    num_tests = 200

    with tempfile.TemporaryDirectory() as temp_dir:
        for i in range(num_tests):
            fuzz_file = os.path.join(temp_dir, f"fuzz_{i}.bin")
            generate_fuzz_file(fuzz_file)

            # Run oracle supplied only at verification time
            oracle_cmd = [sys.executable, ORACLE_PATH, fuzz_file]
            oracle_proc = subprocess.run(oracle_cmd, capture_output=True, text=True)

            # Run agent
            agent_cmd = [sys.executable, AGENT_SCRIPT, fuzz_file]
            agent_proc = subprocess.run(agent_cmd, capture_output=True, text=True)

            # Compare outputs
            assert agent_proc.returncode == oracle_proc.returncode, f"Return code mismatch on {fuzz_file}. Oracle: {oracle_proc.returncode}, Agent: {agent_proc.returncode}"
            assert agent_proc.stdout == oracle_proc.stdout, f"Stdout mismatch on {fuzz_file}.\nOracle:\n{oracle_proc.stdout}\nAgent:\n{agent_proc.stdout}"

            os.remove(fuzz_file)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
