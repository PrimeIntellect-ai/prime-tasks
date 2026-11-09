#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import sqlite3
import subprocess

SOURCE = "/home/user/cleaner.c"
EXECUTABLE = "/home/user/cleaner"
RAW = "/home/user/raw_sensors.csv"
CLEAN = "/home/user/clean_sensors.csv"
DB = "/home/user/sensors.db"

ORIGINAL_LINES = [
    "100,50.50,Tokyo, Japan Zone A,50.50",
    "101,50.50,Tokyo, Japan Zone A,50.50",
    "102,50.50,Tokyo, Japan Zone A,50.50",
    "103,60.50,Paris, France,53.83",
    "104,60.50,Paris, France,57.17",
    "105,70.50,São Paulo, Brazil,63.83",
]

ORIGINAL_DATA = [
    (100, 50.50, "Tokyo, Japan Zone A", 50.50),
    (101, 50.50, "Tokyo, Japan Zone A", 50.50),
    (102, 50.50, "Tokyo, Japan Zone A", 50.50),
    (103, 60.50, "Paris, France", 53.83),
    (104, 60.50, "Paris, France", 57.17),
    (105, 70.50, "São Paulo, Brazil", 63.83),
]


def read_output():
    assert os.path.isfile(CLEAN), f"Cleaned CSV missing at {CLEAN}"
    with open(CLEAN, "r", encoding="utf-8") as f:
        return [line.strip() for line in f if line.strip()]


def assert_lines(expected):
    actual = read_output()
    assert len(actual) == len(expected), f"Expected {len(expected)} rows, found {len(actual)}"
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert got == want, f"Mismatch at row {i + 1}. Expected: '{want}', Got: '{got}'"


def write_raw(data):
    with open(RAW, "wb") as f:
        f.write(data)


def run_cleaner(path):
    if os.path.exists(CLEAN):
        os.remove(CLEAN)
    result = subprocess.run(
        [path], cwd="/home/user", stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=10
    )
    assert result.returncode == 0, (
        f"{path} exited with {result.returncode}: "
        f"{result.stderr.decode('utf-8', errors='replace')}"
    )
    assert os.path.isfile(CLEAN), f"{path} did not create {CLEAN}"


def test_final_state_and_behavior():
    # Preserve the original existence and executability assertions.
    assert os.path.isfile(SOURCE), f"C source file missing at {SOURCE}"
    assert os.path.isfile(EXECUTABLE), f"Executable missing at {EXECUTABLE}"
    assert os.access(EXECUTABLE, os.X_OK), f"Executable at {EXECUTABLE} is not executable"
    with open(EXECUTABLE, "rb") as f:
        assert f.read(4) == b"\x7fELF", "cleaner is not a compiled ELF executable"

    # Preserve the original final CSV assertions.
    assert_lines(ORIGINAL_LINES)

    # Preserve the original database assertions.
    assert os.path.isfile(DB), f"SQLite database missing at {DB}"
    conn = sqlite3.connect(DB)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='cleaned_readings';")
    assert cursor.fetchone() is not None, "Table 'cleaned_readings' does not exist in the database."
    cursor.execute("SELECT timestamp, sensor_value, location_desc, ma_3 FROM cleaned_readings ORDER BY timestamp ASC;")
    rows = cursor.fetchall()
    assert len(rows) == len(ORIGINAL_DATA), f"Expected {len(ORIGINAL_DATA)} rows in database, found {len(rows)}"
    for i, (actual, expected) in enumerate(zip(rows, ORIGINAL_DATA)):
        assert actual[0] == expected[0], f"Row {i+1} timestamp mismatch: expected {expected[0]}, got {actual[0]}"
        assert abs(actual[1] - expected[1]) < 0.01, f"Row {i+1} sensor_value mismatch: expected {expected[1]}, got {actual[1]}"
        assert actual[2] == expected[2], f"Row {i+1} location_desc mismatch: expected '{expected[2]}', got '{actual[2]}'"
        assert abs(actual[3] - expected[3]) < 0.01, f"Row {i+1} ma_3 mismatch: expected {expected[3]}, got {actual[3]}"
    conn.close()

    # Re-run the submitted executable on the original fixture so pre-fabricated
    # output alone cannot satisfy the original assertions.
    original_fixture = (
        'timestamp,sensor_value,location_desc\n'
        '100,50.5,"Tokyo, Japan\nZone A"\n'
        '101,1500.0,"Invalid Zone"\n'
        '103,60.5,"Paris, France"\n'
        '104,-10.0,"Drop me"\n'
        '105,70.5,"São Paulo, Brazil"\n'
    ).encode("utf-8")
    write_raw(original_fixture)
    run_cleaner(EXECUTABLE)
    assert_lines(ORIGINAL_LINES)

    # Exercise parsing, both validation bounds, gap filling, carry-forward,
    # UTF-8 text, embedded LF/CR normalization, and rolling averages on a
    # separate fixture.
    dynamic_fixture = (
        'timestamp,sensor_value,location_desc\n'
        '7,10.0,"Alpha\nNorth"\n'
        '8,-0.01,"Rejected"\n'
        '10,20.0,"München\rWest"\n'
        '11,1000.0,"Comma, Place\rUpper"\n'
        '12,1000.01,"Too high"\n'
        '14,40.0,"Final"\n'
    ).encode("utf-8")
    dynamic_expected = [
        "7,10.00,Alpha North,10.00",
        "8,10.00,Alpha North,10.00",
        "9,10.00,Alpha North,10.00",
        "10,20.00,München West,13.33",
        "11,1000.00,Comma, Place Upper,343.33",
        "12,1000.00,Comma, Place Upper,673.33",
        "13,1000.00,Comma, Place Upper,1000.00",
        "14,40.00,Final,680.00",
    ]
    write_raw(dynamic_fixture)
    run_cleaner(EXECUTABLE)
    assert_lines(dynamic_expected)

    # Ensure cleaner.c itself builds and implements the required behavior,
    # rather than merely accompanying an unrelated executable.
    rebuilt = "/tmp/rebuilt-cleaner"
    build = subprocess.run(
        ["gcc", "-std=c11", SOURCE, "-o", rebuilt],
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert build.returncode == 0, build.stderr.decode("utf-8", errors="replace")

    source_fixture = (
        'timestamp,sensor_value,location_desc\n'
        '20,-1.0,"Discard first"\n'
        '21,0.0,"Zero\nBase"\n'
        '23,3.0,"Next"\n'
        '24,1001.0,"Discard high"\n'
        '25,6.0,"End\rSpot"\n'
    ).encode("utf-8")
    source_expected = [
        "21,0.00,Zero Base,0.00",
        "22,0.00,Zero Base,0.00",
        "23,3.00,Next,1.00",
        "24,3.00,Next,2.00",
        "25,6.00,End Spot,4.00",
    ]
    write_raw(source_fixture)
    run_cleaner(rebuilt)
    assert_lines(source_expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
