#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import random
import subprocess
import pytest

def generate_fuzz_input(seed):
    random.seed(seed)
    length = random.randint(0, 1600)
    out = bytearray()

    seen_ids = []
    last_val = 0

    while len(out) < length:
        chunk_len = min(32, length - len(out))
        if chunk_len < 32:
            out.extend(bytes([random.randint(0, 255) for _ in range(chunk_len)]))
            break

        chunk = bytearray(32)

        # Generate ID (8 bytes)
        if seen_ids and random.random() < 0.2:
            id_str = random.choice(seen_ids)
        else:
            id_str = "".join(random.choice("ABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789") for _ in range(8))
            seen_ids.append(id_str)

        chunk[0:8] = id_str.encode('iso-8859-1')

        # Generate Value (8 bytes)
        rand_choice = random.random()
        if rand_choice < 0.1:
            # Anomaly: jump > 50
            val = last_val + random.choice([-1, 1]) * random.randint(51, 1000)
            val_str = f"{val:8d}"[:8]
            chunk[8:16] = val_str.encode('iso-8859-1')
            last_val = val
        elif rand_choice < 0.2:
            # Invalid parse
            chunk[8:16] = bytes([random.randint(65, 90) for _ in range(8)])
        else:
            # Normal: jump <= 50
            val = last_val + random.choice([-1, 1]) * random.randint(0, 50)
            val_str = f"{val:8d}"[:8]
            chunk[8:16] = val_str.encode('iso-8859-1')
            last_val = val

        # Remaining 16 bytes (random ISO-8859-1 valid-ish characters)
        chunk[16:32] = bytes([random.randint(32, 255) for _ in range(16)])

        out.extend(chunk)

    return bytes(out)

def test_fuzz_equivalence():
    oracle_path = "/tests/oracle_processor"
    agent_path = "/home/user/processor"

    assert os.path.exists(oracle_path), f"Oracle not found at {oracle_path}"
    assert os.path.exists(agent_path), f"Agent program not found at {agent_path}"
    assert os.access(agent_path, os.X_OK), f"Agent program at {agent_path} is not executable"

    inputs = [generate_fuzz_input(i) for i in range(1000)]
    expected_outputs = []

    # Obtain all expected outputs before invoking the submission, then remove the
    # uploaded oracle so the submitted executable cannot delegate its work to it.
    try:
        for inp in inputs:
            oracle_proc = subprocess.run([oracle_path], input=inp, capture_output=True)
            expected_outputs.append(oracle_proc.stdout)
    finally:
        if os.path.exists(oracle_path):
            os.remove(oracle_path)

    for i, (inp, expected) in enumerate(zip(inputs, expected_outputs)):
        agent_proc = subprocess.run([agent_path], input=inp, capture_output=True)

        if expected != agent_proc.stdout:
            error_msg = (
                f"Mismatch on fuzz iteration {i} (seed {i}).\n"
                f"Input length: {len(inp)} bytes\n"
                f"Oracle output:\n{expected.decode('utf-8', errors='replace')}\n"
                f"Agent output:\n{agent_proc.stdout.decode('utf-8', errors='replace')}\n"
            )
            pytest.fail(error_msg)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
