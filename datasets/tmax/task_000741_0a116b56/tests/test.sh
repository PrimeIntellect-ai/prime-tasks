#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import sys
import random
import subprocess
import pytest

ORACLE_PATH = "/tmp/oracle_archiver.py"
AGENT_PATH = "/home/user/archiver.py"

ORACLE_CODE = """\
import sys
import lzma

def archive(input_path, output_path):
    with open(input_path, 'rb') as f:
        data = f.read()

    header = b"BKUP2024"

    transformed = bytearray()
    for b in data:
        if 97 <= b <= 122: # 'a' to 'z'
            transformed.append(b + 1)
        else:
            transformed.append(b)

    payload = header + transformed
    compressed = lzma.compress(payload)

    with open(output_path, 'wb') as f:
        f.write(compressed)

if __name__ == "__main__":
    archive(sys.argv[1], sys.argv[2])
"""

def setup_oracle():
    with open(ORACLE_PATH, "w") as f:
        f.write(ORACLE_CODE)

def test_archiver_fuzz_equivalence():
    assert os.path.isfile(AGENT_PATH), f"Agent script not found at {AGENT_PATH}"
    setup_oracle()

    random.seed(42)

    # Generate test cases
    test_cases = []
    test_cases.append(b"")  # Empty
    test_cases.append(b"\x00" * 1000)  # All nulls
    test_cases.append(b"abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789")  # ASCII

    # Random binary data
    for _ in range(20):
        length = random.randint(1, 100000)
        test_cases.append(bytearray(random.getrandbits(8) for _ in range(length)))

    for i, data in enumerate(test_cases):
        input_file = f"/tmp/input_{i}.bin"
        oracle_out = f"/tmp/oracle_out_{i}.bin"
        agent_out = f"/tmp/agent_out_{i}.bin"

        with open(input_file, "wb") as f:
            f.write(data)

        # Run oracle
        subprocess.run([sys.executable, ORACLE_PATH, input_file, oracle_out], check=True)

        # Run agent
        result = subprocess.run(
            [sys.executable, AGENT_PATH, input_file, agent_out],
            capture_output=True,
            text=True
        )
        assert result.returncode == 0, f"Agent script failed on input {i} (len {len(data)}).\nStderr: {result.stderr}"

        assert os.path.isfile(agent_out), f"Agent script did not produce output file {agent_out}"

        with open(oracle_out, "rb") as f:
            oracle_data = f.read()
        with open(agent_out, "rb") as f:
            agent_data = f.read()

        assert agent_data == oracle_data, f"Output mismatch on input {i} (len {len(data)}). Agent output does not match oracle bit-for-bit."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
