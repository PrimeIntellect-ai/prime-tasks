#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import sqlite3
import subprocess
import tempfile
from datetime import datetime, timedelta

CLEAN_CORPUS_DIR = "/opt/tests/clean_corpus"
EVIL_CORPUS_DIR = "/opt/tests/evil_corpus"
PIPELINE_SCRIPT = "/home/user/pipeline.py"


def is_evil(line: str) -> bool:
    if r"\u0000" in line:
        return True
    if re.search(r'\\u[dD][89aAbB][0-9a-fA-F]{2}(?!\\u[dD][c-fC-F][0-9a-fA-F]{2})', line):
        return True
    return False


def extract_code(comment):
    if not isinstance(comment, str):
        return None
    match = re.search(r'\[CODE:\s*(E-[0-9]+)\]', comment)
    return match.group(1) if match else None


def get_expected_data(input_file: str):
    # Filter first, then normalize and keep the last record for each key.
    deduplicated = {}
    with open(input_file, "r", encoding="utf-8") as f:
        for raw_line in f:
            if is_evil(raw_line):
                continue
            try:
                record = json.loads(raw_line)
                sensor_id = record["sensor_id"].upper()
                timestamp = datetime.fromisoformat(record["timestamp"])
            except (json.JSONDecodeError, KeyError, TypeError, ValueError):
                continue
            deduplicated[(sensor_id, timestamp)] = record

    by_sensor = {}
    for (sensor_id, timestamp), record in deduplicated.items():
        by_sensor.setdefault(sensor_id, {})[timestamp] = record

    expected = {}
    for sensor_id, records in by_sensor.items():
        current = min(records)
        end = max(records)
        last_reading = None
        missing_minutes = 0

        while current <= end:
            if current in records:
                record = records[current]
                reading = record.get("reading")
                error_code = extract_code(record.get("comment"))
                if reading is not None:
                    last_reading = float(reading)
                    missing_minutes = 0
                else:
                    missing_minutes += 1
                    reading = last_reading if last_reading is not None and missing_minutes <= 3 else None
            else:
                missing_minutes += 1
                reading = last_reading if last_reading is not None and missing_minutes <= 3 else None
                error_code = None

            expected[(sensor_id, current)] = (
                None if reading is None else float(reading),
                error_code,
            )
            current += timedelta(minutes=1)

    return expected


def assert_output_matches(output_db, expected):
    conn = sqlite3.connect(output_db)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='processed_sensors'")
        assert cursor.fetchone(), "processed_sensors table is missing"

        cursor.execute("PRAGMA table_info(processed_sensors)")
        columns = [row[1] for row in cursor.fetchall()]
        assert columns == ["timestamp", "sensor_id", "reading", "error_code"], columns

        cursor.execute("SELECT timestamp, sensor_id, reading, error_code FROM processed_sensors")
        rows = cursor.fetchall()
        assert len(rows) == len(expected), f"expected {len(expected)} rows, got {len(rows)}"

        actual = {}
        for timestamp, sensor_id, reading, error_code in rows:
            assert isinstance(timestamp, str), "timestamp must be stored as an ISO8601 string"
            parsed_timestamp = datetime.fromisoformat(timestamp)
            key = (sensor_id, parsed_timestamp)
            assert key not in actual, f"duplicate output row for {key}"
            actual[key] = (reading, error_code)

        assert set(actual) == set(expected), "output sensor/timestamp grid does not match expected resampling"
        for key, (expected_reading, expected_code) in expected.items():
            actual_reading, actual_code = actual[key]
            if expected_reading is None:
                assert actual_reading is None, f"expected NULL reading for {key}, got {actual_reading}"
            else:
                assert actual_reading is not None, f"missing reading for {key}"
                assert abs(float(actual_reading) - expected_reading) < 1e-9, (
                    key, actual_reading, expected_reading
                )
            assert actual_code == expected_code, (
                f"wrong error_code for {key}: {actual_code!r} != {expected_code!r}"
            )
    finally:
        conn.close()


