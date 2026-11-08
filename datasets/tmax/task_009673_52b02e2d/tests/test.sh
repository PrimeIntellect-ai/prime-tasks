#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

DB_PATH = "/home/user/data/telemetry.db"
SQL_PATH = "/home/user/optimize.sql"
PROJECT_PATH = "/home/user/etl_processor"
JSON_PATH = "/home/user/region_summary.json"


def logs_indexes(conn):
    indexes = []
    for row in conn.execute("PRAGMA index_list('logs')"):
        name = row[1]
        quoted = name.replace('"', '""')
        columns = [r[2] for r in conn.execute(f'PRAGMA index_info("{quoted}")')]
        indexes.append((name, columns))
    return indexes


def test_optimize_sql_exists_and_content():
    """Verify that optimize.sql exists and contains a CREATE INDEX statement for logs."""
    assert os.path.exists(SQL_PATH), f"SQL script {SQL_PATH} does not exist."

    with open(SQL_PATH, "r", encoding="utf-8") as f:
        content = f.read().lower()

    assert "create " in content and "index " in content, f"{SQL_PATH} must contain a CREATE INDEX statement."
    assert "logs" in content, f"{SQL_PATH} must reference the 'logs' table."
    assert "device_id" in content, f"{SQL_PATH} must reference the 'device_id' column."


def test_index_applied_to_db():
    """Verify that an index was actually created on logs and leads with device_id."""
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    with sqlite3.connect(DB_PATH) as conn:
        indices = logs_indexes(conn)

    assert len(indices) > 0, "No index was found on the 'logs' table. Did you execute the SQL script?"
    assert any(columns and columns[0].lower() == "device_id" for _, columns in indices), \
        "The applied logs index must index device_id as its leading column."


def test_optimize_script_really_creates_device_index():
    """Apply the submitted script to a copy without logs indexes and inspect its result."""
    with tempfile.TemporaryDirectory() as td:
        copied_db = os.path.join(td, "telemetry.db")
        shutil.copy2(DB_PATH, copied_db)
        with sqlite3.connect(copied_db) as conn:
            for name, _ in logs_indexes(conn):
                quoted = name.replace('"', '""')
                conn.execute(f'DROP INDEX "{quoted}"')
            conn.commit()
            with open(SQL_PATH, "r", encoding="utf-8") as f:
                conn.executescript(f.read())
            indices = logs_indexes(conn)

        assert any(columns and columns[0].lower() == "device_id" for _, columns in indices), \
            "Executing optimize.sql does not create a logs index led by device_id."


def test_rust_project_exists():
    """Verify that a Rust project was initialized at the expected location."""
    cargo_path = os.path.join(PROJECT_PATH, "Cargo.toml")
    assert os.path.exists(cargo_path), f"Rust project not found: {cargo_path} does not exist."


def test_rust_source_contains_required_sql_aggregation():
    sources = glob.glob(os.path.join(PROJECT_PATH, "src", "**", "*.rs"), recursive=True)
    assert sources, "The Rust project has no Rust source files under src/."
    source = "\n".join(open(path, "r", encoding="utf-8").read() for path in sources).lower()

    assert "json_each" in source, "Rust SQL must use SQLite JSON1 json_each to expand sensor_readings."
    assert "sensor_readings" in source, "Rust SQL must extract the sensor_readings array."
    assert "json_extract" in source or "->>" in source or "->" in source, \
        "Rust SQL must extract fields from JSON readings using SQLite JSON1."
    assert "temperature" in source, "Rust SQL must filter for the exact temperature reading type."
    assert " join " in source or "\njoin " in source, "Rust SQL must join logs with devices."
    assert "group by" in source, "Rust SQL must group the result by region."
    assert "max(" in source, "Rust SQL must calculate maximum temperatures."


def test_region_summary_json():
    """Verify the initially generated output contains the known correct maxima."""
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} does not exist."

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} does not contain valid JSON.")

    expected_data = {
        "North": 20.0,
        "South": 30.1,
        "East": 22.0,
        "West": 25.5,
    }

    assert isinstance(data, dict), f"Expected the JSON output to be an object/dict, got {type(data).__name__}."
    for region, expected_temp in expected_data.items():
        assert region in data, f"Region '{region}' is missing from the output JSON."
        actual_temp = data[region]
        assert isinstance(actual_temp, (int, float)), f"Value for '{region}' must be a number, got {type(actual_temp).__name__}."
        assert abs(actual_temp - expected_temp) < 1e-5, \
            f"Expected max temperature for {region} to be {expected_temp}, but got {actual_temp}."


def derive_expected_from_database():
    expected = {}
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute("""
            SELECT devices.region, logs.payload
            FROM logs JOIN devices ON logs.device_id = devices.id
        """)
        for region, payload in rows:
            document = json.loads(payload)
            for reading in document.get("sensor_readings", []):
                if reading.get("type") == "temperature":
                    value = reading.get("value")
                    if isinstance(value, (int, float)) and not isinstance(value, bool):
                        value = float(value)
                        if region not in expected or value > expected[region]:
                            expected[region] = value
    return expected


def test_build_and_run_rust_against_unseen_data():
    """Change the input, execute the Rust artifact, and independently check its fresh output."""
    token = uuid.uuid4().hex
    device = "verify-device-" + token
    region = "VerifyRegion-" + token
    north_device = "verify-north-" + token

    with sqlite3.connect(DB_PATH) as conn:
        conn.execute("INSERT INTO devices(id, firmware_version, region) VALUES (?, ?, ?)",
                     (device, "verify", region))
        conn.execute("INSERT INTO devices(id, firmware_version, region) VALUES (?, ?, ?)",
                     (north_device, "verify", "North"))
        payloads = [
            (device, {"sensor_readings": [
                {"type": "temperature", "value": -17.25},
                {"type": "humidity", "value": 99999.0}
            ]}),
            (device, {"sensor_readings": [
                {"type": "temperature", "value": 73.625},
                {"type": "Temperature", "value": 88888.0}
            ]}),
            (north_device, {"sensor_readings": [
                {"type": "temperature", "value": 111.375}
            ]}),
        ]
        conn.executemany("INSERT INTO logs(device_id, payload) VALUES (?, ?)",
                         [(dev, json.dumps(payload)) for dev, payload in payloads])
        conn.commit()

    expected = derive_expected_from_database()
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)

    result = subprocess.run(
        ["cargo", "run", "--quiet"],
        cwd=PROJECT_PATH,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=180,
    )
    assert result.returncode == 0, \
        f"cargo run failed with exit code {result.returncode}:\n{result.stdout}\n{result.stderr}"
    assert os.path.exists(JSON_PATH), "The executed Rust program did not create region_summary.json."

    with open(JSON_PATH, "r", encoding="utf-8") as f:
        try:
            actual = json.load(f)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Rust program produced invalid JSON: {exc}")

    assert isinstance(actual, dict), "Rust output must be a single JSON object."
    assert set(actual) == set(expected), \
        f"Output regions differ from database regions: expected {set(expected)}, got {set(actual)}"
    for region_name, expected_value in expected.items():
        value = actual[region_name]
        assert isinstance(value, (int, float)) and not isinstance(value, bool), \
            f"Value for {region_name} must be numeric."
        assert abs(float(value) - expected_value) < 1e-5, \
            f"Wrong maximum for {region_name}: expected {expected_value}, got {value}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
