#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import io
import os
import sqlite3
import subprocess
import pytest

RAW_PATH = "/home/user/raw_sensors.csv"
CLEAN_PATH = "/home/user/clean_sensors.csv"

ORIGINAL_ROWS = [
    (1, "2023-10-01T08:00:00", "Café_Étoile", 10.0),
    (2, "2023-10-01T09:00:00", "Café_Étoile", None),
    (3, "2023-10-01T10:00:00", "Café_Étoile", 20.0),
    (4, "2023-10-01T11:00:00", "Entrée_Principale", 22.0),
    (5, "2023-10-01T12:00:00", "Café_Étoile", None),
    (6, "2023-10-01T13:00:00", "Café_Étoile", 25.0),
    (7, "2023-10-01T14:00:00", "Café_Étoile", 26.0),
    (8, "2023-10-01T15:00:00", "Café_Étoile", None),
    (9, "2023-10-01T16:00:00", "Café_Étoile", 30.0),
]


def read_raw_rows():
    with open(RAW_PATH, "r", encoding="iso-8859-1", newline="") as f:
        parsed = list(csv.reader(f))
    rows = []
    for row in parsed:
        assert len(row) == 4
        rows.append((int(row[0]), row[1], row[2], None if row[3] == "" else float(row[3])))
    return rows


def expected_clean_rows():
    rows = read_raw_rows()
    assert rows == ORIGINAL_ROWS, "The supplied raw input was modified."
    result = []
    for i, (seq_id, timestamp, location, reading) in enumerate(rows):
        if reading is None:
            previous = i - 1
            while previous >= 0 and rows[previous][3] is None:
                previous -= 1
            following = i + 1
            while following < len(rows) and rows[following][3] is None:
                following += 1
            assert previous >= 0 and following < len(rows)
            prev_seq, prev_reading = rows[previous][0], rows[previous][3]
            next_seq, next_reading = rows[following][0], rows[following][3]
            reading = prev_reading + (next_reading - prev_reading) * ((seq_id - prev_seq) / (next_seq - prev_seq))
        result.append((seq_id, timestamp, location, float(reading)))
    return result


def assert_clean_matches_input():
    expected = expected_clean_rows()
    assert os.path.isfile(CLEAN_PATH), f"The file {CLEAN_PATH} does not exist."
    with open(CLEAN_PATH, "r", encoding="utf-8", newline="") as f:
        actual = list(csv.reader(f))
    assert len(actual) == len(expected), "The cleaned CSV does not contain every input row."
    for index, (row, wanted) in enumerate(zip(actual, expected), 1):
        assert len(row) == 4, f"Cleaned row {index} does not have exactly four columns."
        assert int(row[0]) == wanted[0]
        assert row[1] == wanted[1]
        assert row[2] == wanted[2]
        assert row[3] != ""
        assert abs(float(row[3]) - wanted[3]) < 0.01


