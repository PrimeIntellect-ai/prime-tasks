#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import random
import sqlite3
import string
import subprocess

import pytest

SOURCE = "/home/user/process_telemetry.c"
EXECUTABLE = "/home/user/process_telemetry"
CSV_PATH = "/home/user/sensor_data.csv"
TSV_PATH = "/home/user/cleaned_telemetry.tsv"
DB_PATH = "/home/user/telemetry.db"


def test_c_file_exists():
    file_path = SOURCE
    assert os.path.exists(file_path), f"File {file_path} is missing."
    assert os.path.isfile(file_path), f"{file_path} is not a file."


def _remove_database_files():
    for suffix in ("", "-wal", "-shm", "-journal"):
        path = DB_PATH + suffix
        try:
            os.unlink(path)
        except FileNotFoundError:
            pass


def test_compile_and_execute_c_program_on_derived_input():
    compile_result = subprocess.run(
        ["gcc", "-std=c11", "-Wall", "-Wextra", "-O2", SOURCE, "-o", EXECUTABLE],
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        text=True,
        timeout=20,
    )
    assert compile_result.returncode == 0, "C source did not compile:\n" + compile_result.stdout
    assert os.path.isfile(EXECUTABLE), f"Executable {EXECUTABLE} is missing."
    assert os.access(EXECUTABLE, os.X_OK), f"{EXECUTABLE} is not executable."

    with open(CSV_PATH, "rb") as f:
        original_csv = f.read()
    original_db = None
    if os.path.isfile(DB_PATH):
        with open(DB_PATH, "rb") as f:
            original_db = f.read()

    rng = random.SystemRandom()
    start = rng.randrange(2000, 900000)
    gap1 = rng.randrange(3, 7)
    gap2 = rng.randrange(2, 6)
    base = rng.randrange(-5, 35) + 0.25
    alphabet = string.ascii_letters
    token1 = ''.join(rng.choice(alphabet) for _ in range(15))
    token2 = ''.join(rng.choice(alphabet) for _ in range(17))
    token3 = ''.join(rng.choice(alphabet) for _ in range(13))
    token4 = ''.join(rng.choice(alphabet) for _ in range(19))

    records = [
        (start, base, token1),
        (start + gap1, base + 1.25 * gap1, token2 + "\n" + token3 + "\nTail"),
        (start + gap1 + 1, base + 1.25 * gap1 + 0.50, "Plain" + token4),
        (start + gap1 + 1 + gap2, base + 1.25 * gap1 + 0.50 - 0.75 * gap2,
         "Cool\n" + token1),
    ]

    csv_data = (
        f'{records[0][0]},{records[0][1]:.2f},"{records[0][2]}"\n'
        f'{records[1][0]},{records[1][1]:.2f},"{records[1][2]}"\n'
        f'{records[2][0]},{records[2][1]:.2f},{records[2][2]}\n'
        f'{records[3][0]},{records[3][1]:.2f},"{records[3][2]}"\n'
    )

    expected = []
    for index, (timestamp, temperature, status) in enumerate(records):
        expected.append(f"{timestamp}\t{temperature:.2f}\t{status.replace(chr(10), ' ')}")
        if index + 1 < len(records):
            next_timestamp, next_temperature, _ = records[index + 1]
            span = next_timestamp - timestamp
            for offset in range(1, span):
                interpolated = temperature + (next_temperature - temperature) * offset / span
                expected.append(f"{timestamp + offset}\t{interpolated:.2f}\tFILLED")

    dynamic_lines = None
    original_run = None
    try:
        _remove_database_files()
        with open(CSV_PATH, "w", newline="") as f:
            f.write(csv_data)
        try:
            os.unlink(TSV_PATH)
        except FileNotFoundError:
            pass

        dynamic_run = subprocess.run(
            [EXECUTABLE], cwd="/home/user", stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT, text=True, timeout=10
        )
        assert dynamic_run.returncode == 0, "Executable failed on generated CSV:\n" + dynamic_run.stdout
        assert os.path.isfile(TSV_PATH), "Executable did not create cleaned_telemetry.tsv."
        with open(TSV_PATH, "r", newline="") as f:
            dynamic_lines = f.read().splitlines()
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        _remove_database_files()
        try:
            try:
                os.unlink(TSV_PATH)
            except FileNotFoundError:
                pass
            original_run = subprocess.run(
                [EXECUTABLE], cwd="/home/user", stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT, text=True, timeout=10
            )
        finally:
            with open(CSV_PATH, "wb") as f:
                f.write(original_csv)
            _remove_database_files()
            if original_db is not None:
                with open(DB_PATH, "wb") as f:
                    f.write(original_db)

    assert dynamic_lines == expected, "Executable output was incorrect for the generated CSV input."
    assert original_run.returncode == 0, "Executable failed on the supplied CSV:\n" + original_run.stdout


def test_tsv_file_contents():
    file_path = TSV_PATH
    assert os.path.exists(file_path), f"File {file_path} is missing."

    expected_lines = [
        "100\t20.00\tSystem Boot",
        "101\t21.00\tFILLED",
        "102\t22.00\tFILLED",
        "103\t23.00\tWarning: High Temp Detected",
        "104\t24.50\tOK",
        "105\t24.00\tFILLED",
        "106\t23.50\tFILLED",
        "107\t23.00\tFILLED",
        "108\t22.50\tCooling Down"
    ]

    with open(file_path, "r") as f:
        lines = [line.strip("\n") for line in f.readlines() if line.strip("\n")]

    assert lines == expected_lines, f"Contents of {file_path} do not match the expected output."


def test_sqlite_db_contents():
    db_path = DB_PATH
    assert os.path.exists(db_path), f"Database {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='sensor_log';")
    assert cursor.fetchone() is not None, "Table 'sensor_log' does not exist in the database."

    cursor.execute("SELECT count(*) FROM sensor_log;")
    count = cursor.fetchone()[0]
    assert count == 9, f"Expected 9 rows in sensor_log, found {count}."

    cursor.execute("SELECT temperature, status FROM sensor_log WHERE timestamp = 106;")
    row = cursor.fetchone()
    assert row is not None, "Missing row for timestamp 106."
    assert abs(row[0] - 23.5) < 0.01, f"Expected temperature 23.5 for timestamp 106, got {row[0]}."
    assert row[1] == "FILLED", f"Expected status 'FILLED' for timestamp 106, got '{row[1]}'."

    cursor.execute("SELECT status FROM sensor_log WHERE timestamp = 103;")
    row = cursor.fetchone()
    assert row is not None, "Missing row for timestamp 103."
    assert row[0] == "Warning: High Temp Detected", f"Expected cleaned status 'Warning: High Temp Detected' for timestamp 103, got '{row[0]}'."

    conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
