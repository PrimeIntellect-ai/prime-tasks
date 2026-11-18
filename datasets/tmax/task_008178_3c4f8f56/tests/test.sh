#!/bin/bash
set -e
mkdir -p /logs/verifier

PIPELINE=/home/user/etl_pipeline.py
if [ ! -f "$PIPELINE" ]; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

# Execute the submitted pipeline against the original inputs before checking its output.
if ! timeout 30s python3 "$PIPELINE"; then
    echo "0" > /logs/verifier/reward.txt
    exit 0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import random
import secrets
import subprocess
import pytest

OUTPUT_CSV = "/home/user/output.csv"
PIPELINE = "/home/user/etl_pipeline.py"
TEMPERATURE_CSV = "/home/user/temperature.csv"
HUMIDITY_CSV = "/home/user/humidity.csv"
EXPECTED_HEADER = ["timestamp", "device_id", "temp_c", "humidity_pct", "rolling_temp_c", "high_risk"]


def test_pipeline_file_exists():
    assert os.path.exists(PIPELINE), f"Pipeline file {PIPELINE} does not exist."
    assert os.path.isfile(PIPELINE), f"{PIPELINE} is not a file."


def test_output_file_exists():
    assert os.path.exists(OUTPUT_CSV), f"Output file {OUTPUT_CSV} does not exist."
    assert os.path.isfile(OUTPUT_CSV), f"{OUTPUT_CSV} is not a file."


