#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import binascii
import os
import stat
import subprocess
from pathlib import Path

import pytest

DROPper_PATH = Path("/home/user/dropper.go")
PAYLOAD_PATH = Path("/home/user/payload.dat")
DECODED_PATH = Path("/home/user/decoded.dat")
EXPECTED_TEXT = b"Suspicious dropper connecting to C2 at 203.0.113.85. Initiate sequence."


def run_dropper():
    DECODED_PATH.unlink(missing_ok=True)
    proc = subprocess.run(
        ["go", "run", "dropper.go"],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert proc.returncode == 0, (
        "Running /home/user/dropper.go failed:\n"
        + proc.stderr.decode("utf-8", errors="replace")
    )
    assert DECODED_PATH.is_file(), "The Go program did not create /home/user/decoded.dat"
    return DECODED_PATH.read_bytes()


def test_00_fixed_dropper_executes_and_decodes_deterministically():
    assert DROPper_PATH.exists(), "/home/user/dropper.go is missing"
    assert stat.S_ISREG(DROPper_PATH.lstat().st_mode), "/home/user/dropper.go must be a regular file"
    assert PAYLOAD_PATH.is_file(), "/home/user/payload.dat is missing"

    original_payload = PAYLOAD_PATH.read_bytes()
    expected_original = bytes(b ^ 0x42 for b in bytes.fromhex(original_payload.decode().strip()))
    assert expected_original == EXPECTED_TEXT

    try:
        # Exercise the submitted Go transformation on unpredictable payloads so
        # pre-creating the two requested output files cannot satisfy the task.
        for size in (97, 257):
            plaintext = os.urandom(size)
            encrypted = bytes(b ^ 0x42 for b in plaintext)
            PAYLOAD_PATH.write_bytes(binascii.hexlify(encrypted))
            outputs = [run_dropper() for _ in range(3)]
            assert outputs == [plaintext] * 3, (
                "dropper.go did not preserve chunk order or was not deterministic"
            )

        PAYLOAD_PATH.write_bytes(original_payload)
        outputs = [run_dropper() for _ in range(3)]
        assert outputs == [expected_original] * 3, (
            "dropper.go did not deterministically decode the intercepted payload"
        )
    finally:
        PAYLOAD_PATH.write_bytes(original_payload)
        try:
            run_dropper()
        except Exception:
            pass


def test_result_txt_content():
    result_path = "/home/user/result.txt"
    assert os.path.isfile(result_path), f"File {result_path} is missing. Did you save the IP address?"

    with open(result_path, "r") as f:
        content = f.read()

    assert content == "203.0.113.85", f"Content of {result_path} is incorrect. Expected exactly '203.0.113.85', but got '{content}'."


def test_decoded_dat_content():
    decoded_path = "/home/user/decoded.dat"
    assert os.path.isfile(decoded_path), f"File {decoded_path} is missing. Did you run the fixed Go script?"

    expected_text = "Suspicious dropper connecting to C2 at 203.0.113.85. Initiate sequence."
    with open(decoded_path, "r") as f:
        content = f.read().strip()

    assert content == expected_text, f"Content of {decoded_path} does not match the expected decrypted text. The Go script might still be assembling chunks out of order."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
