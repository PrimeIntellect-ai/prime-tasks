#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import subprocess
import uuid
from pathlib import Path

import pytest

SUMMARY_PATH = Path("/home/user/summary.json")
CSV_PATH = Path("/home/user/sensor_data.csv")


def test_summary_json_exists():
    """Check that the summary.json file was created in the correct location."""
    assert os.path.isfile(SUMMARY_PATH), f"File not found: {SUMMARY_PATH}. The script did not generate the output file."


def test_summary_json_contents():
    """Check that the original supplied dataset produced the correct statistics."""
    assert os.path.isfile(SUMMARY_PATH), f"File not found: {SUMMARY_PATH}"

    with open(SUMMARY_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {SUMMARY_PATH} does not contain valid JSON.")

    expected_data = {
        "sensor_A": 0.4,
        "sensor_B": 0.4071,
        "sensor_C": 0.0,
    }

    assert isinstance(data, dict), f"Expected JSON root to be a dictionary, got {type(data).__name__}."
    assert set(data.keys()) == set(expected_data.keys()), f"Expected keys {set(expected_data.keys())}, but got {set(data.keys())}."

    for key, expected_value in expected_data.items():
        actual_value = data[key]
        assert isinstance(actual_value, (int, float)), f"Value for {key} should be a number, got {type(actual_value).__name__}."
        assert round(actual_value, 4) == expected_value, f"Value for {key} is incorrect. Expected {expected_value}, got {actual_value}."


def expected_summary(rows):
    groups = {}
    for timestamp, sensor_id, value in rows:
        groups.setdefault(sensor_id, []).append((timestamp, float(value)))

    result = {}
    for sensor_id, values in groups.items():
        values.sort(key=lambda item: item[0])
        diffs = []
        history = []
        for _, value in values:
            history.append(value)
            rolling_mean = sum(history[-3:]) / len(history[-3:])
            diffs.append(value - rolling_mean)

        low = min(diffs)
        high = max(diffs)
        if high == low:
            normalized = [0.0] * len(diffs)
        else:
            normalized = [(value - low) / (high - low) for value in diffs]
        result[sensor_id] = round(sum(normalized) / len(normalized), 4)
    return result


def make_fixture():
    rng = random.SystemRandom()
    rows = []
    sensor_ids = [f"sensor_{uuid.uuid4().hex[:10]}" for _ in range(4)]

    for index, sensor_id in enumerate(sensor_ids):
        count = rng.randint(6, 10)
        if index == len(sensor_ids) - 1:
            values = [float(rng.randint(-50, 50))] * count
        else:
            base = rng.randint(-200, 200)
            values = [float(base + rng.randint(-40, 40)) for _ in range(count)]
            if len(set(values)) == 1:
                values[-1] += 1.0

        timestamps = rng.sample(range(100, 1000), count)
        for timestamp, value in zip(timestamps, values):
            rows.append((timestamp, sensor_id, value))

    rng.shuffle(rows)
    return rows, expected_summary(rows)


def write_fixture(rows):
    with open(CSV_PATH, "w", newline="") as f:
        writer = csv.writer(f)
        writer.writerow(["timestamp", "sensor_id", "value"])
        writer.writerows(rows)


def output_matches(expected):
    if not SUMMARY_PATH.is_file():
        return False
    try:
        with open(SUMMARY_PATH, "r") as f:
            data = json.load(f)
    except (OSError, json.JSONDecodeError):
        return False

    if not isinstance(data, dict) or set(data) != set(expected):
        return False
    for key, expected_value in expected.items():
        actual = data[key]
        if not isinstance(actual, (int, float)) or round(actual, 4) != expected_value:
            return False
    return True


def test_python_etl_script_processes_unseen_csv_inputs():
    scripts = sorted(
        path for path in Path("/home/user").rglob("*.py")
        if path.is_file() and not path.is_symlink()
    )
    assert scripts, "No Python ETL script was found under /home/user."

    fixtures = [make_fixture() for _ in range(3)]
    original_csv = CSV_PATH.read_bytes()
    original_summary = SUMMARY_PATH.read_bytes()
    working_script = None

    try:
        for script in scripts:
            passed_all = True
            for rows, expected in fixtures:
                write_fixture(rows)
                SUMMARY_PATH.unlink(missing_ok=True)
                try:
                    completed = subprocess.run(
                        ["python3", str(script)],
                        cwd="/home/user",
                        stdout=subprocess.PIPE,
                        stderr=subprocess.PIPE,
                        text=True,
                        timeout=20,
                    )
                except (subprocess.SubprocessError, OSError):
                    passed_all = False
                    break

                if completed.returncode != 0 or not output_matches(expected):
                    passed_all = False
                    break

            if passed_all:
                working_script = script
                break
    finally:
        CSV_PATH.write_bytes(original_csv)
        SUMMARY_PATH.write_bytes(original_summary)

    assert working_script is not None, "No submitted Python script correctly processed multiple unseen sensor CSV fixtures."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
