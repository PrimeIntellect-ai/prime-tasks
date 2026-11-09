#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import sqlite3
from collections import Counter, defaultdict
from datetime import datetime, timedelta

import pytest

RAW = "/home/user/sensor_data_raw.csv"
UTF8 = "/home/user/sensor_data_utf8.csv"
SAMPLED = "/home/user/sensor_data_sampled.csv"
DB = "/home/user/sensors.db"
AVERAGES = "/home/user/average_temps.csv"
FIELDS = ["timestamp", "sensor_id", "temperature", "status"]


def canonical_raw_rows():
    sensors = [
        ("SENS_A", 100, 15.5),
        ("SENS_B", 50, 22.0),
        ("SENS_C", 200, 8.4),
    ]
    start = datetime(2023, 1, 1, 0, 0, 0)
    rows = []
    for sensor_id, count, temperature in sensors:
        for i in range(count):
            rows.append({
                "timestamp": (start + timedelta(minutes=i)).isoformat(),
                "sensor_id": sensor_id,
                "temperature": str(temperature),
                "status": f"Température mesurée à {temperature}°C",
            })
    return rows


def read_dict_csv(path, encoding):
    with open(path, "r", encoding=encoding, newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == FIELDS, f"Unexpected columns in {path}: {reader.fieldnames}"
        rows = list(reader)
    assert all(None not in row for row in rows), f"Malformed CSV rows in {path}"
    return rows


def expected_sample(rows):
    grouped = defaultdict(list)
    for row in rows:
        grouped[row["sensor_id"]].append(row)

    result = {}
    for sensor_id, sensor_rows in grouped.items():
        ordered = sorted(sensor_rows, key=lambda row: datetime.fromisoformat(row["timestamp"]))
        result[sensor_id] = ordered[:int(0.2 * len(ordered))]
    return result


def test_utf8_conversion():
    """The UTF-8 file must be a faithful conversion of the supplied ISO-8859-1 CSV."""
    assert os.path.isfile(RAW), f"File {RAW} does not exist."
    raw_rows = read_dict_csv(RAW, "iso-8859-1")
    assert raw_rows == canonical_raw_rows(), "The supplied raw input was modified."

    assert os.path.isfile(UTF8), f"File {UTF8} does not exist."
    try:
        utf8_rows = read_dict_csv(UTF8, "utf-8")
        with open(UTF8, "r", encoding="utf-8") as f:
            content = f.read()
            assert "Température mesurée" in content or "°C" in content, \
                "Expected special characters not found in UTF-8 file."
    except UnicodeDecodeError:
        pytest.fail(f"The file {UTF8} is not valid UTF-8.")

    assert utf8_rows == raw_rows, "The UTF-8 CSV is not a faithful conversion of the raw CSV."


def test_sampled_data():
    """The sample must contain exactly the chronological first 20% for each sensor."""
    assert os.path.isfile(SAMPLED), f"File {SAMPLED} does not exist."
    source_rows = read_dict_csv(UTF8, "utf-8")
    sampled_rows = read_dict_csv(SAMPLED, "utf-8")

    actual = defaultdict(list)
    counts = {"SENS_A": 0, "SENS_B": 0, "SENS_C": 0}
    for row in sampled_rows:
        sensor = row.get("sensor_id")
        if sensor not in counts:
            pytest.fail(f"Unexpected sensor_id found: {sensor}")
        counts[sensor] += 1
        actual[sensor].append(row)

    assert counts["SENS_A"] == 20, f"Expected 20 rows for SENS_A, got {counts['SENS_A']}"
    assert counts["SENS_B"] == 10, f"Expected 10 rows for SENS_B, got {counts['SENS_B']}"
    assert counts["SENS_C"] == 40, f"Expected 40 rows for SENS_C, got {counts['SENS_C']}"

    expected = expected_sample(source_rows)
    assert set(actual) == set(expected), "Sample has missing or unexpected sensors."
    for sensor_id in sorted(expected):
        assert actual[sensor_id] == expected[sensor_id], \
            f"Rows for {sensor_id} are not exactly its chronological first 20%."


def test_database_import():
    """The readings table must contain exactly the sampled CSV data."""
    assert os.path.isfile(DB), f"Database {DB} does not exist."
    sampled_rows = read_dict_csv(SAMPLED, "utf-8")

    conn = sqlite3.connect(DB)
    try:
        obj = conn.execute(
            "SELECT type FROM sqlite_master WHERE name = 'readings'"
        ).fetchone()
        assert obj is not None and obj[0] == "table", "readings is not a SQLite table."

        columns = [row[1] for row in conn.execute("PRAGMA table_info(readings)")]
        assert columns == FIELDS, f"Unexpected readings columns: {columns}"

        count = conn.execute("SELECT COUNT(*) FROM readings").fetchone()[0]
        assert count == 70, f"Expected 70 rows in the 'readings' table, got {count}"

        db_rows = conn.execute(
            'SELECT timestamp, sensor_id, temperature, status FROM readings'
        ).fetchall()
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query 'readings' table: {e}")
    finally:
        conn.close()

    expected_tuples = Counter(tuple(row[field] for field in FIELDS) for row in sampled_rows)
    actual_tuples = Counter(
        tuple(None if value is None else str(value) for value in row) for row in db_rows
    )
    assert actual_tuples == expected_tuples, \
        "The readings table is not an exact import of sensor_data_sampled.csv."


def test_average_temps_export():
    """The export must match averages calculated from the verified readings table."""
    assert os.path.isfile(AVERAGES), f"File {AVERAGES} does not exist."

    conn = sqlite3.connect(DB)
    try:
        expected_from_db = conn.execute(
            "SELECT sensor_id, AVG(CAST(temperature AS REAL)) "
            "FROM readings GROUP BY sensor_id ORDER BY sensor_id ASC"
        ).fetchall()
    finally:
        conn.close()

    with open(AVERAGES, "r", encoding="utf-8", newline="") as f:
        actual_rows = [[col.strip() for col in row] for row in csv.reader(f)]

    expected_rows = [
        ["sensor_id", "avg_temperature"],
        ["SENS_A", "15.5"],
        ["SENS_B", "22.0"],
        ["SENS_C", "8.4"],
    ]

    assert len(actual_rows) == 4, \
        "Expected exactly 4 rows (including header) in average_temps.csv"
    assert all(len(row) == 2 for row in actual_rows), \
        "average_temps.csv must have exactly two columns."
    assert actual_rows[0] == expected_rows[0], "Header mismatch in average_temps.csv"

    assert len(expected_from_db) == len(actual_rows) - 1
    for i in range(1, 4):
        assert actual_rows[i][0] == expected_rows[i][0], \
            f"Expected sensor_id {expected_rows[i][0]}, got {actual_rows[i][0]}"
        assert actual_rows[i][0] == expected_from_db[i - 1][0], \
            "Exported sensor order or identity does not match the database query."
        try:
            actual_temp = float(actual_rows[i][1])
            fixed_expected_temp = float(expected_rows[i][1])
        except ValueError:
            pytest.fail(f"Could not parse average temperature as float: {actual_rows[i][1]}")
        assert abs(actual_temp - fixed_expected_temp) < 0.01, \
            f"Expected avg_temperature {fixed_expected_temp} for {expected_rows[i][0]}, got {actual_temp}"
        assert abs(actual_temp - float(expected_from_db[i - 1][1])) < 0.01, \
            f"Exported average for {actual_rows[i][0]} does not match the readings table."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
