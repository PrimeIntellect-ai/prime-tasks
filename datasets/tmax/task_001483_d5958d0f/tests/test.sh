#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import resource
import secrets
import subprocess
from pathlib import Path

import pytest

BINARY = Path("/home/user/csv_processor/target/release/csv_processor")
RAW = Path("/home/user/data/raw_users.csv")
CLEANED = Path("/home/user/data/cleaned_users.csv")
PROJECT = Path("/home/user/csv_processor")


def test_01_release_binary_exists():
    assert os.path.isfile(BINARY), f"Release binary not found at {BINARY}. Did you run 'cargo build --release'?"
    assert os.access(BINARY, os.X_OK), f"File at {BINARY} is not executable."


def test_02_cleaned_users_csv_content():
    assert os.path.isfile(CLEANED), f"Cleaned CSV file not found at {CLEANED}. Did you run the compiled binary?"

    with open(CLEANED, "r") as f:
        lines = [line.strip() for line in f.readlines() if line.strip()]

    expected_lines = [
        "extracted_id,name,email",
        "100001,Alice Smith,alice@example.com",
        "100002,Bob Jones,bob.jones@test.org",
        "100003,Dave Miller,dave@miller.net"
    ]

    assert len(lines) == len(expected_lines), f"Expected {len(expected_lines)} lines in cleaned CSV, but found {len(lines)}."

    for i, (actual, expected) in enumerate(zip(lines, expected_lines)):
        assert actual == expected, f"Line {i+1} in cleaned CSV does not match expected.\nExpected: {expected}\nActual: {actual}"


def test_03_crontab_entry_exists():
    try:
        result = subprocess.run(["crontab", "-l"], capture_output=True, text=True, check=True)
        crontab_content = result.stdout
    except subprocess.CalledProcessError:
        pytest.fail("Failed to read crontab. Ensure crontab is installed for the user.")

    found = False
    for line in crontab_content.splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue

        parts = line.split()
        if len(parts) >= 6:
            schedule = " ".join(parts[:5])
            command = " ".join(parts[5:])
            if schedule == "30 2 * * *" and str(BINARY) in command:
                found = True
                break

    assert found, "Crontab entry for the CSV processor not found or incorrect. Expected schedule '30 2 * * *' and command pointing to the release binary."


def run_binary(timeout=60, memory_limit=None):
    def set_limits():
        if memory_limit is not None:
            resource.setrlimit(resource.RLIMIT_AS, (memory_limit, memory_limit))

    result = subprocess.run(
        [str(BINARY)],
        cwd=str(PROJECT),
        capture_output=True,
        text=True,
        timeout=timeout,
        preexec_fn=set_limits,
    )
    assert result.returncode == 0, (
        f"CSV processor exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def read_cleaned_records():
    assert CLEANED.is_file(), "Running the release binary did not create cleaned_users.csv"
    with CLEANED.open("r", newline="") as f:
        return list(csv.reader(f))


def test_04_build_and_execute_on_derived_inputs():
    source = PROJECT / "src/main.rs"
    assert source.is_file(), "Rust source file src/main.rs is missing"

    build = subprocess.run(
        ["cargo", "build", "--release", "--manifest-path", str(PROJECT / "Cargo.toml")],
        capture_output=True,
        text=True,
        timeout=240,
    )
    assert build.returncode == 0, f"cargo build --release failed:\n{build.stdout}\n{build.stderr}"
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)
    assert BINARY.read_bytes()[:4] == b"\x7fELF", "Cargo release artifact is not an ELF executable"

    original_raw = RAW.read_bytes()
    original_cleaned = CLEANED.read_bytes()

    try:
        rng = secrets.SystemRandom()
        ids = rng.sample(range(100000, 1000000), 12)
        rows = [
            ["No Number", " INVALID@EXAMPLE.COM ", "There is no identifier in this row"],
            ["Too Short", " short@example.com ", "User ID: 12345"],
        ]
        expected = [["extracted_id", "name", "email"]]
        formats = [
            "Account UserID: {} complete",
            "pending id: {}",
            "ticket ID-{} accepted",
            "mixed-case iD / {} end",
        ]

        for i, ident in enumerate(ids):
            name = f"Person {i}, QA" if i == 3 else f"Person {i}"
            email = f"  PERSON{i}@EXAMPLE.COM  "
            rows.append([name, email, formats[i % len(formats)].format(ident)])
            expected.append([str(ident), name, f"person{i}@example.com"])
            if i % 3 == 1:
                rows.append([f"Duplicate {i}", f"duplicate{i}@example.net", f"duplicate ID: {ident}"])
            if i % 4 == 2:
                rows.append([f"Invalid {i}", "invalid@example.net", "number 654321 without an id label"])

        with RAW.open("w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerow(["name", "email", "notes"])
            writer.writerows(rows)

        if CLEANED.exists():
            CLEANED.unlink()
        run_binary()
        assert read_cleaned_records() == expected, (
            "The compiled program failed randomized regex extraction, email normalization, "
            "invalid-row filtering, CSV handling, or first-record deduplication"
        )

        # A file larger than the address-space limit distinguishes row streaming from
        # implementations that load the entire input into memory.
        long_row = b"N,x@y.z," + (b"z" * 1014) + b"\n"
        with RAW.open("wb") as f:
            f.write(b"name,email,notes\n")
            chunk = long_row * 1000
            for _ in range(150):
                f.write(chunk)

        if CLEANED.exists():
            CLEANED.unlink()
        run_binary(timeout=90, memory_limit=96 * 1024 * 1024)
        assert read_cleaned_records() == [["extracted_id", "name", "email"]], (
            "Streaming test should discard every invalid row and emit only the required header"
        )
    finally:
        RAW.write_bytes(original_raw)
        CLEANED.write_bytes(original_cleaned)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
