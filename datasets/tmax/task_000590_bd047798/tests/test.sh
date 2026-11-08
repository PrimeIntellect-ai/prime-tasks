#!/bin/bash
set +e
mkdir -p /logs/verifier
echo "0" > /logs/verifier/reward.txt
result=1

# Remove any pre-created artifacts and execute the submitted pipeline on the
# original input before applying the original assertions.
rm -f /home/user/cleaned_data.csv /home/user/anomalies.csv
if ! timeout 30s bash /home/user/etl_pipeline.sh; then
    result=0
fi

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

def test_script_exists():
    """Verify that the ETL pipeline script exists."""
    script_path = "/home/user/etl_pipeline.sh"
    assert os.path.isfile(script_path), f"Expected script {script_path} does not exist."

def test_cleaned_data_exists():
    """Verify that the cleaned data CSV exists."""
    csv_path = "/home/user/cleaned_data.csv"
    assert os.path.isfile(csv_path), f"Expected file {csv_path} does not exist."

def test_anomalies_exists():
    """Verify that the anomalies CSV exists."""
    csv_path = "/home/user/anomalies.csv"
    assert os.path.isfile(csv_path), f"Expected file {csv_path} does not exist."

def test_cleaned_data_content():
    """Verify the contents of the cleaned data CSV."""
    csv_path = "/home/user/cleaned_data.csv"
    if not os.path.exists(csv_path):
        pytest.fail(f"{csv_path} is missing.")

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Cleaned data CSV is empty."

    header = rows[0]
    expected_header = ["timestamp", "sensor_id", "value", "notes", "norm_value"]
    assert header == expected_header, f"Expected header {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 5, f"Expected 5 data rows after deduplication, got {len(data_rows)}"

    # Check specific row values to ensure correct cleaning and normalization
    expected_rows = [
        ["1600000000", "S1", "15.5", "Normal reading", "0.1571"],
        ["1600000005", "S1", "15.5", "Normal reading duplicate", "0.1571"],
        ["1600000010", "S1", "45.0", "Spike detected", "1.0000"],
        ["1600000015", "S2", "10.0", "S2 start", "0.0000"],
        ["1600000020", "S1", "16.0", "Back to normal", "0.1714"]
    ]

    for i, expected in enumerate(expected_rows):
        assert data_rows[i] == expected, f"Row {i+1} mismatch. Expected {expected}, got {data_rows[i]}"

def test_anomalies_content():
    """Verify the contents of the anomalies CSV."""
    csv_path = "/home/user/anomalies.csv"
    if not os.path.exists(csv_path):
        pytest.fail(f"{csv_path} is missing.")

    with open(csv_path, "r", newline="") as f:
        reader = csv.reader(f)
        rows = list(reader)

    assert len(rows) > 0, "Anomalies CSV is empty."

    header = rows[0]
    expected_header = ["timestamp", "sensor_id", "distance"]
    assert header == expected_header, f"Expected header {expected_header}, got {header}"

    data_rows = rows[1:]
    assert len(data_rows) == 2, f"Expected 2 anomaly rows, got {len(data_rows)}"

    expected_rows = [
        ["1600000010", "S1", "0.8429"],
        ["1600000020", "S1", "0.8286"]
    ]

    for i, expected in enumerate(expected_rows):
        assert data_rows[i] == expected, f"Anomaly row {i+1} mismatch. Expected {expected}, got {data_rows[i]}"
TEST_EOF

if ! python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    result=0
fi

# Generate a second, unpredictable input so a script that merely recreates the
# known fixture outputs cannot pass.
if ! python3 << 'GEN_EOF'
import csv
import random
import secrets

