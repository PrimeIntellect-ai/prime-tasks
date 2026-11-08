#!/bin/bash
set +e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import math
import os
import random
import secrets
import subprocess

PROGRAM = "/tmp/process_sensors_verified"
DEVICES = "/home/user/devices.json"
SENSORS = "/home/user/sensor_data.csv"
OUTPUT = "/home/user/top_sensors.json"


def run_program():
    if os.path.exists(OUTPUT):
        os.remove(OUTPUT)
    subprocess.run([PROGRAM], check=True, timeout=20, cwd="/home/user")
    assert os.path.isfile(OUTPUT), "Go program did not create /home/user/top_sensors.json"
    with open(OUTPUT, "r") as f:
        return json.load(f)


def derive_expected(devices, rows):
    active = {d["device_id"]: d["region"] for d in devices if d["active"]}
    grouped = {device_id: [] for device_id in active}
    for timestamp, device_id, temperature, _humidity in rows:
        if device_id in active:
            grouped[device_id].append({
                "timestamp": int(timestamp),
                "temperature": None if temperature == "" else float(temperature),
            })

    processed = []
    for device_id, records in grouped.items():
        records.sort(key=lambda r: r["timestamp"])
        temps = [r["temperature"] for r in records]
        for i, value in enumerate(temps):
            if value is not None:
                continue
            left = i - 1
            while temps[left] is None:
                left -= 1
            right = i + 1
            while temps[right] is None:
                right += 1
            t = records[i]["timestamp"]
            t0 = records[left]["timestamp"]
            t1 = records[right]["timestamp"]
            temps[i] = temps[left] + (temps[right] - temps[left]) * (t - t0) / (t1 - t0)

        for i, record in enumerate(records):
            start = max(0, i - 2)
            smoothed = sum(temps[start:i + 1]) / (i - start + 1)
            processed.append({
                "region": active[device_id],
                "device_id": device_id,
                "timestamp": record["timestamp"],
                "smoothed_temp": smoothed,
            })

    result = []
    for region in sorted({r["region"] for r in processed}):
        candidates = [r for r in processed if r["region"] == region]
        candidates.sort(key=lambda r: (-r["smoothed_temp"], r["timestamp"], r["device_id"]))
        result.extend(candidates[:2])
    return result


def test_go_file_exists():
    path = "/home/user/process_sensors.go"
    assert os.path.isfile(path), f"Expected Go source file {path} does not exist. Did you write your Go program?"


def test_program_on_derived_inputs():
    with open(DEVICES, "rb") as f:
        original_devices = f.read()
    with open(SENSORS, "rb") as f:
        original_sensors = f.read()

    token = secrets.token_hex(4)
    base = 1700000000 + secrets.randbelow(500000)
    region_a = "A_" + token
    region_m = "M_" + token
    region_z = "Z_" + token
    tie_a = "a_" + token
    tie_b = "b_" + token
    interp = "interp_" + token
    other = "other_" + token
    lone = "lone_" + token
    inactive = "inactive_" + token
    unknown = "unknown_" + token

    devices = [
        {"device_id": tie_b, "region": region_m, "active": True},
        {"device_id": interp, "region": region_a, "active": True},
        {"device_id": inactive, "region": region_a, "active": False},
        {"device_id": tie_a, "region": region_m, "active": True},
        {"device_id": other, "region": region_a, "active": True},
        {"device_id": lone, "region": region_z, "active": True},
    ]
    rows = [
        (base + 120, tie_b, "30", "10"),
        (base, tie_b, "30", "11"),
        (base + 60, tie_b, "30", "12"),
        (base + 60, tie_a, "30", "13"),
        (base + 120, tie_a, "30", "14"),
        (base, tie_a, "30", "15"),
        (base + 211, interp, "42", "50"),
        (base + 47, interp, "", "51"),
        (base + 5, interp, "12", "52"),
        (base + 130, interp, "", "53"),
        (base + 190, other, "17", "60"),
        (base + 10, other, "20", "61"),
        (base + 70, other, "19", "62"),
        (base + 130, other, "18", "63"),
        (base + 15, lone, "5", "70"),
        (base + 75, lone, "11", "71"),
        (base + 135, lone, "17", "72"),
        (base + 195, lone, "23", "73"),
        (base + 20, inactive, "999", "1"),
        (base + 80, inactive, "999", "1"),
        (base + 30, unknown, "888", "1"),
        (base + 90, unknown, "888", "1"),
    ]
    random.SystemRandom().shuffle(rows)
    expected = derive_expected(devices, rows)

    try:
        with open(DEVICES, "w") as f:
            json.dump(devices, f)
        with open(SENSORS, "w", newline="") as f:
            writer = csv.writer(f, lineterminator="\n")
            writer.writerows(rows)

        actual = run_program()
        assert isinstance(actual, list), "Output must be a JSON array"
        assert len(actual) == len(expected), f"Expected {len(expected)} sampled records, got {len(actual)}"
        for i, (got, want) in enumerate(zip(actual, expected)):
            assert isinstance(got, dict), f"Record at index {i} must be an object"
            for key in ["region", "device_id", "timestamp", "smoothed_temp"]:
                assert key in got, f"Record at index {i} is missing the '{key}' key."
            assert got["region"] == want["region"], f"Region mismatch at index {i}"
            assert got["device_id"] == want["device_id"], f"Device mismatch at index {i}"
            assert got["timestamp"] == want["timestamp"], f"Timestamp mismatch at index {i}"
            assert math.isclose(float(got["smoothed_temp"]), want["smoothed_temp"], abs_tol=0.011), \
                f"Smoothed temperature mismatch at index {i}: expected {want['smoothed_temp']}, got {got['smoothed_temp']}"
    finally:
        with open(DEVICES, "wb") as f:
            f.write(original_devices)
        with open(SENSORS, "wb") as f:
            f.write(original_sensors)
        run_program()


