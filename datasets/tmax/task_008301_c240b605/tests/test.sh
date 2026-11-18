#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import secrets
import subprocess
from pathlib import Path

import pytest

CPP_FILE = Path("/home/user/process_logs.cpp")
LOG_FILE = Path("/home/user/server_logs.txt")
CSV_FILE = Path("/home/user/hourly_stats.csv")
BINARY = Path("/home/user/process_logs")

CANONICAL_LOG = """TIMESTAMP=2023-10-14T08:15:01Z | MSG: Request processed. [latency: 120ms] | USER: ALICE
TIMESTAMP=2023-10-14T08:45:00Z | MSG: Request processed. [latency: 130ms] | USER: BOB
TIMESTAMP=2023-10-14T09:05:00Z | MSG: Request processed. [latency: 200ms] | USER: CHARLIE
TIMESTAMP=2023-10-14T09:15:00Z | MSG: Request processed. [latency: 210ms] | USER: ALICE
TIMESTAMP=2023-10-14T10:00:00Z | MSG: Request processed. [latency: 50ms] | USER: BOB
TIMESTAMP=2023-10-14T10:30:00Z | MSG: Request processed. [latency: 60ms] | USER: ALICE
TIMESTAMP=2023-10-14T23:59:59Z | MSG: Request processed. [latency: 999ms] | USER: SYSTEM
"""

EXPECTED_CANONICAL = [
    "Hour,Avg_Latency",
    "08,125.00",
    "09,205.00",
    "10,55.00",
    "23,999.00",
]

_prepared = False


def run_program(log_text):
    LOG_FILE.write_text(log_text)
    if CSV_FILE.exists():
        CSV_FILE.unlink()
    subprocess.run([str(BINARY)], check=True, timeout=10, cwd="/home/user")
    assert CSV_FILE.is_file(), f"Missing generated CSV file at {CSV_FILE}"
    with CSV_FILE.open("r") as f:
        return [line.strip() for line in f if line.strip()]


def prepare_canonical_run():
    global _prepared
    if _prepared:
        return
    assert CPP_FILE.is_file(), f"Missing C++ source file at {CPP_FILE}"
    if BINARY.exists() or BINARY.is_symlink():
        BINARY.unlink()
    subprocess.run(
        ["g++", "-O2", str(CPP_FILE), "-o", str(BINARY)],
        check=True,
        timeout=30,
    )
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)
    run_program(CANONICAL_LOG)
    _prepared = True


def test_process_logs_cpp_exists():
    """Test that the C++ source file was created."""
    assert CPP_FILE.is_file(), f"Missing C++ source file at {CPP_FILE}"


def test_program_compiles_and_executes():
    """Compile the submitted source and execute the resulting artifact."""
    prepare_canonical_run()


def test_hourly_stats_csv_exists():
    """Test that the hourly_stats.csv file was generated."""
    prepare_canonical_run()
    assert CSV_FILE.is_file(), f"Missing generated CSV file at {CSV_FILE}"


def test_hourly_stats_csv_content():
    """Test that the generated CSV file has the correct original content."""
    prepare_canonical_run()
    with CSV_FILE.open("r") as f:
        actual_lines = [line.strip() for line in f if line.strip()]
    assert actual_lines == EXPECTED_CANONICAL, (
        f"Content of {CSV_FILE} is incorrect.\n"
        f"Expected:\n{chr(10).join(EXPECTED_CANONICAL)}\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def make_random_case(rng, hour_count):
    hours = sorted(rng.sample(range(24), hour_count))
    lines = []
    expected = ["Hour,Avg_Latency"]

    for hour in hours:
        base = rng.randint(20, 900)
        quarter = rng.randint(0, 3)
        values = [base, base, base, base]
        values[0] += quarter
        rng.shuffle(values)

        expected.append(f"{hour:02d},{(sum(values) / len(values)):.2f}")
        for latency in values:
            minute = rng.randrange(60)
            second = rng.randrange(60)
            day = rng.randint(1, 28)
            lines.append(
                f"TIMESTAMP=2024-11-{day:02d}T{hour:02d}:{minute:02d}:{second:02d}Z "
                f"| MSG: Request processed. [latency: {latency}ms] | USER: TESTER"
            )

    rng.shuffle(lines)
    return "\n".join(lines) + "\n", expected


def test_program_parses_and_aggregates_runtime_inputs():
    """Exercise the compiled program on answers derived at verification time."""
    prepare_canonical_run()
    rng = random.Random(secrets.randbits(128))
    try:
        for hour_count in (1, 7, 13):
            log_text, expected = make_random_case(rng, hour_count)
            actual = run_program(log_text)
            assert actual == expected, (
                "Incorrect aggregation for a runtime-generated log.\n"
                f"Expected:\n{chr(10).join(expected)}\n"
                f"Got:\n{chr(10).join(actual)}"
            )
    finally:
        run_program(CANONICAL_LOG)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
