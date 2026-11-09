#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import subprocess
import tempfile
import pytest


def run_with_timeout(argv, timeout=1.0):
    try:
        return subprocess.run(
            argv,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=timeout,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"Command timed out after {timeout} seconds: {argv}")


def exercise_parser(bin_path):
    # Derive several valid and corrupted records independently of bad_payload.bin.
    cases = [
        (bytes([]), 0),
        (bytes([0]), 0),
        (bytes([1, 0x37]), 0),
        (bytes([2, 0x10, 0x20]), 0),
        (bytes([1]), 0),
        (bytes([3, 0x44]), 0),
        (bytes([17, 0x01, 0x02, 0x03]), 0),
        (bytes([255]), 0),
        (bytes([255, 0x41]), 0),
    ]

    with tempfile.TemporaryDirectory() as td:
        for index, (payload, expected_status) in enumerate(cases):
            payload_path = os.path.join(td, f"case_{index}.bin")
            with open(payload_path, "wb") as f:
                f.write(payload)

            result = run_with_timeout([bin_path, payload_path])
            assert result.returncode == expected_status, (
                f"Parser failed on generated case {index} ({payload.hex()}): "
                f"exit={result.returncode}, stderr={result.stderr.decode(errors='replace')}"
            )


def test_report_txt():
    report_path = "/home/user/report.txt"
    assert os.path.isfile(report_path), f"File {report_path} does not exist."

    with open(report_path, "r") as f:
        lines = [line.strip() for line in f.read().strip().split('\n')]

    assert len(lines) == 3, f"Expected exactly 3 lines in {report_path}, found {len(lines)}."
    assert lines[0] == "REQ-1004", f"Line 1 of report.txt is incorrect. Expected 'REQ-1004', got '{lines[0]}'."
    assert lines[1] == "FF41", f"Line 2 of report.txt is incorrect. Expected 'FF41', got '{lines[1]}'."
    assert lines[2] == "FIXED", f"Line 3 of report.txt is incorrect. Expected 'FIXED', got '{lines[2]}'."


def test_bad_payload_bin():
    payload_path = "/home/user/bad_payload.bin"
    assert os.path.isfile(payload_path), f"File {payload_path} does not exist."

    with open(payload_path, "rb") as f:
        content = f.read()

    assert len(content) == 2, f"Expected {payload_path} to be exactly 2 bytes, but it is {len(content)} bytes."
    assert content[0] == 0xFF, f"First byte of {payload_path} is incorrect. Expected 0xFF."
    assert content[1] == 0x41, f"Second byte of {payload_path} is incorrect. Expected 0x41."


def test_telemetry_parser_executable():
    bin_path = "/home/user/bin/telemetry_parser"
    assert os.path.isfile(bin_path), f"Executable {bin_path} does not exist."
    assert os.access(bin_path, os.X_OK), f"File {bin_path} is not executable."

    with open(bin_path, "rb") as f:
        magic = f.read(4)
    assert magic == b"\x7fELF", (
        f"{bin_path} is not a compiled ELF executable; shell scripts and other stubs are not accepted."
    )


def test_telemetry_parser_execution():
    bin_path = "/home/user/bin/telemetry_parser"
    payload_path = "/home/user/bad_payload.bin"

    assert os.path.isfile(bin_path), "Executable missing, cannot test execution."
    assert os.path.isfile(payload_path), "Payload file missing, cannot test execution."

    try:
        result = subprocess.run(
            [bin_path, payload_path],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=1.0
        )
    except subprocess.TimeoutExpired:
        pytest.fail("The executable timed out after 1 second. The livelock bug is likely not fixed.")

    assert result.returncode == 0, f"Executable returned non-zero exit code: {result.returncode}. Stderr: {result.stderr.decode()}"


def test_submitted_parser_cli_and_generated_inputs():
    bin_path = "/home/user/bin/telemetry_parser"

    no_args = run_with_timeout([bin_path])
    assert no_args.returncode == 1, "The compiled parser must retain its no-argument error behavior."
    assert b"Usage:" in no_args.stderr and b"<binary_file>" in no_args.stderr, (
        "The executable does not expose the telemetry parser's expected command-line interface."
    )

    missing = run_with_timeout([bin_path, "/tmp/definitely_missing_telemetry_payload.bin"])
    assert missing.returncode == 1, "The parser must reject a nonexistent input file."

    exercise_parser(bin_path)


def test_fixed_source_compiles_and_handles_generated_corruption():
    source_path = "/home/user/src/telemetry_parser.cpp"
    rebuilt_path = "/tmp/telemetry_parser_rebuilt_for_verification"
    assert os.path.isfile(source_path), f"Source file {source_path} does not exist."

    build = subprocess.run(
        ["g++", "-std=c++17", source_path, "-o", rebuilt_path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert build.returncode == 0, (
        "The submitted C++ source does not compile: "
        + build.stderr.decode(errors="replace")
    )
    assert os.path.isfile(rebuilt_path) and os.access(rebuilt_path, os.X_OK)

    # This directly checks the source-level root-cause fix rather than trusting
    # only the executable placed in /home/user/bin.
    exercise_parser(rebuilt_path)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
