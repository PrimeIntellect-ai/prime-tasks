#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import subprocess

PROJECT_DIR = "/home/user/sensor_pipeline"
OUTPUT_FILE = "/home/user/output/aggregated_temps.csv"
SENSORS_FILE = "/home/user/data/sensors.csv"
READINGS_FILE = "/home/user/data/readings.csv"


def read_output():
    assert os.path.isfile(OUTPUT_FILE), f"The output file '{OUTPUT_FILE}' is missing."
    with open(OUTPUT_FILE, "r", newline="") as f:
        return list(csv.reader(f))


def test_rust_project_exists():
    assert os.path.isdir(PROJECT_DIR), "The Rust project directory '/home/user/sensor_pipeline' is missing."
    assert os.path.isfile(os.path.join(PROJECT_DIR, "Cargo.toml")), "The Cargo.toml file is missing."
    assert os.path.isfile(os.path.join(PROJECT_DIR, "src/main.rs")), "The src/main.rs file is missing."


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), "The output file '/home/user/output/aggregated_temps.csv' is missing."


def test_output_file_contents():
    rows = read_output()
    assert len(rows) > 0, "The output CSV is empty."
    assert rows[0] == ["location", "max_temp_f", "avg_temp_f"], f"Headers do not match expected. Got: {rows[0]}"

    data = {}
    for row in rows[1:]:
        assert len(row) == 3, f"Row does not have 3 columns: {row}"
        location = row[0]
        max_temp = float(row[1])
        avg_temp = float(row[2])
        data[location] = (max_temp, avg_temp)

    expected_data = {
        "Warehouse_A": (77.0, 72.5),
        "Warehouse_B": (86.0, 86.0),
        "Warehouse_C": (59.0, 54.5),
    }

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} data rows, got {len(data)}."
    for loc, (exp_max, exp_avg) in expected_data.items():
        assert loc in data, f"Location '{loc}' is missing from the output."
        act_max, act_avg = data[loc]
        assert abs(act_max - exp_max) < 1e-6, f"For {loc}, expected max_temp_f {exp_max}, got {act_max}"
        assert abs(act_avg - exp_avg) < 1e-6, f"For {loc}, expected avg_temp_f {exp_avg}, got {act_avg}"

    assert len(rows[1:]) == len(expected_data), "The output contains duplicate or extra data rows."
    assert [row[0] for row in rows[1:]] == sorted(expected_data), "Output rows are not sorted alphabetically by location."


def test_rust_program_on_generated_inputs():
    token = secrets.token_hex(6)
    base = secrets.randbelow(800000) + 100000
    sensors = [
        (base + 7, f"Zulu_{token}", "Temperature"),
        (base + 1, f"Alpha_{token}", "Temperature"),
        (base + 9, f"Middle_{token}", "Humidity"),
        (base + 3, f"Beta_{token}", "Temperature"),
        (base + 4, f"Almost_{token}", "Temperature "),
    ]
    readings = [
        ("2041-01-01T00:00:00Z", base + 7, -5.0),
        ("2041-01-01T00:01:00Z", base + 1, 11.25),
        ("2041-01-01T00:02:00Z", base + 3, 40.0),
        ("2041-01-01T00:03:00Z", base + 1, 18.75),
        ("2041-01-01T00:04:00Z", base + 9, 99.0),
        ("2041-01-01T00:05:00Z", base + 7, 7.5),
        ("2041-01-01T00:06:00Z", base + 3, 20.0),
        ("2041-01-01T00:07:00Z", base + 4, 500.0),
        ("2041-01-01T00:08:00Z", base + 999, 123.0),
        ("2041-01-01T00:09:00Z", base + 1, -2.5),
    ]

    with open(SENSORS_FILE, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["sensor_id", "location", "sensor_type"])
        writer.writerows(sensors)
    with open(READINGS_FILE, "w", newline="") as f:
        writer = csv.writer(f, lineterminator="\n")
        writer.writerow(["timestamp", "sensor_id", "value"])
        writer.writerows(readings)

    sensor_by_id = {sensor_id: (location, sensor_type) for sensor_id, location, sensor_type in sensors}
    grouped = {}
    for _timestamp, sensor_id, value in readings:
        metadata = sensor_by_id.get(sensor_id)
        if metadata is None or metadata[1] != "Temperature":
            continue
        grouped.setdefault(metadata[0], []).append(value * 1.8 + 32.0)
    expected = {
        location: (max(values), sum(values) / len(values))
        for location, values in grouped.items()
    }

    metadata_result = subprocess.run(
        ["cargo", "metadata", "--no-deps", "--format-version", "1", "--manifest-path", os.path.join(PROJECT_DIR, "Cargo.toml")],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=60,
    )
    assert metadata_result.returncode == 0, f"Cargo could not load the Rust project:\n{metadata_result.stderr}"
    metadata = json.loads(metadata_result.stdout)
    required_source = os.path.realpath(os.path.join(PROJECT_DIR, "src/main.rs"))
    targets = [
        target for package in metadata["packages"] for target in package["targets"]
        if "bin" in target.get("kind", []) and os.path.realpath(target["src_path"]) == required_source
    ]
    assert targets, "Cargo.toml does not define src/main.rs as an executable binary target."

    if os.path.exists(OUTPUT_FILE):
        os.remove(OUTPUT_FILE)
    run_result = subprocess.run(
        ["cargo", "run", "--quiet", "--manifest-path", os.path.join(PROJECT_DIR, "Cargo.toml"), "--bin", targets[0]["name"]],
        cwd=PROJECT_DIR,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=240,
    )
    assert run_result.returncode == 0, f"The Rust program failed:\nstdout:\n{run_result.stdout}\nstderr:\n{run_result.stderr}"

    rows = read_output()
    assert rows, "The Rust program generated an empty CSV."
    assert rows[0] == ["location", "max_temp_f", "avg_temp_f"], f"Headers do not match expected. Got: {rows[0]}"
    assert len(rows) == len(expected) + 1, f"Expected {len(expected)} data rows, got {len(rows) - 1}."

    actual_locations = []
    for row in rows[1:]:
        assert len(row) == 3, f"Row does not have 3 columns: {row}"
        location = row[0]
        assert location in expected, f"Unexpected location in output: {location}"
        actual_locations.append(location)
        actual_max = float(row[1])
        actual_avg = float(row[2])
        expected_max, expected_avg = expected[location]
        assert abs(actual_max - expected_max) < 1e-6, f"For {location}, expected max_temp_f {expected_max}, got {actual_max}"
        assert abs(actual_avg - expected_avg) < 1e-6, f"For {location}, expected avg_temp_f {expected_avg}, got {actual_avg}"

    assert len(set(actual_locations)) == len(actual_locations), "The output contains duplicate locations."
    assert actual_locations == sorted(expected), "Output rows are not sorted alphabetically by location."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