base = random.SystemRandom().randint(1700000000, 1900000000)
lo = random.SystemRandom().randint(100, 500)
span = 20 * random.SystemRandom().randint(2, 8)
a = "A_" + secrets.token_hex(4)
b = "B_" + secrets.token_hex(4)
tag = secrets.token_hex(6)
rows = [
    [str(base), a, str(lo), f"start {tag}\ncontinued"],
    [str(base + 20), b, str(lo + span // 2), f"second sensor {tag}"],
    [str(base + 10), a, str(lo + span), f"high {tag}\nreading"],
    [str(base + 10), a, str(lo + span * 3), f"duplicate must disappear {tag}"],
    [str(base + 30), a, str(lo + span // 20), f"return {tag}\nto low"],
    [str(base + 25), b, str(lo + span // 2 + 1), f"steady {tag}"],
]
path = "/home/user/raw_sensor_data.csv"
with open(path, "w", newline="") as f:
    w = csv.writer(f, lineterminator="\n")
    w.writerow(["timestamp", "sensor_id", "value", "notes"])
    w.writerows(rows)
with open(path, "rb") as src, open("/tmp/dynamic_raw_sensor_data.csv", "wb") as dst:
    dst.write(src.read())
GEN_EOF
then
    result=0
fi

rm -f /home/user/cleaned_data.csv /home/user/anomalies.csv
if ! timeout 30s bash /home/user/etl_pipeline.sh; then
    result=0
fi

cat << 'DYNAMIC_EOF' > /tmp/test_dynamic_state.py
import csv
import hashlib
import os

INPUT = "/tmp/dynamic_raw_sensor_data.csv"
CLEANED = "/home/user/cleaned_data.csv"
ANOMALIES = "/home/user/anomalies.csv"


def build_expected():
    with open(INPUT, "r", newline="") as f:
        source = list(csv.DictReader(f))

    deduped = []
    seen = set()
    for row in source:
        digest = hashlib.md5((row["timestamp"] + row["sensor_id"]).encode()).hexdigest()
        if digest in seen:
            continue
        seen.add(digest)
        row = dict(row)
        row["notes"] = row["notes"].replace("\r\n", "\n").replace("\r", "\n").replace("\n", " ")
        deduped.append(row)

    values = [float(row["value"]) for row in deduped]
    minimum, maximum = min(values), max(values)
    for row in deduped:
        row["norm"] = (float(row["value"]) - minimum) / (maximum - minimum)

    expected_cleaned = [["timestamp", "sensor_id", "value", "notes", "norm_value"]]
    expected_cleaned += [
        [row["timestamp"], row["sensor_id"], row["value"], row["notes"], f'{row["norm"]:.4f}']
        for row in deduped
    ]

    by_sensor = {}
    for row in deduped:
        by_sensor.setdefault(row["sensor_id"], []).append(row)
    found = []
    for sensor_rows in by_sensor.values():
        sensor_rows.sort(key=lambda row: int(row["timestamp"]))
        for previous, current in zip(sensor_rows, sensor_rows[1:]):
            distance = abs(current["norm"] - previous["norm"])
            if distance > 0.5:
                found.append([current["timestamp"], current["sensor_id"], f"{distance:.4f}"])
    found.sort(key=lambda row: int(row[0]))
    expected_anomalies = [["timestamp", "sensor_id", "distance"]] + found
    return expected_cleaned, expected_anomalies


def read_csv(path):
    assert os.path.isfile(path), f"Expected output {path} does not exist"
    with open(path, "r", newline="") as f:
        return list(csv.reader(f))


def test_dynamic_cleaned_output():
    expected_cleaned, _ = build_expected()
    actual = read_csv(CLEANED)
    assert actual == expected_cleaned, f"Dynamic cleaned output mismatch: expected {expected_cleaned}, got {actual}"


def test_dynamic_anomaly_output():
    _, expected_anomalies = build_expected()
    actual = read_csv(ANOMALIES)
    assert actual == expected_anomalies, f"Dynamic anomaly output mismatch: expected {expected_anomalies}, got {actual}"
DYNAMIC_EOF

if ! python3 -m pytest /tmp/test_dynamic_state.py -x --tb=short 2>&1; then
    result=0
fi

if [ "$result" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
