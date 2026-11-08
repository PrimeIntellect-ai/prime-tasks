#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import secrets
import shutil
import stat
import subprocess
import sys
from datetime import datetime, timezone

import pytest

ETL_PATH = "/home/user/etl.py"
RAW_DIR = "/home/user/raw_data"
OUTPUT_DIR = "/home/user/output"
OUTPUT_PATH = "/home/user/output/summary.jsonl"


def write_inputs(metadata, rows):
    os.makedirs(RAW_DIR, exist_ok=True)
    os.makedirs(OUTPUT_DIR, exist_ok=True)
    with open(os.path.join(RAW_DIR, "metadata.json"), "w") as f:
        json.dump(metadata, f)
    with open(os.path.join(RAW_DIR, "telemetry.csv"), "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "device_id", "sensor_type", "value"])
        writer.writerows(rows)


def clear_output():
    if os.path.lexists(OUTPUT_PATH):
        if os.path.isdir(OUTPUT_PATH) and not os.path.islink(OUTPUT_PATH):
            shutil.rmtree(OUTPUT_PATH)
        else:
            os.unlink(OUTPUT_PATH)


def run_etl():
    clear_output()
    result = subprocess.run(
        [sys.executable, ETL_PATH],
        cwd="/home/user",
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.STDOUT,
        timeout=60,
    )
    assert result.returncode == 0, f"etl.py failed with exit code {result.returncode}:\n{result.stdout}"


def read_jsonl():
    actual = []
    with open(OUTPUT_PATH, "r") as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {OUTPUT_PATH} is not valid JSON: {line}")
    return actual


def install_original_fixture():
    metadata = [
        {"device_id": "D1", "site": "North", "alert_threshold": 50.0},
        {"device_id": "D2", "site": "North", "alert_threshold": 55.0},
        {"device_id": "D3", "site": "South", "alert_threshold": 40.0},
    ]
    rows = [
        ["2023-10-01 11:15:00", "D3", "temp", 39.0],
        ["2023-10-01 10:25:00", "D1", "temp", 55.0],
        ["2023-10-01 10:10:00", "D2", "humidity", 60.0],
        ["2023-10-01 10:00:00", "D9", "temp", 100.0],
        ["10/01/2023 10:15", "D1", "temp", ""],
        ["2023-10-01 10:30:00", "D2", "humidity", ""],
        ["2023-10-01 10:05:00", "D1", "temp", 45.0],
        ["2023-10-01 11:05:00", "D3", "temp", 41.0],
        ["10/01/2023 10:20", "D2", "humidity", ""],
        ["2023-10-01 10:25:00", "D1", "temp", 55.0],
    ]
    write_inputs(metadata, rows)


def test_etl_script_exists_and_executes_on_supplied_inputs():
    assert os.path.isfile(ETL_PATH), f"Required script {ETL_PATH} is missing"
    assert stat.S_ISREG(os.stat(ETL_PATH).st_mode), f"{ETL_PATH} is not a regular file"
    assert os.path.getsize(ETL_PATH) > 0, f"{ETL_PATH} is empty"
    install_original_fixture()
    run_etl()


def test_summary_jsonl_exists():
    """Test that the output file was created."""
    path = "/home/user/output/summary.jsonl"
    assert os.path.isfile(path), f"Output file {path} is missing. Did the script run and output to the correct location?"


def test_summary_jsonl_content():
    """Test that the aggregated results match the expected output."""
    path = "/home/user/output/summary.jsonl"

    expected_data = [
        {
            "window_start": "2023-10-01T10:00:00Z",
            "site": "North",
            "sensor_type": "humidity",
            "avg_value": 20.0,
            "alert_count": 1
        },
        {
            "window_start": "2023-10-01T10:00:00Z",
            "site": "North",
            "sensor_type": "temp",
            "avg_value": 50.0,
            "alert_count": 1
        },
        {
            "window_start": "2023-10-01T11:00:00Z",
            "site": "South",
            "sensor_type": "temp",
            "avg_value": 40.0,
            "alert_count": 1
        }
    ]

    actual_data = []
    with open(path, 'r') as f:
        for line_num, line in enumerate(f, 1):
            line = line.strip()
            if not line:
                continue
            try:
                actual_data.append(json.loads(line))
            except json.JSONDecodeError:
                pytest.fail(f"Line {line_num} in {path} is not valid JSON: {line}")

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} records, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert actual.get("window_start") == expected["window_start"], f"Record {i} window_start mismatch: expected {expected['window_start']}, got {actual.get('window_start')}"
        assert actual.get("site") == expected["site"], f"Record {i} site mismatch: expected {expected['site']}, got {actual.get('site')}"
        assert actual.get("sensor_type") == expected["sensor_type"], f"Record {i} sensor_type mismatch: expected {expected['sensor_type']}, got {actual.get('sensor_type')}"

        actual_avg = actual.get("avg_value")
        assert actual_avg is not None, f"Record {i} missing avg_value"
        assert abs(actual_avg - expected["avg_value"]) < 0.01, f"Record {i} avg_value mismatch: expected {expected['avg_value']}, got {actual_avg}"

        assert actual.get("alert_count") == expected["alert_count"], f"Record {i} alert_count mismatch: expected {expected['alert_count']}, got {actual.get('alert_count')}"


