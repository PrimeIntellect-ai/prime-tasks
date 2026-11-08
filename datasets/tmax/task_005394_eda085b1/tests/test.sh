#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import tempfile
import struct
import pytest

def generate_test_cases(n=1000, seed=42):
    random.seed(seed)
    cases = []
    for i in range(n):
        length = random.randint(0, 1024)

        r = random.random()
        if r < 0.25:
            # 25% valid (correct header + checksum)
            length = max(8, length)
            payload = bytearray(random.getrandbits(8) for _ in range(length - 8))
            checksum = sum(payload) % 65536
            data = b'MLST' + struct.pack('<H', 2) + struct.pack('<H', checksum) + payload
        elif r < 0.50:
            # 25% MLST but invalid
            if length < 4:
                data = bytearray(random.getrandbits(8) for _ in range(length))
            else:
                data = bytearray(random.getrandbits(8) for _ in range(length))
                data[0:4] = b'MLST'
                if length >= 8 and random.random() < 0.5:
                    # Make version wrong
                    data[4:6] = struct.pack('<H', random.choice([0, 1, 3, 4]))
        else:
            # 50% random
            data = bytearray(random.getrandbits(8) for _ in range(length))
            if len(data) >= 4 and data[:4] == b'MLST':
                data[0] = 0x00
        cases.append(bytes(data))
    return cases

def test_fuzz_equivalence():
    oracle = "/app/mail_config_validator"
    agent = "/home/user/new_validator"

    assert os.path.exists(agent), f"Agent program missing: {agent}"
    assert os.access(agent, os.X_OK), f"Agent program is not executable: {agent}"

    cases = generate_test_cases()

    with tempfile.TemporaryDirectory() as tmpdir:
        for i, data in enumerate(cases):
            filepath = os.path.join(tmpdir, f"test_{i}.bin")
            with open(filepath, "wb") as f:
                f.write(data)

            oracle_res = subprocess.run([oracle, filepath], capture_output=True, text=True)
            agent_res = subprocess.run([agent, filepath], capture_output=True, text=True)

            assert oracle_res.returncode == agent_res.returncode, (
                f"Return code mismatch on input {i} (len={len(data)}). "
                f"Oracle: {oracle_res.returncode}, Agent: {agent_res.returncode}"
            )
            assert oracle_res.stdout == agent_res.stdout, (
                f"Stdout mismatch on input {i} (len={len(data)}). "
                f"Oracle: {oracle_res.stdout!r}, Agent: {agent_res.stdout!r}"
            )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
