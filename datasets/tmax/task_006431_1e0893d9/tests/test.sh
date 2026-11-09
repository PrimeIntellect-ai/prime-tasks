#!/bin/bash
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
from collections import Counter

import pytest

RAW_DB_PATH = "/home/user/raw_data.db"
NORMALIZED_DB_PATH = "/home/user/normalized_data.db"
SCHEMA_JSON_PATH = "/home/user/schema_validation.json"

EXPECTED_RAW_COLUMNS = [
    ("sensor_id", "TEXT"),
    ("sensor_model", "TEXT"),
    ("location_name", "TEXT"),
    ("latitude", "REAL"),
    ("longitude", "REAL"),
    ("timestamp", "INTEGER"),
    ("temperature", "REAL"),
    ("humidity", "REAL"),
]
EXPECTED_RAW_ROWS = Counter([
    ("S1", "ModelX", "Station_A", 40.7128, -74.0060, 1622505600, 22.5, 55.2),
    ("S2", "ModelY", "Station_B", 34.0522, -118.2437, 1622505600, 28.1, 40.1),
    ("S1", "ModelX", "Station_A", 40.7128, -74.0060, 1622509200, 23.0, 54.0),
])


def connect_normalized():
    conn = sqlite3.connect(NORMALIZED_DB_PATH)
    conn.execute("PRAGMA foreign_keys=ON")
    return conn


def test_files_exist():
    assert os.path.isfile(NORMALIZED_DB_PATH), f"The normalized database file is missing at {NORMALIZED_DB_PATH}"
    assert os.path.isfile(SCHEMA_JSON_PATH), f"The schema validation JSON file is missing at {SCHEMA_JSON_PATH}"


def test_raw_input_is_original_and_well_formed():
    assert os.path.isfile(RAW_DB_PATH), "raw_data.db is missing"
    with sqlite3.connect(RAW_DB_PATH) as conn:
        info = conn.execute("PRAGMA table_info(raw_readings)").fetchall()
        assert [(r[1], r[2].upper()) for r in info] == EXPECTED_RAW_COLUMNS
        rows = Counter(conn.execute(
            "SELECT sensor_id, sensor_model, location_name, latitude, longitude, "
            "timestamp, temperature, humidity FROM raw_readings"
        ).fetchall())
    assert rows == EXPECTED_RAW_ROWS, "The source raw_readings data was modified"


def test_normalized_data_counts():
    conn = connect_normalized()
    cursor = conn.cursor()
    try:
        cursor.execute("SELECT COUNT(*) FROM locations;")
        loc_count = cursor.fetchone()[0]
        assert loc_count == 2, f"Expected 2 locations, got {loc_count}"

        cursor.execute("SELECT COUNT(*) FROM sensors;")
        sensor_count = cursor.fetchone()[0]
        assert sensor_count == 2, f"Expected 2 sensors, got {sensor_count}"

        cursor.execute("SELECT COUNT(*) FROM readings;")
        reading_count = cursor.fetchone()[0]
        assert reading_count == 3, f"Expected 3 readings, got {reading_count}"
    except sqlite3.OperationalError as e:
        pytest.fail(f"Failed to query normalized tables: {e}")
    finally:
        conn.close()


def test_exact_table_schemas():
    expected = {
        "locations": [("id", "INTEGER", 1), ("name", "TEXT", 0), ("latitude", "REAL", 0), ("longitude", "REAL", 0)],
        "sensors": [("id", "TEXT", 1), ("model", "TEXT", 0)],
        "readings": [("id", "INTEGER", 1), ("sensor_id", "TEXT", 0), ("location_id", "INTEGER", 0),
                     ("timestamp", "INTEGER", 0), ("temperature", "REAL", 0), ("humidity", "REAL", 0)],
    }
    with connect_normalized() as conn:
        for table, wanted in expected.items():
            info = conn.execute(f"PRAGMA table_info({table})").fetchall()
            actual = [(r[1], r[2].upper(), r[5]) for r in info]
            assert actual == wanted, f"Incorrect schema for {table}: {actual}"

        fks = conn.execute("PRAGMA foreign_key_list(readings)").fetchall()
        actual_fks = {(r[2], r[3], r[4]) for r in fks}
        assert actual_fks == {
            ("sensors", "sensor_id", "id"),
            ("locations", "location_id", "id"),
        }
        assert conn.execute("PRAGMA foreign_key_check").fetchall() == []


def test_migrated_values_match_raw_database():
    with sqlite3.connect(RAW_DB_PATH) as raw:
        expected_sensors = Counter(raw.execute(
            "SELECT DISTINCT sensor_id, sensor_model FROM raw_readings"
        ).fetchall())
        expected_locations = Counter(raw.execute(
            "SELECT DISTINCT location_name, latitude, longitude FROM raw_readings"
        ).fetchall())
        expected_readings = Counter(raw.execute(
            "SELECT sensor_id, location_name, latitude, longitude, timestamp, temperature, humidity "
            "FROM raw_readings"
        ).fetchall())

    with connect_normalized() as conn:
        actual_sensors = Counter(conn.execute("SELECT id, model FROM sensors").fetchall())
        actual_locations = Counter(conn.execute("SELECT name, latitude, longitude FROM locations").fetchall())
        actual_readings = Counter(conn.execute(
            "SELECT r.sensor_id, l.name, l.latitude, l.longitude, r.timestamp, r.temperature, r.humidity "
            "FROM readings AS r JOIN locations AS l ON l.id = r.location_id"
        ).fetchall())

    assert actual_sensors == expected_sensors
    assert actual_locations == expected_locations
    assert actual_readings == expected_readings


