#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import secrets
import subprocess
import pytest

PIPELINE = "/home/user/pipeline.go"
CSV_PATH = "/home/user/sensor_data.csv"
OUTPUT_PATH = "/home/user/clean_summary.json"


def run_pipeline():
    if os.path.exists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    subprocess.run(
        ["go", "run", PIPELINE],
        cwd="/home/user",
        check=True,
        timeout=60,
    )
    assert os.path.isfile(OUTPUT_PATH), "The Go program did not create clean_summary.json."


def test_json_file_exists():
    """Test that the clean_summary.json file was created."""
    file_path = "/home/user/clean_summary.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing. Did you run the Go program?"


def test_json_file_valid_and_correct():
    """Test that clean_summary.json is valid JSON and contains the correct aggregations."""
    file_path = "/home/user/clean_summary.json"
    assert os.path.isfile(file_path), f"File {file_path} is missing."

    with open(file_path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {file_path} does not contain valid JSON.")

    assert "alpha" in data, "Missing 'alpha' key in the JSON output."
    assert data["alpha"].get("count") == 2, f"Expected alpha count to be 2, got {data['alpha'].get('count')}"
    assert float(data["alpha"].get("average")) == 100.0, f"Expected alpha average to be 100.0, got {data['alpha'].get('average')}"

    assert "beta" in data, "Missing 'beta' key in the JSON output."
    assert data["beta"].get("count") == 1, f"Expected beta count to be 1, got {data['beta'].get('count')}"
    assert float(data["beta"].get("average")) == 200.0, f"Expected beta average to be 200.0, got {data['beta'].get('average')}"

    assert "gamma" in data, "Missing 'gamma' key in the JSON output."
    assert data["gamma"].get("count") == 1, f"Expected gamma count to be 1, got {data['gamma'].get('count')}"
    assert float(data["gamma"].get("average")) == 500.0, f"Expected gamma average to be 500.0, got {data['gamma'].get('average')}"

    expected_keys = {"alpha", "beta", "gamma"}
    actual_keys = set(data.keys())
    assert actual_keys == expected_keys, f"Expected keys {expected_keys}, but got {actual_keys}"


def test_pipeline_on_runtime_generated_input():
    original_csv = open(CSV_PATH, "rb").read()
    original_output = open(OUTPUT_PATH, "rb").read()

    token = secrets.token_hex(8)
    sensor_a = "runtime_a_" + token
    sensor_b = "runtime_b_" + token
    sensor_invalid = "runtime_invalid_" + token
    value_a = secrets.randbelow(300) + 1
    value_b = secrets.randbelow(300) + 301

    rows = [
        ["2026-01-01T00:00:00Z", sensor_a, str(value_a), ""],
        ["2026-01-01T00:00:01Z", sensor_a, str(value_b), ""],
        ["2026-01-01T00:00:02Z", sensor_a, "-0.5", ""],
        ["2026-01-01T00:00:03Z", sensor_a, "777", "E-RUNTIME"],
        ["2026-01-01T00:00:04Z", sensor_b, "0", ""],
        ["2026-01-01T00:00:05Z", sensor_b, "1000", ""],
        ["2026-01-01T00:00:06Z", sensor_b, "1000.5", ""],
        ["2026-01-01T00:00:07Z", sensor_invalid, "20", "BAD"],
        ["2026-01-01T00:00:08Z", sensor_invalid, "-10", ""],
    ]

    expected = {}
    for _, sensor_id, reading_text, error_code in rows:
        reading = float(reading_text)
        if error_code != "" or reading < 0.0 or reading > 1000.0:
            continue
        bucket = expected.setdefault(sensor_id, [])
        bucket.append(reading)

    try:
        with open(CSV_PATH, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "sensor_id", "reading", "error_code"])
            writer.writerows(rows)

        run_pipeline()
        with open(OUTPUT_PATH, "r") as f:
            data = json.load(f)

        assert isinstance(data, dict)
        assert set(data.keys()) == set(expected.keys())
        for sensor_id, readings in expected.items():
            assert isinstance(data[sensor_id], dict)
            count = data[sensor_id].get("count")
            average = data[sensor_id].get("average")
            assert isinstance(count, int) and not isinstance(count, bool)
            assert isinstance(average, (int, float)) and not isinstance(average, bool)
            assert count == len(readings)
            assert math.isclose(
                float(average), sum(readings) / len(readings), rel_tol=1e-12, abs_tol=1e-12
            )
    finally:
        with open(CSV_PATH, "wb") as f:
            f.write(original_csv)
        with open(OUTPUT_PATH, "wb") as f:
            f.write(original_output)
TEST_EOF

passed=0
if [[ -f /home/user/pipeline.go ]] \
   && rm -f /home/user/clean_summary.json \
   && timeout 60s go run /home/user/pipeline.go \
   && python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=1
fi

echo "$passed" > /logs/verifier/reward.txt
