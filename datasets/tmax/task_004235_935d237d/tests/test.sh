#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import random
import string
import tempfile
import struct
import pytest

def generate_random_string(length):
    return ''.join(random.choices(string.ascii_letters + string.digits, k=length)).encode('ascii')

def generate_wal_file(path, add_incomplete=False):
    with open(path, 'wb') as f:
        f.write(b'CWAL')

        num_records = random.randint(5, 150)
        for _ in range(num_records):
            op = random.choice([0x1A, 0x1B, 0x1C])
            key_len = random.randint(1, 50)
            key = generate_random_string(key_len)

            f.write(struct.pack('<B', op))
            f.write(struct.pack('<H', key_len))
            f.write(key)

            if op in (0x1A, 0x1C):
                val_len = random.randint(1, 50)
                val = generate_random_string(val_len)
                f.write(struct.pack('<H', val_len))
                f.write(val)

        if add_incomplete:
            # write partial record to simulate EOF edge case
            op = random.choice([0x1A, 0x1B, 0x1C])
            f.write(struct.pack('<B', op))
            key_len = random.randint(10, 50)
            f.write(struct.pack('<H', key_len))
            f.write(generate_random_string(key_len // 2)) # incomplete key

def test_wal_parser_fuzz_equivalence():
    oracle_path = "/tests/oracle_wal_parser"
    agent_path = "/home/user/wal_parser"

    assert os.path.isfile(agent_path), f"Agent executable {agent_path} not found."
    assert os.access(agent_path, os.X_OK), f"Agent executable {agent_path} is not executable."

    random.seed(42)

    with tempfile.TemporaryDirectory() as tmpdir:
        for i in range(100):
            wal_path = os.path.join(tmpdir, f"test_{i}.wal")
            add_incomplete = random.choice([True, False])
            generate_wal_file(wal_path, add_incomplete=add_incomplete)

            oracle_proc = subprocess.run([oracle_path, wal_path], capture_output=True, text=True)
            agent_proc = subprocess.run([agent_path, wal_path], capture_output=True, text=True)

            assert agent_proc.stdout == oracle_proc.stdout, (
                f"Output mismatch on generated WAL file (iteration {i}, incomplete record at EOF: {add_incomplete}).\n"
                f"Oracle stdout:\n{oracle_proc.stdout}\n"
                f"Agent stdout:\n{agent_proc.stdout}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
