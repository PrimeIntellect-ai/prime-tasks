#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import struct
import subprocess
from contextlib import contextmanager

import pytest

DB_PATH = "/home/user/data/sensor.db"
BINARY_PATH = "/home/user/sensor_logger"
SOURCE_PATH = "/home/user/sensor_logger.c"


@contextmanager
def preserved_database():
    existed = os.path.exists(DB_PATH)
    original = None
    if existed:
        with open(DB_PATH, "rb") as f:
            original = f.read()
    try:
        yield
    finally:
        if existed:
            with open(DB_PATH, "wb") as f:
                f.write(original)
        elif os.path.exists(DB_PATH):
            os.remove(DB_PATH)


def run_and_check_append(executable, timestamp, sensor_id, value, env=None):
    prefix = os.urandom(13)
    expected_record = struct.pack("<IHi", timestamp, sensor_id, value)

    with preserved_database():
        with open(DB_PATH, "wb") as f:
            f.write(prefix)

        try:
            result = subprocess.run(
                [executable, str(timestamp), str(sensor_id), str(value)],
                capture_output=True,
                timeout=5,
                env=env,
            )
        except subprocess.TimeoutExpired:
            pytest.fail("The sensor_logger binary timed out, indicating a possible infinite loop or deadlock.")

        assert result.returncode == 0, (
            f"The sensor_logger binary crashed or returned non-zero exit code ({result.returncode}) "
            f"for ({timestamp}, {sensor_id}, {value}).\n"
            f"Stderr: {result.stderr.decode('utf-8', errors='ignore')}"
        )

        with open(DB_PATH, "rb") as f:
            actual = f.read()

        assert actual == prefix + expected_record, (
            "sensor_logger did not append exactly one correctly encoded 10-byte record.\n"
            f"Expected appended bytes: {expected_record.hex()}\n"
            f"Actual database bytes: {actual.hex()}"
        )


def test_recovered_csv():
    csv_path = "/home/user/data/recovered.csv"
    assert os.path.isfile(csv_path), f"Expected recovered CSV file at {csv_path} does not exist."

    with open(csv_path, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "1600000000,1,25",
        "1600000005,2,42",
        "1600000010,1,18"
    ]

    assert lines == expected_lines, (
        f"Contents of {csv_path} are incorrect.\n"
        f"Expected:\n{expected_lines}\n"
        f"Got:\n{lines}"
    )


def test_sensor_logger_binary_fixed():
    assert os.path.isfile(BINARY_PATH), f"Binary {BINARY_PATH} is missing."
    assert os.access(BINARY_PATH, os.X_OK), f"Binary {BINARY_PATH} is not executable."

    with open(BINARY_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "sensor_logger is not a compiled ELF executable."

    # Preserve the original fixed invocation and verify its actual appended record.
    run_and_check_append(BINARY_PATH, 1600000020, 1, -10)

    # Also exercise the invocation required by the task and unpredictable values.
    run_and_check_append(BINARY_PATH, 1600000000, 1, -50)
    random_cases = [
        (
            secrets.randbelow(2**32),
            secrets.randbelow(2**16),
            -(secrets.randbelow(2**30) + 1),
        )
        for _ in range(3)
    ]
    for case in random_cases:
        run_and_check_append(BINARY_PATH, *case)


def test_sensor_logger_source_fixed():
    assert os.path.isfile(SOURCE_PATH), f"Source file {SOURCE_PATH} is missing."

    with open(SOURCE_PATH, "r") as f:
        content = f.read()

    # Retain the original source assertion.
    original_bug_snippet = "if (val < 0) {\n        free(r); // BUG: Use after free\n    }"
    assert "BUG: Use after free" not in content or "if (val < 0)" not in content[:content.find("BUG: Use after free")], (
        "The source file still appears to contain the original use-after-free bug logic."
    )

    # Compile the submitted source with AddressSanitizer so the source itself must
    # be functional and free of use-after-free and leak errors.
    asan_binary = "/tmp/sensor_logger_asan"
    compile_result = subprocess.run(
        [
            "gcc", "-g", "-fsanitize=address", "-fno-omit-frame-pointer",
            "-o", asan_binary, SOURCE_PATH,
        ],
        capture_output=True,
        timeout=15,
    )
    assert compile_result.returncode == 0, (
        "The submitted sensor_logger.c could not be compiled.\n"
        f"Stderr: {compile_result.stderr.decode('utf-8', errors='ignore')}"
    )

    env = os.environ.copy()
    env["ASAN_OPTIONS"] = "detect_leaks=1:halt_on_error=1:exitcode=99"
    cases = [
        (1600000000, 1, -50),
        (
            secrets.randbelow(2**32),
            secrets.randbelow(2**16),
            -(secrets.randbelow(2**30) + 1),
        ),
    ]
    for case in cases:
        run_and_check_append(asan_binary, *case, env=env)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
