#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import subprocess
from collections import defaultdict

import pytest

PROJECT = "/home/user/etl_pipeline"
RAW = "/home/user/raw_sensor_data.csv"
OUTPUT = "/home/user/processed_data.json"


def run_program(check=True):
    return subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT, "Cargo.toml")],
        cwd=PROJECT,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=120,
        check=check,
    )


def load_output():
    assert os.path.isfile(OUTPUT), f"The file {OUTPUT} does not exist."
    with open(OUTPUT, "r") as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {OUTPUT} does not contain valid JSON.")


def assert_records(data, expected_data):
    assert isinstance(data, list), "The JSON output must be a list of objects."
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} records, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual.get("sensor_id") == expected["sensor_id"], f"Record {i}: Expected sensor_id {expected['sensor_id']}, got {actual.get('sensor_id')}"
        assert actual.get("timestamp") == expected["timestamp"], f"Record {i}: Expected timestamp {expected['timestamp']}, got {actual.get('timestamp')}"
        actual_temp = actual.get("temperature")
        assert isinstance(actual_temp, (int, float)) and not isinstance(actual_temp, bool), f"Record {i}: Temperature must be a number."
        assert math.isfinite(actual_temp), f"Record {i}: Temperature must be finite."
        assert abs(actual_temp - expected["temperature"]) < 1e-6, f"Record {i}: Expected temperature {expected['temperature']}, got {actual_temp}"


def derive_expected(csv_text):
    grouped = defaultdict(list)
    reader = csv.DictReader(csv_text.splitlines())
    for row in reader:
        try:
            timestamp_text = row.get("timestamp")
            sensor_id = row.get("sensor_id")
            temperature_text = row.get("temperature")
            if not timestamp_text or not sensor_id or not temperature_text:
                continue
            timestamp = int(timestamp_text)
            temperature = float(temperature_text)
            if not math.isfinite(temperature) or temperature < -50.0 or temperature > 150.0:
                continue
        except (TypeError, ValueError):
            continue
        bucket = timestamp - (timestamp % 3600)
        grouped[(sensor_id, bucket)].append(temperature)

    averages = {key: sum(values) / len(values) for key, values in grouped.items()}
    sensors = sorted({sensor for sensor, _ in averages})
    expected = []
    for sensor in sensors:
        buckets = sorted(bucket for current_sensor, bucket in averages if current_sensor == sensor)
        if not buckets:
            continue
        last_temperature = None
        for bucket in range(buckets[0], buckets[-1] + 1, 3600):
            if (sensor, bucket) in averages:
                last_temperature = averages[(sensor, bucket)]
            expected.append({"sensor_id": sensor, "timestamp": bucket, "temperature": last_temperature})
    return expected


@pytest.fixture(scope="session", autouse=True)
def compile_and_run_rust_project():
    assert os.path.isfile(os.path.join(PROJECT, "Cargo.toml")), "Missing /home/user/etl_pipeline/Cargo.toml."
    src_dir = os.path.join(PROJECT, "src")
    assert os.path.isdir(src_dir), "Missing Rust src directory."
    assert any(name.endswith(".rs") for _, _, files in os.walk(src_dir) for name in files), "No Rust source file was created."
    result = run_program(check=False)
    assert result.returncode == 0, f"The Rust program failed to compile or run:\n{result.stderr}"


def test_processed_data_exists():
    assert os.path.isfile(OUTPUT), f"The file {OUTPUT} does not exist. Did you run the Rust program?"


def test_processed_data_content():
    expected_data = [
        {"sensor_id": "S1", "timestamp": 1599998400, "temperature": 23.0},
        {"sensor_id": "S1", "timestamp": 1600002000, "temperature": 23.0},
        {"sensor_id": "S1", "timestamp": 1600005600, "temperature": 24.0},
        {"sensor_id": "S1", "timestamp": 1600009200, "temperature": 24.0},
        {"sensor_id": "S1", "timestamp": 1600012800, "temperature": 25.0},
        {"sensor_id": "S2", "timestamp": 1600002000, "temperature": 10.0},
        {"sensor_id": "S2", "timestamp": 1600005600, "temperature": 10.0},
        {"sensor_id": "S2", "timestamp": 1600009200, "temperature": 12.0},
    ]
    assert_records(load_output(), expected_data)


def test_program_processes_additional_input():
    alternate_csv = """timestamp,sensor_id,temperature
3601,Z,10
3700,Z,14
10801,Z,20
3605,A,5
7201,A,7
10801,A,9
bad,A,11
10801,A,invalid
10801,A,200
10801,,8
"""
    expected = derive_expected(alternate_csv)
    with open(RAW, "rb") as f:
        original_raw = f.read()

    try:
        with open(RAW, "w") as f:
            f.write(alternate_csv)
        result = run_program(check=False)
        assert result.returncode == 0, f"The Rust program failed on additional input:\n{result.stderr}"
        assert_records(load_output(), expected)
    finally:
        with open(RAW, "wb") as f:
            f.write(original_raw)
        run_program(check=False)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
