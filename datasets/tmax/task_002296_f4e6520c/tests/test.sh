#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import struct
import subprocess
import secrets
import pytest

RECOVER = "/home/user/recover.go"
TELEMETRY = "/home/user/telemetry.bin"
OUTPUT = "/home/user/recovered.csv"


def run_recover():
    if os.path.lexists(OUTPUT):
        os.unlink(OUTPUT)
    result = subprocess.run(
        ["go", "run", RECOVER],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f"recover.go failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


@pytest.fixture(scope="session", autouse=True)
def execute_on_customer_dump():
    with open(TELEMETRY, "rb") as f:
        original_telemetry = f.read()

    run_recover()
    yield

    with open(TELEMETRY, "wb") as f:
        f.write(original_telemetry)


def test_recovered_csv_exists():
    path = "/home/user/recovered.csv"
    assert os.path.isfile(path), f"Expected file {path} does not exist. Did you write the output to the correct location?"


def test_recovered_csv_content():
    path = "/home/user/recovered.csv"
    assert os.path.isfile(path), "Cannot check content because recovered.csv is missing."

    with open(path, "r") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = [
        "1,10.5000",
        "2,20.2500",
        "3,30.1250",
        "4,40.8750"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in recovered.csv, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in recovered.csv is incorrect. Expected '{expected}', got '{actual}'."


def test_recover_go_exists():
    path = "/home/user/recover.go"
    assert os.path.isfile(path), f"Expected file {path} does not exist. Did you create the Go script as requested?"


def test_recover_go_is_regular_nonempty_file():
    mode = os.lstat(RECOVER).st_mode
    assert stat.S_ISREG(mode), "recover.go must be a regular Go source file."
    assert os.path.getsize(RECOVER) > 0, "recover.go is empty."


def make_dump(records, garbage_after):
    data = bytearray(b"TELE")
    for index, (record_id, value, use_float32) in enumerate(records):
        data += struct.pack("<I", record_id)
        if use_float32:
            data += struct.pack("<f", value) + b"\xff\xff\xff\xff"
        else:
            data += struct.pack("<d", value)
        data += struct.pack("<I", 0xAABBCCDD)
        if index in garbage_after:
            data += garbage_after[index]
    return bytes(data)


def test_recover_go_handles_derived_unseen_inputs():
    base = 100000 + secrets.randbelow(800000)
    cases = [
        (
            [
                (base + 11, 7.125, False),
                (base + 22, 18.75, True),
                (base + 33, -3.5, False),
                (base + 44, 96.625, True),
            ],
            {1: b"\x12\x34\x56\x78\x90"},
        ),
        (
            [
                (base + 105, 0.875, True),
                (base + 206, 123.5, False),
                (base + 307, -42.25, True),
                (base + 408, 2048.125, False),
            ],
            {0: b"\x01\x99\x02", 2: b"brownout!"},
        ),
    ]

    for records, garbage_after in cases:
        fixture = make_dump(records, garbage_after)
        with open(TELEMETRY, "wb") as f:
            f.write(fixture)

        run_recover()
        assert os.path.isfile(OUTPUT), "Running recover.go did not create recovered.csv."
        with open(OUTPUT, "r", newline="") as f:
            actual = f.read().splitlines()

        expected = [f"{record_id},{value:.4f}" for record_id, value, _ in records]
        assert actual == expected, (
            "recover.go did not correctly recover a generated telemetry stream. "
            f"Expected {expected}, got {actual}."
        )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
