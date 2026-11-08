#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import subprocess
import cv2
import pytest

STUDENT_BIN = "/home/user/normalize"
VIDEO = "/app/diagnostic.mp4"


def calibration_factor():
    cap = cv2.VideoCapture(VIDEO)
    assert cap.isOpened(), f"Could not open diagnostic video at {VIDEO}"
    count = 0
    while True:
        ok, frame = cap.read()
        if not ok:
            break
        blue, green, red = frame.mean(axis=(0, 1))
        if green > 200 and red < 50 and blue < 50:
            count += 1
    cap.release()
    return count


def expected_output(data, n):
    if data[:4] == b"\x7fELF":
        e_type = int.from_bytes(data[0x10:0x12], "little")
        e_machine = int.from_bytes(data[0x12:0x14], "little")
        e_entry = int.from_bytes(data[0x18:0x20], "little")
        e_entry = (e_entry + n) & ((1 << 64) - 1)
        return f"ELF {e_type:04x} {e_machine:04x} {e_entry:016x}\n".encode()

    if data[:4] == b"WAL\x00":
        salt = int.from_bytes(data[8:12], "little")
        return f"WAL {salt ^ n:08x}\n".encode()

    utf8 = data.decode("utf-16-le").encode("utf-8")
    prefix = utf8[:n]
    normalized = bytes(b if 0x20 <= b <= 0x7e else ord(".") for b in prefix)
    return normalized + b"\n"


def valid_utf16_input(rng):
    units = []
    while len(units) < 32:
        if len(units) <= 30 and rng.random() < 0.20:
            cp = rng.randint(0x10000, 0x10ffff)
            value = cp - 0x10000
            units.append(0xd800 + (value >> 10))
            units.append(0xdc00 + (value & 0x3ff))
        else:
            cp = rng.randint(0, 0xffff)
            while 0xd800 <= cp <= 0xdfff:
                cp = rng.randint(0, 0xffff)
            units.append(cp)

    data = b"".join(unit.to_bytes(2, "little") for unit in units)
    if data[:4] in (b"\x7fELF", b"WAL\x00"):
        units[0] ^= 1
        data = b"".join(unit.to_bytes(2, "little") for unit in units)
    return data


def test_fuzz_equivalence():
    assert os.path.isfile(STUDENT_BIN), f"Student binary not found at {STUDENT_BIN}"
    assert os.access(STUDENT_BIN, os.X_OK), f"Student binary {STUDENT_BIN} is not executable"
    assert os.path.isfile(VIDEO), f"Diagnostic video not found at {VIDEO}"

    n = calibration_factor()
    rng = random.Random(42)
    test_cases = []

    for _ in range(1000):
        choice = rng.random()
        if choice < 0.33:
            buf = bytearray(rng.getrandbits(8) for _ in range(64))
            buf[0:4] = b"\x7fELF"
            test_cases.append(bytes(buf))
        elif choice < 0.66:
            buf = bytearray(rng.getrandbits(8) for _ in range(64))
            buf[0:4] = b"WAL\x00"
            test_cases.append(bytes(buf))
        else:
            test_cases.append(valid_utf16_input(rng))

    for i, input_data in enumerate(test_cases):
        expected = expected_output(input_data, n)
        try:
            proc = subprocess.run(
                [STUDENT_BIN],
                input=input_data,
                capture_output=True,
                timeout=1
            )
        except subprocess.TimeoutExpired:
            pytest.fail(f"Student program timed out on input {input_data.hex()}")

        if proc.returncode != 0:
            pytest.fail(
                f"Student program crashed or returned non-zero on input "
                f"{input_data.hex()}\nStderr: {proc.stderr}"
            )

        assert proc.stdout == expected, (
            f"Mismatch on iteration {i}.\n"
            f"Input (hex): {input_data.hex()}\n"
            f"Expected output (hex): {expected.hex()}\n"
            f"Actual output (hex): {proc.stdout.hex()}\n"
            f"Expected output (text): {expected}\n"
            f"Actual output (text): {proc.stdout}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
