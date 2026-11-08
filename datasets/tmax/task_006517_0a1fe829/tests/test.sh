#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import subprocess
import tempfile
from decimal import Decimal, ROUND_HALF_UP, getcontext
from fractions import Fraction
from pathlib import Path

import pytest

HOME = Path("/home/user")
INPUT = HOME / "data/input.csv"
OUTPUT = HOME / "output.csv"
SCRIPT = HOME / "run_pipeline.sh"
SOURCE = HOME / "process.cpp"

ORIGINAL_INPUT = b"""2023-10-01 10:00:00,Hello World! This is a test.
2023-10-01 10:05:00,Caf\xc3\xa9 is open!!! Welcome.
2023-10-01 10:10:00,123 numbers 456
2023-10-01 10:15:00,No-alphanumerics... here??
2023-10-01 10:20:00,short string
"""

ORIGINAL_EXPECTED = [
    "2023-10-01 10:00:00,3.50",
    "2023-10-01 10:05:00,3.75",
    "2023-10-01 10:10:00,3.94",
    "2023-10-01 10:15:00,5.94",
    "2023-10-01 10:20:00,6.44",
]


def test_process_cpp_exists():
    """Test that the C++ program file exists."""
    assert os.path.isfile(SOURCE), "File /home/user/process.cpp does not exist."


def test_run_pipeline_sh_exists_and_executable():
    """Test that the shell script exists and is executable."""
    assert os.path.isfile(SCRIPT), "File /home/user/run_pipeline.sh does not exist."
    assert os.access(SCRIPT, os.X_OK), "File /home/user/run_pipeline.sh is not executable."


def test_cron_txt_content():
    """Test that the cron.txt file contains the correct cron expression."""
    cron_path = HOME / "cron.txt"
    assert os.path.isfile(cron_path), "File /home/user/cron.txt does not exist."

    content = cron_path.read_text().strip()
    parts = content.split()
    assert len(parts) >= 6, "cron.txt does not contain a complete cron expression."

    minute_field = parts[0]
    assert minute_field in ("*/15", "0,15,30,45"), (
        f"Invalid minute field in cron expression: {minute_field}. "
        "Expected '*/15' or '0,15,30,45'."
    )
    assert parts[1:5] == ["*", "*", "*", "*"], (
        "Cron expression should run every hour, day, month, and day of week (i.e. * * * *)."
    )

    command = " ".join(parts[5:])
    assert command.endswith("/home/user/run_pipeline.sh") or "/home/user/run_pipeline.sh" in command, (
        f"Cron command does not seem to execute /home/user/run_pipeline.sh. Found: {command}"
    )


def run_program(command):
    if OUTPUT.exists():
        OUTPUT.unlink()
    result = subprocess.run(
        command,
        cwd=HOME,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
        check=False,
    )
    assert result.returncode == 0, (
        f"Command failed with status {result.returncode}: {command}\n"
        f"stdout:\n{result.stdout.decode(errors='replace')}\n"
        f"stderr:\n{result.stderr.decode(errors='replace')}"
    )
    assert OUTPUT.is_file(), "The executed program did not create /home/user/output.csv."


def read_output():
    return OUTPUT.read_text().splitlines()


def expected_for(rows):
    getcontext().prec = 40
    stats = []
    result = []
    for timestamp, message in rows:
        cleaned = bytearray()
        for value in message:
            if 65 <= value <= 90:
                cleaned.append(value + 32)
            elif 97 <= value <= 122 or 48 <= value <= 57 or value == 32:
                cleaned.append(value)
            # All other bytes are removed, not converted into delimiters.

        tokens = bytes(cleaned).split(b" ")
        lengths = [len(token) for token in tokens if token]
        stat = Fraction(sum(lengths), len(lengths)) if lengths else Fraction(0, 1)
        stats.append(stat)

        window = stats[max(0, len(stats) - 3):]
        rolling = sum(window, Fraction(0, 1)) / len(window)
        value = (Decimal(rolling.numerator) / Decimal(rolling.denominator)).quantize(
            Decimal("0.01"), rounding=ROUND_HALF_UP
        )
        result.append(f"{timestamp},{value:.2f}")
    return result


def write_rows(rows):
    data = b"".join(ts.encode("ascii") + b"," + message + b"\n" for ts, message in rows)
    INPUT.write_bytes(data)


def test_output_csv_content():
    """Run the requested pipeline and check the corrected output for the supplied input."""
    assert INPUT.read_bytes() == ORIGINAL_INPUT, "The supplied input.csv was unexpectedly modified."
    run_program([str(SCRIPT)])
    actual_lines = read_output()
    assert len(actual_lines) == len(ORIGINAL_EXPECTED), (
        f"Expected {len(ORIGINAL_EXPECTED)} lines in output.csv, but found {len(actual_lines)}."
    )
    for i, (actual, expected) in enumerate(zip(actual_lines, ORIGINAL_EXPECTED)):
        assert actual == expected, (
            f"Mismatch at line {i + 1} in output.csv. Expected: '{expected}', Actual: '{actual}'"
        )


def test_pipeline_and_cpp_on_unseen_input():
    """Exercise both the pipeline and a freshly compiled process.cpp on verifier-derived data."""
    random_values = [1 + (b % 17) for b in os.urandom(8)]
    nonce = os.urandom(5).hex().encode("ascii")
    a, b, c, d, e, f, g, h = random_values
    rows = [
        ("2026-04-11 09:00:01", b"A" * a + b"-._" + b"B" * b + b" " + b"C" * c),
        ("2026-04-11 09:00:02", b"12\xc3\xa934 " + b"Z" * d),
        ("2026-04-11 09:00:03", b"!!!\xff???"),
        ("2026-04-11 09:00:04", b"x" * e + b"   " + b"7" * f + b" " + nonce),
        ("2026-04-11 09:00:05", b"left-right " + b"Q" * g),
        ("2026-04-11 09:00:06", b"M" * h + b"\tN"),
    ]
    expected = expected_for(rows)

    try:
        write_rows(rows)

        # The automation script itself must generate correct output for unseen data.
        run_program([str(SCRIPT)])
        assert read_output() == expected

        # Independently compile and execute the submitted C++ artifact so static or
        # hardcoded output.csv files cannot satisfy the verifier.
        with tempfile.TemporaryDirectory() as tmpdir:
            executable = Path(tmpdir) / "submitted_processor"
            compile_result = subprocess.run(
                ["g++", "-std=c++17", str(SOURCE), "-o", str(executable)],
                cwd=HOME,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
                check=False,
            )
            assert compile_result.returncode == 0, (
                "process.cpp did not compile:\n"
                + compile_result.stderr.decode(errors="replace")
            )
            run_program([str(executable)])
            assert read_output() == expected
    finally:
        INPUT.write_bytes(ORIGINAL_INPUT)
        run_program([str(SCRIPT)])

    assert read_output() == ORIGINAL_EXPECTED
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
