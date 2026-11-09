#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import base64
import os
import random
import string
import subprocess
import pytest

AGENT_PATH = "/home/user/encoder"
NUM_TESTS = 500


def test_agent_executable_exists():
    assert os.path.exists(AGENT_PATH), f"Agent executable not found at {AGENT_PATH}"
    assert os.path.isfile(AGENT_PATH), f"{AGENT_PATH} is not a file"
    assert os.access(AGENT_PATH, os.X_OK), f"{AGENT_PATH} is not executable"


def generate_random_input(length):
    chars = string.ascii_letters + string.digits
    return "".join(random.choice(chars) for _ in range(length)) + "\n"


def encode_varint(value):
    out = bytearray()
    while value >= 0x80:
        out.append((value & 0x7f) | 0x80)
        value >>= 7
    out.append(value)
    return bytes(out)


def expected_output(input_str):
    trimmed = input_str[:-1] if input_str.endswith("\n") else input_str
    encoded = base64.b64encode(trimmed[::-1].encode("utf-8"))

    # AssetInfo.data (field 1, wire type 2), followed by
    # AssetInfo.original_length (field 2, wire type 0).
    return (
        b"\x0a"
        + encode_varint(len(encoded))
        + encoded
        + b"\x10"
        + encode_varint(len(trimmed.encode("utf-8")))
    )


def test_fuzz_equivalence():
    random.seed(42)

    for i in range(NUM_TESTS):
        length = random.randint(5, 100)
        input_str = generate_random_input(length)
        input_bytes = input_str.encode("utf-8")

        agent_proc = subprocess.run(
            [AGENT_PATH],
            input=input_bytes,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
        )

        if agent_proc.returncode != 0:
            pytest.fail(
                f"Agent program failed (exit code {agent_proc.returncode}) "
                f"on input: {repr(input_str)}\n"
                f"Stderr: {agent_proc.stderr.decode('utf-8', errors='replace')}"
            )

        expected = expected_output(input_str)
        agent_out = agent_proc.stdout

        if expected != agent_out:
            pytest.fail(
                f"Output mismatch on input: {repr(input_str)}\n"
                f"Expected:    {expected.hex()}\n"
                f"Got (agent): {agent_out.hex()}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