def test_output_json_exists_and_valid():
    path = "/home/user/top_sensors.json"
    assert os.path.isfile(path), f"Expected output file {path} does not exist. Did your Go program create it?"

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {path} does not contain valid JSON."

    assert isinstance(data, list), f"Output in {path} must be a JSON array at the root."


def test_output_json_content():
    path = "/home/user/top_sensors.json"
    if not os.path.isfile(path):
        return

    with open(path, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            return

    assert len(data) == 6, f"Expected exactly 6 records in {path} (top 2 from 3 active regions), but found {len(data)}."

    expected_records = [
        {"region": "East", "device_id": "dev5", "timestamp": 1620000180, "smoothed_temp": 21.0},
        {"region": "East", "device_id": "dev5", "timestamp": 1620000120, "smoothed_temp": 18.0},
        {"region": "North", "device_id": "dev2", "timestamp": 1620000180, "smoothed_temp": 24.0},
        {"region": "North", "device_id": "dev2", "timestamp": 1620000120, "smoothed_temp": 22.0},
        {"region": "South", "device_id": "dev4", "timestamp": 1620000180, "smoothed_temp": 27.666},
        {"region": "South", "device_id": "dev4", "timestamp": 1620000120, "smoothed_temp": 27.0}
    ]

    for i, exp in enumerate(expected_records):
        actual = data[i]

        for key in ["region", "device_id", "timestamp", "smoothed_temp"]:
            assert key in actual, f"Record at index {i} is missing the '{key}' key."

        assert actual["region"] == exp["region"], \
            f"Record at index {i} region mismatch: expected '{exp['region']}', got '{actual['region']}'."
        assert actual["device_id"] == exp["device_id"], \
            f"Record at index {i} device_id mismatch: expected '{exp['device_id']}', got '{actual['device_id']}'."
        assert actual["timestamp"] == exp["timestamp"], \
            f"Record at index {i} timestamp mismatch: expected {exp['timestamp']}, got {actual['timestamp']}."

        actual_temp = float(actual["smoothed_temp"])
        expected_temp = exp["smoothed_temp"]
        assert math.isclose(actual_temp, expected_temp, rel_tol=1e-2), \
            f"Record at index {i} smoothed_temp mismatch: expected ~{expected_temp}, got {actual_temp}."
TEST_EOF

passed=0
if [ -f /home/user/process_sensors.go ] && \
   GO111MODULE=off go build -o /tmp/process_sensors_verified /home/user/process_sensors.go && \
   rm -f /home/user/top_sensors.json && \
   timeout 20 /tmp/process_sensors_verified && \
   python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    passed=1
fi

echo "$passed" > /logs/verifier/reward.txt
exit 0