def test_output_csv_content():
    assert os.path.exists(OUTPUT_CSV), f"Output file {OUTPUT_CSV} missing."

    with open(OUTPUT_CSV, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Output CSV is empty."

    header = rows[0]
    expected_header = ["timestamp", "device_id", "temp_c", "humidity_pct", "rolling_temp_c", "high_risk"]
    assert header == expected_header, f"Header mismatch. Expected {expected_header}, got {header}."

    data_rows = rows[1:]
    assert len(data_rows) == 8, f"Expected 8 data rows, got {len(data_rows)}."

    # Expected data computed from the rules
    expected_data = [
        ["2023-10-01T10:00:00", "D1", "28.0", "65.0", "28.0", "0"],
        ["2023-10-01T10:01:00", "D1", "29.5", "72.0", "28.75", "0"],
        ["2023-10-01T10:02:00", "D1", "31.0", "75.0", "29.5", "0"],
        ["2023-10-01T10:03:00", "D1", "32.0", "71.0", "30.83", "1"],
        ["2023-10-01T10:04:00", "D1", "33.0", "60.0", "32.0", "0"],
        ["2023-10-01T10:00:00", "D2", "25.0", "80.0", "25.0", "0"],
        ["2023-10-01T10:01:00", "D2", "26.0", "85.0", "25.5", "0"],
        ["2023-10-01T10:02:00", "D2", "27.0", "75.0", "26.0", "0"],
    ]

    for i, (actual, expected) in enumerate(zip(data_rows, expected_data)):
        # Compare each field
        assert actual[0] == expected[0], f"Row {i+1}: timestamp mismatch. Expected {expected[0]}, got {actual[0]}."
        assert actual[1] == expected[1], f"Row {i+1}: device_id mismatch. Expected {expected[1]}, got {actual[1]}."
        assert float(actual[2]) == float(expected[2]), f"Row {i+1}: temp_c mismatch. Expected {expected[2]}, got {actual[2]}."
        assert float(actual[3]) == float(expected[3]), f"Row {i+1}: humidity_pct mismatch. Expected {expected[3]}, got {actual[3]}."
        assert float(actual[4]) == float(expected[4]), f"Row {i+1}: rolling_temp_c mismatch. Expected {expected[4]}, got {actual[4]}."
        assert actual[5] == expected[5], f"Row {i+1}: high_risk mismatch. Expected {expected[5]}, got {actual[5]}."


def test_pipeline_on_derived_inputs():
    original_temperature = open(TEMPERATURE_CSV, "rb").read()
    original_humidity = open(HUMIDITY_CSV, "rb").read()

    rng = random.SystemRandom()
    suffix = secrets.token_hex(4)
    device_a = f"A_{suffix}"
    device_b = f"B_{suffix}"
    adjustment = rng.choice([0.1, 0.2, 0.4, 0.7, 0.8])

    timestamps_a = [f"2026-04-15T09:0{i}:00" for i in range(4)]
    timestamps_b = [f"2026-04-15T10:0{i}:00" for i in range(3)]
    temps_a = [28.0 + adjustment, 34.0 + adjustment, 31.0 + adjustment, 35.0 + adjustment]
    hums_a = [80.0 + adjustment, 75.0 + adjustment, 69.0 + adjustment, 90.0 + adjustment]
    temps_b = [39.0 + adjustment, 10.0 + adjustment, 44.0 + adjustment]
    hums_b = [72.0 + adjustment, 99.0 - adjustment, 71.0 + adjustment]

    temperature_rows = [
        [ts, device_a, temp] for ts, temp in zip(timestamps_a, temps_a)
    ] + [
        [ts, device_b, temp] for ts, temp in zip(timestamps_b, temps_b)
    ] + [["2026-04-15T11:00:00", f"TEMP_ONLY_{suffix}", 99.0]]

    humidity_rows = [
        [ts, device_a, hum] for ts, hum in zip(timestamps_a, hums_a)
    ] + [
        [ts, device_b, hum] for ts, hum in zip(timestamps_b, hums_b)
    ] + [["2026-04-15T12:00:00", f"HUM_ONLY_{suffix}", 99.0]]

    rng.shuffle(temperature_rows)
    rng.shuffle(humidity_rows)

    try:
        with open(TEMPERATURE_CSV, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "device_id", "temp_c"])
            writer.writerows(temperature_rows)

        with open(HUMIDITY_CSV, "w", newline="") as f:
            writer = csv.writer(f)
            writer.writerow(["timestamp", "device_id", "humidity_pct"])
            writer.writerows(humidity_rows)

        completed = subprocess.run(
            ["python3", PIPELINE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
        assert completed.returncode == 0, f"Pipeline failed on alternate inputs: {completed.stderr}"
        assert os.path.isfile(OUTPUT_CSV), "Pipeline did not create output.csv on alternate inputs."

        temp_by_key = {(row[1], row[0]): float(row[2]) for row in temperature_rows}
        hum_by_key = {(row[1], row[0]): float(row[2]) for row in humidity_rows}
        joined_keys = sorted(set(temp_by_key) & set(hum_by_key))

        history = {}
        expected_rows = []
        for device_id, timestamp in joined_keys:
            temp = temp_by_key[(device_id, timestamp)]
            humidity = hum_by_key[(device_id, timestamp)]
            history.setdefault(device_id, []).append(temp)
            rolling = round(sum(history[device_id][-3:]) / len(history[device_id][-3:]), 2)
            high_risk = 1 if rolling > 30.0 and humidity > 70.0 else 0
            expected_rows.append([timestamp, device_id, temp, humidity, rolling, high_risk])

        with open(OUTPUT_CSV, "r", newline="") as f:
            actual_rows = list(csv.reader(f))

        assert actual_rows, "Output CSV is empty on alternate inputs."
        assert actual_rows[0] == EXPECTED_HEADER, f"Header mismatch on alternate inputs: {actual_rows[0]}"
        assert len(actual_rows[1:]) == len(expected_rows), "Inner join produced the wrong number of rows."

        for index, (actual, expected) in enumerate(zip(actual_rows[1:], expected_rows), start=1):
            assert len(actual) == 6, f"Alternate row {index} has the wrong number of columns."
            assert actual[0] == expected[0], f"Alternate row {index}: timestamp/order mismatch."
            assert actual[1] == expected[1], f"Alternate row {index}: device/order mismatch."
            assert float(actual[2]) == pytest.approx(expected[2]), f"Alternate row {index}: temp mismatch."
            assert float(actual[3]) == pytest.approx(expected[3]), f"Alternate row {index}: humidity mismatch."
            assert float(actual[4]) == pytest.approx(expected[4]), f"Alternate row {index}: rolling average mismatch."
            assert actual[5] == str(expected[5]), f"Alternate row {index}: high_risk mismatch."
    finally:
        with open(TEMPERATURE_CSV, "wb") as f:
            f.write(original_temperature)
        with open(HUMIDITY_CSV, "wb") as f:
            f.write(original_humidity)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
