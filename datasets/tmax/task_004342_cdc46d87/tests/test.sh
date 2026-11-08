#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import secrets
import sqlite3
import subprocess
from pathlib import Path

import pytest

RAW = Path("/home/user/raw_telemetry.csv")
CSV = Path("/home/user/processed_telemetry.csv")
SOURCE = Path("/home/user/process.c")
PROGRAM = Path("/home/user/process")
REBUILT = Path("/tmp/process_from_source")


def expected_from_text(text):
    expected = []
    last_val = None
    window = []

    for line in text.splitlines():
        if not line.strip():
            continue
        parts = line.strip().split(",")
        ts = int(parts[0])
        user_id = parts[1]
        val_str = parts[2] if len(parts) > 2 else ""

        if len(user_id) <= 4:
            anon_id = user_id
        else:
            anon_id = "*" * (len(user_id) - 4) + user_id[-4:]

        if val_str == "":
            val = last_val
        else:
            val = float(val_str)
        last_val = val

        window.append(val)
        if len(window) > 3:
            window.pop(0)
        sma = sum(window) / len(window)

        expected.append((ts, anon_id, round(val, 2), round(sma, 2)))

    return expected


def expected_lines(text):
    return [f"{ts},{anon_id},{val:.2f},{sma:.2f}" for ts, anon_id, val, sma in expected_from_text(text)]


def assert_csv_matches(text, artifact):
    assert CSV.is_file(), f"{artifact} did not create {CSV}"
    actual = CSV.read_text().splitlines()
    expected = expected_lines(text)
    assert actual == expected, f"{artifact} produced incorrect or incorrectly formatted CSV data"


def run_processor(executable, text):
    RAW.write_text(text)
    if CSV.exists():
        CSV.unlink()
    result = subprocess.run(
        [str(executable)],
        cwd="/home/user",
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"{executable} exited with {result.returncode}: {result.stderr}"
    )
    assert_csv_matches(text, executable)


def make_hidden_input():
    token = secrets.token_hex(6)
    start = 1700000000 + secrets.randbelow(1000000)
    base = (secrets.randbelow(31) - 15) * 6
    rows = [
        (start, "abc", f"{base}.0"),
        (start + 7, "wxyz", ""),
        (start + 14, f"sensor_{token}_9876", f"{base + 12}.0"),
        (start + 21, "q", ""),
        (start + 28, f"node_{token}_1234", f"{base - 6}.0"),
        (start + 35, "four", f"{base + 24}.0"),
        (start + 42, f"unit_{token}_ABCD", ""),
        (start + 49, f"x{token}WXYZ", f"{base + 6}.0"),
    ]
    return "".join(f"{ts},{uid},{val}\n" for ts, uid, val in rows)


@pytest.fixture(scope="session", autouse=True)
def exercise_c_pipeline():
    assert RAW.is_file(), f"Raw file {RAW} is missing, cannot compute expected data."
    assert SOURCE.is_file(), "C source file /home/user/process.c is missing."
    assert PROGRAM.is_file(), "Compiled executable /home/user/process is missing."
    assert os.access(PROGRAM, os.X_OK), "/home/user/process is not executable."
    with PROGRAM.open("rb") as f:
        assert f.read(4) == b"\x7fELF", "/home/user/process is not a compiled ELF executable."

    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-O2", str(SOURCE), "-o", str(REBUILT), "-lm"],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, f"process.c does not compile: {compile_result.stderr}"

    original_raw = RAW.read_bytes()
    original_text = original_raw.decode()
    try:
        run_processor(REBUILT, make_hidden_input())
        run_processor(PROGRAM, make_hidden_input())
    finally:
        RAW.write_bytes(original_raw)

    # Regenerate the required final CSV with the submitted executable.
    run_processor(PROGRAM, original_text)


def get_expected_data():
    raw_file = "/home/user/raw_telemetry.csv"
    if not os.path.exists(raw_file):
        pytest.fail(f"Raw file {raw_file} is missing, cannot compute expected data.")
    return expected_from_text(Path(raw_file).read_text())


def test_c_files_exist():
    """Test that the C source and compiled executable exist."""
    assert os.path.isfile("/home/user/process.c"), "C source file /home/user/process.c is missing."
    assert os.path.isfile("/home/user/process"), "Compiled executable /home/user/process is missing."


def test_processed_csv_exists():
    """Test that the intermediate processed CSV was created."""
    assert os.path.isfile("/home/user/processed_telemetry.csv"), "Processed CSV /home/user/processed_telemetry.csv is missing."


def test_processed_csv_contents():
    """Test that the C-produced CSV has the required rows and exact formatting."""
    assert_csv_matches(Path("/home/user/raw_telemetry.csv").read_text(), "/home/user/process")


def test_database_exists():
    """Test that the SQLite database was created."""
    assert os.path.isfile("/home/user/telemetry.db"), "Database /home/user/telemetry.db is missing."


def test_database_contents():
    """Test that the database contains the correctly processed data."""
    db_path = "/home/user/telemetry.db"
    assert os.path.isfile(db_path), "Database /home/user/telemetry.db is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cleaned_data'")
    assert cursor.fetchone() is not None, "Table 'cleaned_data' does not exist in the database."

    try:
        cursor.execute("SELECT ts, anon_id, val, sma FROM cleaned_data ORDER BY ts ASC")
        rows = cursor.fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query 'cleaned_data': {e}")
    finally:
        conn.close()

    expected = get_expected_data()
    assert len(rows) == len(expected), f"Expected {len(expected)} rows, found {len(rows)} in cleaned_data."

    for i, (row, exp) in enumerate(zip(rows, expected)):
        assert row[0] == exp[0], f"Row {i+1}: Expected timestamp {exp[0]}, got {row[0]}"
        assert row[1] == exp[1], f"Row {i+1}: Expected anon_id '{exp[1]}', got '{row[1]}'"
        assert round(row[2], 2) == exp[2], f"Row {i+1}: Expected val {exp[2]}, got {round(row[2], 2) if row[2] is not None else None}"
        assert round(row[3], 2) == exp[3], f"Row {i+1}: Expected sma {exp[3]}, got {round(row[3], 2) if row[3] is not None else None}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
