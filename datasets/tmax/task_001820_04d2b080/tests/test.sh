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

AGENT_BIN = "/home/user/token_v2"
AGENT_SOURCE = "/home/user/token_v2.c"
SOURCE_BIN = "/tmp/token_v2_from_source"


def expected_output(input_str):
    data = b"SECURE|" + input_str.encode("ascii")
    transformed = bytes(byte ^ 0x5A for byte in data)
    return base64.b64encode(transformed).decode("ascii") + "\n"


def test_agent_binary_exists():
    assert os.path.isfile(AGENT_BIN), (
        f"Agent binary {AGENT_BIN} does not exist. "
        "Did you compile your code to the correct location?"
    )
    assert os.access(AGENT_BIN, os.X_OK), f"Agent binary {AGENT_BIN} is not executable."


def test_agent_source_exists_and_compiles():
    assert os.path.isfile(AGENT_SOURCE), f"Required C source {AGENT_SOURCE} does not exist."
    result = subprocess.run(
        ["gcc", "-O2", AGENT_SOURCE, "-o", SOURCE_BIN],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, f"Failed to compile {AGENT_SOURCE}:\n{result.stderr}"
    assert os.path.isfile(SOURCE_BIN) and os.access(SOURCE_BIN, os.X_OK)


def test_fuzz_equivalence():
    assert os.path.isfile(AGENT_BIN), f"Agent binary {AGENT_BIN} missing."
    assert os.path.isfile(SOURCE_BIN), "The submitted C source was not successfully compiled."

    random.seed(42)
    charset = string.ascii_letters + string.digits

    for _ in range(100):
        length = random.randint(5, 50)
        input_str = "".join(random.choice(charset) for _ in range(length))
        expected = expected_output(input_str)

        for binary, description in (
            (AGENT_BIN, "Your binary"),
            (SOURCE_BIN, "The binary compiled from your source"),
        ):
            try:
                result = subprocess.run(
                    [binary, input_str], capture_output=True, text=True, timeout=2
                )
            except subprocess.TimeoutExpired:
                pytest.fail(f"{description} timed out on input: {input_str}")

            assert result.returncode == 0, (
                f"Return code mismatch for {description} on input '{input_str}'. "
                f"Expected 0, got {result.returncode}."
            )
            assert result.stdout == expected, (
                f"Output mismatch for {description} on input '{input_str}'.\n"
                f"Expected output:\n{expected}\n"
                f"Got output:\n{result.stdout}"
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
