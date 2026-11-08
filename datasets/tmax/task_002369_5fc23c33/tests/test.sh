#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import zlib
import struct
import subprocess
import pytest

def generate_ras_stream(seed, length=5000):
    random.seed(seed)
    out = bytearray()

    def make_valid_chunk():
        title = "Title: " + "".join(random.choices(string.ascii_letters, k=10)) + "\n"
        body = "".join(random.choices(string.ascii_letters + string.digits + " \n", k=random.randint(50, 500)))
        doc = (title + body).encode('utf-8')
        crc = zlib.crc32(doc) & 0xffffffff
        comp = zlib.compress(doc)
        return b'RAS\n' + struct.pack('<I', len(comp)) + comp + struct.pack('<I', crc)

    def make_corrupt_chunk():
        chunk = bytearray(make_valid_chunk())
        corruption_type = random.choice(['trunc', 'crc', 'zlib'])
        if corruption_type == 'trunc':
            return chunk[:-random.randint(1, 10)]
        elif corruption_type == 'crc':
            chunk[-1] = (chunk[-1] + 1) % 256
            return chunk
        elif corruption_type == 'zlib':
            if len(chunk) > 10:
                chunk[8] = (chunk[8] + 1) % 256
            return chunk
        return chunk

    while len(out) < length:
        if random.random() < 0.2:
            if random.random() < 0.7:
                out.extend(make_valid_chunk())
            else:
                out.extend(make_corrupt_chunk())
        else:
            out.append(random.randint(0, 255))

    return bytes(out)

def test_fuzz_equivalence():
    agent_script = "/home/user/doc_extractor.py"
    oracle_script = "/tests/oracle_extractor.py"

    assert os.path.exists(agent_script), f"Agent script {agent_script} is missing."
    assert os.path.exists(oracle_script), f"Oracle script {oracle_script} is missing."

    agent_cmd = ["python3", agent_script]
    oracle_cmd = ["python3", oracle_script]

    N = 100  # Number of random inputs to test
    for i in range(N):
        input_data = generate_ras_stream(i, length=random.randint(500, 50000))

        agent_proc = subprocess.run(agent_cmd, input=input_data, capture_output=True)
        oracle_proc = subprocess.run(oracle_cmd, input=input_data, capture_output=True)

        if agent_proc.returncode != oracle_proc.returncode or agent_proc.stdout != oracle_proc.stdout:
            error_msg = (
                f"Output mismatch on random input seed {i}.\n\n"
                f"Oracle return code: {oracle_proc.returncode}\n"
                f"Agent return code: {agent_proc.returncode}\n\n"
                f"Oracle stdout:\n{oracle_proc.stdout.decode('utf-8', errors='replace')}\n\n"
                f"Agent stdout:\n{agent_proc.stdout.decode('utf-8', errors='replace')}\n\n"
                f"Agent stderr:\n{agent_proc.stderr.decode('utf-8', errors='replace')}"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