def test_uniqueness_and_foreign_keys_are_enforced():
    conn = connect_normalized()
    try:
        sensor_id, model = conn.execute("SELECT id, model FROM sensors LIMIT 1").fetchone()
        location_id, name = conn.execute("SELECT id, name FROM locations LIMIT 1").fetchone()

        with pytest.raises(sqlite3.IntegrityError):
            conn.execute("INSERT INTO sensors(id, model) VALUES (?, ?)", (sensor_id, model))
        conn.rollback()

        with pytest.raises(sqlite3.IntegrityError):
            conn.execute("INSERT INTO locations(name, latitude, longitude) VALUES (?, 0, 0)", (name,))
        conn.rollback()

        with pytest.raises(sqlite3.IntegrityError):
            conn.execute(
                "INSERT INTO readings(sensor_id, location_id, timestamp, temperature, humidity) VALUES (?, ?, 0, 0, 0)",
                ("does-not-exist", location_id),
            )
        conn.rollback()

        with pytest.raises(sqlite3.IntegrityError):
            conn.execute(
                "INSERT INTO readings(sensor_id, location_id, timestamp, temperature, humidity) VALUES (?, ?, 0, 0, 0)",
                (sensor_id, 999999999),
            )
        conn.rollback()
    finally:
        conn.close()


def test_indexes_exist():
    conn = connect_normalized()
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_readings_loc_time';")
    idx_loc_time = cursor.fetchone()
    assert idx_loc_time is not None, "Missing index 'idx_readings_loc_time'"

    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_readings_sensor';")
    idx_sensor = cursor.fetchone()
    assert idx_sensor is not None, "Missing index 'idx_readings_sensor'"

    for name in ("idx_readings_loc_time", "idx_readings_sensor"):
        row = cursor.execute(
            "SELECT tbl_name FROM sqlite_master WHERE type='index' AND name=?", (name,)
        ).fetchone()
        assert row == ("readings",), f"{name} is not an index on readings"

    loc_info = cursor.execute("PRAGMA index_xinfo(idx_readings_loc_time)").fetchall()
    loc_keys = [(r[2], r[3]) for r in loc_info if r[5] == 1]
    assert loc_keys == [("location_id", 0), ("timestamp", 1)], \
        f"idx_readings_loc_time must be (location_id ASC, timestamp DESC), got {loc_keys}"

    sensor_info = cursor.execute("PRAGMA index_xinfo(idx_readings_sensor)").fetchall()
    sensor_keys = [(r[2], r[3]) for r in sensor_info if r[5] == 1]
    assert sensor_keys == [("sensor_id", 0)], \
        f"idx_readings_sensor must index only sensor_id, got {sensor_keys}"
    conn.close()


def test_schema_validation_json():
    with open(SCHEMA_JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail("schema_validation.json is not a valid JSON file.")

    assert isinstance(data, list), "schema_validation.json should contain a JSON array."

    create_table_count = sum(1 for item in data if isinstance(item, str) and "CREATE TABLE" in item.upper())
    assert create_table_count >= 3, f"Expected at least 3 'CREATE TABLE' statements in JSON, found {create_table_count}"
    assert all(isinstance(item, str) for item in data), "Every schema report entry must be a SQL string"

    with connect_normalized() as conn:
        actual_sql = [r[0] for r in conn.execute(
            "SELECT sql FROM sqlite_master WHERE type IN ('table','index') AND sql IS NOT NULL"
        ).fetchall()]
    assert Counter(data) == Counter(actual_sql), \
        "schema_validation.json must contain the actual SQL definitions of all tables and indexes"
TEST_EOF

PROJECT=/home/user/climate_processor
BUILD_OK=0
if [ -d "$PROJECT" ] && [ -f "$PROJECT/Cargo.toml" ] && [ -f "$PROJECT/src/main.rs" ]; then
    if runuser -u user -- env HOME=/home/user CARGO_HOME=/home/user/.cargo bash -c \
        "cd '$PROJECT' && cargo clean && cargo build --offline --message-format=json" \
        > /tmp/cargo-build.jsonl 2>/tmp/cargo-build.stderr; then
        python3 - <<'PY'
import json
paths = []
with open('/tmp/cargo-build.jsonl', errors='replace') as f:
    for line in f:
        try:
            msg = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = msg.get('target', {})
        executable = msg.get('executable')
        if executable and 'bin' in target.get('kind', []):
            paths.append(executable)
if len(paths) != 1:
    raise SystemExit(f'Expected exactly one compiled Rust binary, found {len(paths)}')
with open('/tmp/climate-executable', 'w') as f:
    f.write(paths[0])
PY
        if [ $? -eq 0 ] && [ -x "$(cat /tmp/climate-executable 2>/dev/null)" ]; then
            rm -f /home/user/normalized_data.db /home/user/schema_validation.json
            if cd "$PROJECT" && timeout 120 runuser -u user -- "$(cat /tmp/climate-executable)"; then
                BUILD_OK=1
            fi
        fi
    fi
fi

if [ "$BUILD_OK" -eq 1 ] && python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    [ -s /tmp/cargo-build.stderr ] && cat /tmp/cargo-build.stderr
    echo "0" > /logs/verifier/reward.txt
fi