@pytest.fixture(scope="session", autouse=True)
def test_cpp_source_and_executable():
    source = "/home/user/etl_processor.cpp"
    executable = "/home/user/etl_processor"
    rebuilt = "/tmp/etl_processor_from_source"

    assert os.path.isfile(source), f"The C++ source {source} does not exist or is not a file."
    assert os.path.isfile(executable), f"The executable {executable} does not exist or is not a file."
    assert os.access(executable, os.X_OK), f"{executable} is not executable."
    with open(executable, "rb") as f:
        assert f.read(4) == b"\x7fELF", f"{executable} is not a compiled ELF executable."

    subprocess.run(
        ["g++", "-std=c++17", source, "-o", rebuilt],
        check=True,
        timeout=30,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    )
    subprocess.run([rebuilt], check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert_clean_matches_input()

    subprocess.run([executable], check=True, timeout=30, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert_clean_matches_input()
    assert read_raw_rows() == ORIGINAL_ROWS, "The ETL program modified its raw input."


def test_clean_sensors_exists_and_utf8():
    file_path = "/home/user/clean_sensors.csv"
    assert os.path.exists(file_path), f"The file {file_path} does not exist."
    assert os.path.isfile(file_path), f"The path {file_path} is not a file."

    try:
        with open(file_path, "r", encoding="utf-8") as f:
            lines = f.readlines()
        assert len(lines) > 0, f"The file {file_path} is empty."

        # Check for missing values (empty strings between commas or at the end)
        for i, line in enumerate(lines):
            parts = line.strip().split(",")
            assert len(parts) == 4, f"Line {i+1} does not have exactly 4 columns: {line}"
            assert parts[3] != "", f"Line {i+1} has a missing reading value: {line}"

    except UnicodeDecodeError:
        pytest.fail(f"The file {file_path} is not properly UTF-8 encoded.")

    assert_clean_matches_input()


def test_database_and_table_schema():
    db_path = "/home/user/sensor_data.db"
    assert os.path.exists(db_path), f"The database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if table 'readings' exists
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='readings';")
    assert cursor.fetchone() is not None, "Table 'readings' does not exist in the database."

    # Check schema
    cursor.execute("PRAGMA table_info(readings);")
    schema_rows = cursor.fetchall()
    columns = {row[1]: row[2].upper() for row in schema_rows}

    assert "seq_id" in columns, "Column 'seq_id' is missing."
    assert "timestamp" in columns, "Column 'timestamp' is missing."
    assert "location_name" in columns, "Column 'location_name' is missing."
    assert "reading" in columns, "Column 'reading' is missing."
    assert [(row[1], row[2].upper()) for row in schema_rows] == [
        ("seq_id", "INTEGER"),
        ("timestamp", "TEXT"),
        ("location_name", "TEXT"),
        ("reading", "REAL"),
    ], "Table 'readings' does not have the required schema."

    conn.close()


def test_database_data_and_interpolation():
    db_path = "/home/user/sensor_data.db"
    assert os.path.exists(db_path), f"The database {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if data was imported
    cursor.execute("SELECT COUNT(*) FROM readings;")
    count = cursor.fetchone()[0]
    assert count > 0, "Table 'readings' is empty."

    # Check specific interpolated values based on the setup data
    # seq_id 2 should be 15.0
    cursor.execute("SELECT reading FROM readings WHERE seq_id = 2;")
    row = cursor.fetchone()
    assert row is not None, "Database row for seq_id 2 is missing."
    if row:
        assert abs(float(row[0]) - 15.0) < 0.01, f"Interpolated value for seq_id 2 is incorrect. Expected 15.0, got {row[0]}"

    # seq_id 5 should be 23.5
    cursor.execute("SELECT reading FROM readings WHERE seq_id = 5;")
    row = cursor.fetchone()
    assert row is not None, "Database row for seq_id 5 is missing."
    if row:
        assert abs(float(row[0]) - 23.5) < 0.01, f"Interpolated value for seq_id 5 is incorrect. Expected 23.5, got {row[0]}"

    # seq_id 8 should be 28.0
    cursor.execute("SELECT reading FROM readings WHERE seq_id = 8;")
    row = cursor.fetchone()
    assert row is not None, "Database row for seq_id 8 is missing."
    if row:
        assert abs(float(row[0]) - 28.0) < 0.01, f"Interpolated value for seq_id 8 is incorrect. Expected 28.0, got {row[0]}"

    expected = expected_clean_rows()
    cursor.execute("SELECT seq_id, timestamp, location_name, reading FROM readings ORDER BY seq_id;")
    actual = cursor.fetchall()
    assert len(actual) == len(expected), "The database does not contain exactly all cleaned rows."
    for got, wanted in zip(actual, expected):
        assert int(got[0]) == wanted[0]
        assert got[1] == wanted[1]
        assert got[2] == wanted[2]
        assert got[3] is not None
        assert abs(float(got[3]) - wanted[3]) < 0.01

    conn.close()


def test_verification_log():
    log_path = "/home/user/verification.log"
    assert os.path.exists(log_path), f"The file {log_path} does not exist."

    with open(log_path, "r", encoding="utf-8") as f:
        content = f.read().strip()

    assert "22.19" in content, f"The verification log does not contain the correct average '22.19'. Found: '{content}'"

    expected = expected_clean_rows()
    conn = sqlite3.connect(":memory:")
    conn.execute("CREATE TABLE expected (location_name TEXT, reading REAL)")
    conn.executemany("INSERT INTO expected VALUES (?, ?)", [(row[2], row[3]) for row in expected])
    expected_text = conn.execute(
        "SELECT printf('%.2f', ROUND(AVG(reading), 2)) FROM expected WHERE location_name = ?",
        ("Café_Étoile",),
    ).fetchone()[0]
    conn.close()
    assert content == expected_text, f"Verification log must contain only {expected_text!r}; found {content!r}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
