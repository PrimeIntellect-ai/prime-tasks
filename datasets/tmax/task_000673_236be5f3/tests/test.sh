#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess

SCRIPT = "/home/user/process_logs.py"
LOG = "/home/user/processor.log"
AGGREGATE = "/home/user/aggregate.txt"
MAGIC = 0xDEADBEEF


def run_parser(log_data):
    with open(LOG, "wb") as f:
        f.write(log_data)
    with open(AGGREGATE, "w") as f:
        f.write("SENTINEL")

    result = subprocess.run(
        ["python3", SCRIPT],
        capture_output=True,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"process_logs.py exited with code {result.returncode}. "
        f"Stderr: {result.stderr}"
    )
    assert os.path.exists(AGGREGATE), "process_logs.py did not create aggregate.txt"
    with open(AGGREGATE, "r") as f:
        aggregate = f.read().strip()
    return result.stdout.strip(), aggregate


def record(input_id, result):
    return struct.pack("<IIQ", MAGIC, input_id, result)


def test_trigger_txt():
    path = "/home/user/trigger.txt"
    assert os.path.exists(path), f"File {path} does not exist."
    with open(path, "r") as f:
        content = f.read().strip()
    assert content == "31337", f"Expected trigger.txt to contain '31337', but got '{content}'"


def test_process_logs_execution():
    assert os.path.exists(SCRIPT), f"File {SCRIPT} does not exist."
    assert os.path.isfile(SCRIPT), f"File {SCRIPT} is not a regular file."

    result = subprocess.run(
        ["python3", SCRIPT],
        capture_output=True,
        text=True,
        timeout=10,
    )

    assert result.returncode == 0, f"process_logs.py exited with code {result.returncode}. Stderr: {result.stderr}"
    stdout_stripped = result.stdout.strip()
    assert stdout_stripped == "CORRUPTION_DETECTED", f"Expected stdout to be 'CORRUPTION_DETECTED', but got '{stdout_stripped}'"


def test_aggregate_txt():
    assert os.path.exists(AGGREGATE), f"File {AGGREGATE} does not exist. process_logs.py might not have created it."
    with open(AGGREGATE, "r") as f:
        content = f.read().strip()
    assert content == "600", f"Expected aggregate.txt to contain '600', but got '{content}'"


def test_parser_on_derived_inputs_and_corruption_modes():
    with open(LOG, "rb") as f:
        original_log = f.read()

    try:
        entries = [
            (secrets.randbelow(2**32), secrets.randbelow(10**9) + 1)
            for _ in range(secrets.randbelow(4) + 2)
        ]
        valid_data = b"".join(record(i, value) for i, value in entries)
        expected_total = sum(value for _, value in entries)

        stdout, aggregate = run_parser(valid_data)
        assert stdout == "", f"Valid log unexpectedly reported corruption: {stdout!r}"
        assert aggregate == str(expected_total), (
            f"Valid randomized records should aggregate to {expected_total}, got {aggregate!r}"
        )

        prefix_entries = [
            (secrets.randbelow(2**32), secrets.randbelow(10**8) + 1)
            for _ in range(secrets.randbelow(3) + 1)
        ]
        prefix = b"".join(record(i, value) for i, value in prefix_entries)
        prefix_total = sum(value for _, value in prefix_entries)

        invalid_magic = MAGIC
        while invalid_magic == MAGIC:
            invalid_magic = secrets.randbelow(2**32)
        invalid_header_log = prefix + struct.pack("<IIQ", invalid_magic, 17, 999999) + record(18, 123)

        malformed_trigger_record = (
            b"\xEF\xBE\xAD"
            + struct.pack("<I", secrets.randbelow(2**32))
            + struct.pack("<Q", secrets.randbelow(10**8))
        )
        misaligned_log = prefix + malformed_trigger_record + record(19, 456)

        eof_cases = [
            prefix + struct.pack("<I", MAGIC)[:secrets.randbelow(3) + 1],
            prefix + struct.pack("<I", MAGIC) + struct.pack("<I", 20)[:secrets.randbelow(3) + 1],
            prefix + struct.pack("<II", MAGIC, 21) + struct.pack("<Q", 789)[:secrets.randbelow(7) + 1],
        ]

        cases = [invalid_header_log, misaligned_log] + eof_cases
        for index, data in enumerate(cases):
            stdout, aggregate = run_parser(data)
            assert stdout == "CORRUPTION_DETECTED", (
                f"Corruption case {index} did not print exactly CORRUPTION_DETECTED; got {stdout!r}"
            )
            assert aggregate == str(prefix_total), (
                f"Corruption case {index} should preserve only the pre-corruption total "
                f"{prefix_total}, got {aggregate!r}"
            )
    finally:
        with open(LOG, "wb") as f:
            f.write(original_log)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
