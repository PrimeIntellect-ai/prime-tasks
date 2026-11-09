#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import struct
import subprocess

AGENT_PATH = "/home/user/config_parser"
NUM_TESTS = 500


def generate_random_chunk():
    num_codepoints = random.randint(0, 2000)
    chars = []
    for _ in range(num_codepoints):
        cp = random.randint(0, 0x10FFFF)
        if 0xD800 <= cp <= 0xDFFF:
            cp = random.randint(0, 0xD7FF)
        chars.append(chr(cp))

    utf16_bytes = "".join(chars).encode("utf-16le")
    char_count = len(utf16_bytes) // 2
    return struct.pack("<I", char_count) + utf16_bytes


def generate_input(truncate=False):
    num_chunks = random.randint(0, 50)
    data = b"".join(generate_random_chunk() for _ in range(num_chunks))
    if truncate and data:
        data = data[:random.randint(0, len(data) - 1)]
    return data


def expected_result(data):
    offset = 0
    output = bytearray()

    while offset < len(data):
        if len(data) - offset < 4:
            return 1, bytes(output)

        char_count = struct.unpack_from("<I", data, offset)[0]
        offset += 4
        payload_size = char_count * 2

        if len(data) - offset < payload_size:
            return 1, bytes(output)

        payload = data[offset:offset + payload_size]
        offset += payload_size
        output.extend(payload.decode("utf-16le").encode("utf-8"))
        output.extend(b"\n")

    return 0, bytes(output)


def test_agent_binary_exists():
    assert os.path.isfile(AGENT_PATH), f"Agent binary not found at {AGENT_PATH}"
    assert os.access(AGENT_PATH, os.X_OK), f"Agent binary at {AGENT_PATH} is not executable"


def test_fuzz_equivalence():
    random.seed(42)
    partial_headers = [b"\x01", b"\x01\x00", b"\x01\x00\x00"]

    for i in range(NUM_TESTS):
        if i < len(partial_headers):
            input_data = partial_headers[i]
            is_truncated = True
        else:
            is_truncated = (i % 10 == 0)
            input_data = generate_input(truncate=is_truncated)

        expected_code, expected_stdout = expected_result(input_data)
        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_data,
            capture_output=True
        )

        assert agent_proc.returncode == expected_code, (
            f"Return code mismatch on test {i} (truncated={is_truncated}). "
            f"Expected {expected_code}, got {agent_proc.returncode}."
        )
        assert agent_proc.stdout == expected_stdout, (
            f"Stdout mismatch on test {i} (truncated={is_truncated}). "
            f"Input length: {len(input_data)} bytes."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