def test_etl_generalizes_to_fresh_inputs():
    token = secrets.token_hex(4)
    month = random.randint(2, 9)
    threshold = random.randint(31, 73)
    day = 17
    year = 2024

    d1 = f"A_{token}"
    d2 = f"B_{token}"
    d3 = f"C_{token}"
    ghost = f"G_{token}"
    site_a = f"Site_{token}_A"
    site_b = f"Site_{token}_B"

    metadata = [
        {"device_id": d1, "site": site_b, "alert_threshold": float(threshold)},
        {"device_id": d2, "site": site_a, "alert_threshold": float(threshold + 7)},
        {"device_id": d3, "site": site_a, "alert_threshold": float(threshold - 4)},
    ]

    iso_date = f"{year:04d}-{month:02d}-{day:02d}"
    slash_date = f"{month:02d}/{day:02d}/{year:04d}"
    rows = [
        [f"{iso_date} 09:15:00", d3, "pressure", threshold - 4],
        [f"{iso_date} 08:25:00", d1, "temp", threshold + 10],
        [f"{iso_date} 08:10:00", d2, "humidity", ""],
        [f"{iso_date} 08:00:00", ghost, "temp", 9999.0],
        [f"{slash_date} 08:15", d1, "temp", ""],
        [f"{iso_date} 08:30:00", d2, "humidity", ""],
        [f"{iso_date} 08:05:00", d1, "temp", threshold - 10],
        [f"{iso_date} 09:05:00", d3, "pressure", threshold + 4],
        [f"{slash_date} 08:20", d2, "humidity", threshold + 13],
        [f"{iso_date} 08:25:00", d1, "temp", threshold + 10],
    ]
    random.SystemRandom().shuffle(rows)
    write_inputs(metadata, rows)
    run_etl()

    expected = [
        {
            "window_start": f"{iso_date}T08:00:00Z",
            "site": site_a,
            "sensor_type": "humidity",
            "avg_value": round((threshold + 13) / 3.0, 2),
            "alert_count": 1,
        },
        {
            "window_start": f"{iso_date}T08:00:00Z",
            "site": site_b,
            "sensor_type": "temp",
            "avg_value": round(float(threshold), 2),
            "alert_count": 1,
        },
        {
            "window_start": f"{iso_date}T09:00:00Z",
            "site": site_a,
            "sensor_type": "pressure",
            "avg_value": round(float(threshold), 2),
            "alert_count": 1,
        },
    ]

    assert os.path.isfile(OUTPUT_PATH), "etl.py did not recreate summary.jsonl for fresh inputs"
    actual = read_jsonl()
    assert len(actual) == len(expected), f"Expected {len(expected)} fresh-input records, found {len(actual)}"
    for i, (got, want) in enumerate(zip(actual, expected)):
        assert set(got) == {"window_start", "site", "sensor_type", "avg_value", "alert_count"}, f"Record {i} has incorrect keys: {set(got)}"
        assert got["window_start"] == want["window_start"], f"Record {i} window_start mismatch"
        assert got["site"] == want["site"], f"Record {i} site mismatch"
        assert got["sensor_type"] == want["sensor_type"], f"Record {i} sensor_type mismatch"
        assert abs(got["avg_value"] - want["avg_value"]) < 0.01, f"Record {i} avg_value mismatch: expected {want['avg_value']}, got {got['avg_value']}"
        assert got["alert_count"] == want["alert_count"], f"Record {i} alert_count mismatch"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