def run_and_check(input_file, output_db):
    expected = get_expected_data(input_file)
    if os.path.exists(output_db):
        os.remove(output_db)

    result = subprocess.run(
        ["python3", PIPELINE_SCRIPT, input_file, output_db],
        capture_output=True,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stderr
    assert os.path.exists(output_db), "pipeline did not create the output database"
    assert_output_matches(output_db, expected)


def test_pipeline_exists():
    assert os.path.exists(PIPELINE_SCRIPT), f"Pipeline script not found at {PIPELINE_SCRIPT}"
    assert os.path.isfile(PIPELINE_SCRIPT), f"Pipeline path is not a file: {PIPELINE_SCRIPT}"


def test_clean_corpus():
    clean_files = glob.glob(os.path.join(CLEAN_CORPUS_DIR, "*.jsonl"))
    assert len(clean_files) > 0, "No clean corpus files found"

    failed_files = []
    for input_file in clean_files:
        try:
            run_and_check(input_file, input_file + ".db")
        except Exception:
            failed_files.append(os.path.basename(input_file))
    assert not failed_files, f"{len(failed_files)} of {len(clean_files)} clean modified/failed: {failed_files}"


def test_evil_corpus():
    evil_files = glob.glob(os.path.join(EVIL_CORPUS_DIR, "*.jsonl"))
    assert len(evil_files) > 0, "No evil corpus files found"

    failed_files = []
    for input_file in evil_files:
        try:
            run_and_check(input_file, input_file + ".db")
        except Exception:
            failed_files.append(os.path.basename(input_file))
    assert not failed_files, f"{len(failed_files)} of {len(evil_files)} evil bypassed/failed: {failed_files}"


def test_deduplication_filtering_resampling_and_gap_fill():
    with tempfile.TemporaryDirectory() as tmpdir:
        input_file = os.path.join(tmpdir, "behavior.jsonl")
        output_db = os.path.join(tmpdir, "behavior.db")
        records = [
            {"timestamp": "2024-02-03T00:00:00", "sensor_id": "Sensor_A", "reading": 1.0,
             "comment": "Initial [CODE: E-101]"},
            {"timestamp": "2024-02-03T00:00:00", "sensor_id": "sensor_a", "reading": 2.5,
             "comment": "Last duplicate [CODE: E-202]"},
            {"timestamp": "2024-02-03T00:05:00", "sensor_id": "SENSOR_A", "reading": 5.5,
             "comment": "No error code here"},
            # This later duplicate is fatal and must be filtered before deduplication.
            {"timestamp": "2024-02-03T00:05:00", "sensor_id": "sensor_a", "reading": 999.0,
             "comment": "fatal \u0000 [CODE: E-999]"},
            {"timestamp": "2024-02-03T00:09:00", "sensor_id": "sensor_a", "reading": 9.5,
             "comment": "Recovered [CODE: E-909]"},
            {"timestamp": "2024-02-03T00:01:00", "sensor_id": "sensor_b", "reading": 10.0,
             "comment": "B start [CODE: E-111]"},
            {"timestamp": "2024-02-03T00:03:00", "sensor_id": "SENSOR_B", "reading": 30.0,
             "comment": "No code"},
            # A valid surrogate pair must not be confused with an unpaired high surrogate.
            {"timestamp": "2024-02-03T00:04:00", "sensor_id": "sensor_b", "reading": 40.0,
             "comment": "Valid emoji \U0001F600 [CODE: E-444]"},
            {"timestamp": "2024-02-03T00:00:00", "sensor_id": "evil_only", "reading": 77.0,
             "comment": "unpaired \ud83d"},
        ]

        with open(input_file, "w", encoding="utf-8") as f:
            for record in records:
                f.write(json.dumps(record) + "\n")
            f.write("{not valid json}\n")

        run_and_check(input_file, output_db)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
