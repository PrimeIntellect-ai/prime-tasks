#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import random
import string
import struct
import subprocess
import pytest

ORACLE_PATH = "/tests/oracle_wal_tracker"
AGENT_PATH = "/home/user/wal_tracker"
N_TESTS = 5000

def generate_random_wal_stream(seed):
    rng = random.Random(seed)

    # 50% chance of valid magic bytes
    if rng.random() < 0.5:
        data = bytearray([0x57, 0x41, 0x4C, 0x43, 0x01, 0x00])
    else:
        # Invalid magic bytes
        data = bytearray(rng.getrandbits(8) for _ in range(6))
        return bytes(data)

    num_records = rng.randint(0, 100)
    for _ in range(num_records):
        # 10% chance of invalid opcode
        if rng.random() < 0.1:
            opcode = rng.choice([3, 4, 5, 255, 128])
        else:
            opcode = rng.choice([0, 1, 2])

        data.append(opcode)

        k_len = rng.randint(1, 20)
        data.append(k_len)
        key_chars = ''.join(rng.choices(string.ascii_letters + string.digits, k=k_len))
        data.extend(key_chars.encode('ascii'))

        v_len = rng.randint(0, 50)
        data.extend(struct.pack('<H', v_len))
        val_chars = ''.join(rng.choices(string.ascii_letters + string.digits, k=v_len))
        data.extend(val_chars.encode('ascii'))

        if opcode not in [0, 1, 2]:
            # Invalid opcode terminates generation as well (since it terminates parsing)
            break

    # 10% chance of truncation
    if rng.random() < 0.1 and len(data) > 6:
        trunc_len = rng.randint(6, len(data) - 1)
        data = data[:trunc_len]

    return bytes(data)

def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}. Did you compile it?"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent executable {AGENT_PATH} is not executable."

    for i in range(N_TESTS):
        input_data = generate_random_wal_stream(i)

        oracle_proc = subprocess.run(
            [ORACLE_PATH],
            input=input_data,
            capture_output=True
        )

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            capture_output=True
        )

        if oracle_proc.returncode != agent_proc.returncode or oracle_proc.stdout != agent_proc.stdout:
            error_msg = f"Mismatch on fuzz seed {i}!\n"
            error_msg += f"Input length: {len(input_data)} bytes\n"
            error_msg += f"Input hex: {input_data.hex()}\n\n"
            error_msg += f"Oracle Return Code: {oracle_proc.returncode}\n"
            error_msg += f"Agent Return Code: {agent_proc.returncode}\n\n"
            error_msg += f"Oracle stdout:\n{oracle_proc.stdout.decode('utf-8', errors='replace')}\n"
            error_msg += f"Agent stdout:\n{agent_proc.stdout.decode('utf-8', errors='replace')}\n"
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
