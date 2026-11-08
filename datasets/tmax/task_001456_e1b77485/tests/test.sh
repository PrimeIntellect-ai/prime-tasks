#!/bin/bash
set -e
mkdir -p /logs/verifier

verify() {
    if [[ ! -f /home/user/cleaner.go || -L /home/user/cleaner.go ]]; then
        echo "Missing regular Go source file: /home/user/cleaner.go" >&2
        return 1
    fi

    timeout 30s go build -o /tmp/cleaner-under-test /home/user/cleaner.go || return 1

    # Restore the original dataset, execute the submitted program, and retain all
    # assertions from the original verifier.
    cat << 'EOF' > /home/user/sensor_data.csv
ID,Timestamp,Temperature,Humidity
1,2023-10-01T00:00:00Z,22.5,45.0
1,2023-10-01T01:00:00Z,,45.5
1,2023-10-01T02:00:00Z,100.0,46.0
2,2023-10-01T00:00:00Z,23.0,40.0
2,2023-10-01T01:00:00Z,23.5,
3,2023-10-01T00:00:00Z,21.0,50.0
4,2023-10-01T00:00:00Z,-15.0,30.0
EOF

    cat << 'EOF' > /home/user/sensor_metadata.csv
ID,Location,Model
1,Lab1,X100
2,Lab2,Y200
3,Lab1,X100
4,Lab3,Z300
EOF

    rm -f /home/user/cleaned_data.csv /home/user/experiment_metrics.json
    (cd /home/user && timeout 30s /tmp/cleaner-under-test) || return 1

    cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import csv
import json
import math
import pytest

CLEANED_DATA_PATH = "/home/user/cleaned_data.csv"
METRICS_PATH = "/home/user/experiment_metrics.json"

def test_cleaned_data_csv():
    assert os.path.exists(CLEANED_DATA_PATH), f"File {CLEANED_DATA_PATH} does not exist."
    assert os.path.isfile(CLEANED_DATA_PATH), f"Path {CLEANED_DATA_PATH} is not a file."

    expected_rows = [
        ["ID", "Timestamp", "Temperature", "Humidity", "Location", "Model"],
        ["1", "2023-10-01T00:00:00Z", "22.5", "45.0", "Lab1", "X100"],
        ["2", "2023-10-01T00:00:00Z", "23.0", "40.0", "Lab2", "Y200"],
        ["3", "2023-10-01T00:00:00Z", "21.0", "50.0", "Lab1", "X100"]
    ]

    with open(CLEANED_DATA_PATH, "r", newline="") as f:
        reader = csv.reader(f)
        actual_rows = list(reader)

    assert len(actual_rows) == len(expected_rows), f"Expected {len(expected_rows)} rows in {CLEANED_DATA_PATH}, got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Row {i} mismatch in {CLEANED_DATA_PATH}. Expected {expected}, got {actual}."

def test_experiment_metrics_json():
    assert os.path.exists(METRICS_PATH), f"File {METRICS_PATH} does not exist."
    assert os.path.isfile(METRICS_PATH), f"Path {METRICS_PATH} is not a file."

    with open(METRICS_PATH, "r") as f:
        try:
            metrics = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {METRICS_PATH} is not valid JSON.")

    expected_keys = {
        "initial_rows",
        "rows_after_missing_drop",
        "rows_after_outlier_drop",
        "final_mean_temperature"
    }

    assert set(metrics.keys()) == expected_keys, f"Metrics keys mismatch. Expected {expected_keys}, got {set(metrics.keys())}."

    assert metrics["initial_rows"] == 7, f"Expected initial_rows to be 7, got {metrics['initial_rows']}."
    assert metrics["rows_after_missing_drop"] == 5, f"Expected rows_after_missing_drop to be 5, got {metrics['rows_after_missing_drop']}."
    assert metrics["rows_after_outlier_drop"] == 3, f"Expected rows_after_outlier_drop to be 3, got {metrics['rows_after_outlier_drop']}."

    expected_mean = (22.5 + 23.0 + 21.0) / 3
    assert math.isclose(metrics["final_mean_temperature"], expected_mean, rel_tol=1e-5), f"Expected final_mean_temperature to be approx {expected_mean}, got {metrics['final_mean_temperature']}."
TEST_EOF

    python3 -m pytest /tmp/test_final_state.py -x --tb=short || return 1

    # Exercise the compiled artifact on a fresh, unpredictable dataset. Expected
    # outputs are derived here rather than trusted from pre-existing files.
    python3 << 'DYNAMIC_EOF'
import csv
import json
import math
import os
import random
import secrets
import subprocess

home = "/home/user"
token = secrets.token_hex(5)
base = secrets.randbelow(700000) + 100000
ids = [str(base + i) for i in range(9)]
mid_temp = 10.0 + secrets.randbelow(25000) / 1000.0
high_outlier = 50.001 + secrets.randbelow(9000) / 1000.0
low_outlier = -10.001 - secrets.randbelow(9000) / 1000.0
mid_text = f"{mid_temp:.3f}"
high_text = f"{high_outlier:.3f}"
low_text = f"{low_outlier:.3f}"

sensor_rows = [
    [ids[0], f"2042-01-01T00:00:00Z", "-10.0", "31.1"],
    [ids[1], f"2042-01-01T01:00:00Z", "50.0", "32.2"],
    [ids[2], f"2042-01-01T02:00:00Z", mid_text, "33.3"],
    [ids[3], f"2042-01-01T03:00:00Z", high_text, "34.4"],
    [ids[4], f"2042-01-01T04:00:00Z", low_text, "35.5"],
    [ids[5], f"2042-01-01T05:00:00Z", "", "36.6"],
    [ids[6], f"2042-01-01T06:00:00Z", "12.5", ""],
    [ids[7], "", "13.5", "37.7"],
    [ids[8], f"2042-01-01T08:00:00Z", "14.5", "38.8"],
]

metadata = []
for i, sensor_id in enumerate(ids):
    location = f"Location-{token}-{i}"
    model = f"Model-{token}-{i}"
    if i == 8:
        location = ""
    metadata.append([sensor_id, location, model])
random.SystemRandom().shuffle(metadata)

with open(os.path.join(home, "sensor_data.csv"), "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["ID", "Timestamp", "Temperature", "Humidity"])
    writer.writerows(sensor_rows)

with open(os.path.join(home, "sensor_metadata.csv"), "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["ID", "Location", "Model"])
    writer.writerows(metadata)

for name in ("cleaned_data.csv", "experiment_metrics.json"):
    try:
        os.remove(os.path.join(home, name))
    except FileNotFoundError:
        pass

subprocess.run(["/tmp/cleaner-under-test"], cwd=home, check=True, timeout=30)

metadata_by_id = {row[0]: row[1:] for row in metadata}
expected = [["ID", "Timestamp", "Temperature", "Humidity", "Location", "Model"]]
for row in sensor_rows[:3]:
    expected.append(row + metadata_by_id[row[0]])

cleaned_path = os.path.join(home, "cleaned_data.csv")
metrics_path = os.path.join(home, "experiment_metrics.json")
assert os.path.isfile(cleaned_path), "cleaned_data.csv was not generated"
assert os.path.isfile(metrics_path), "experiment_metrics.json was not generated"
with open(cleaned_path, newline="") as f:
    actual = list(csv.reader(f))
assert actual == expected, f"Dynamic cleaned CSV mismatch. Expected {expected!r}, got {actual!r}"

with open(metrics_path) as f:
    metrics = json.load(f)
keys = {"initial_rows", "rows_after_missing_drop", "rows_after_outlier_drop", "final_mean_temperature"}
assert set(metrics) == keys, f"Dynamic metrics keys mismatch: {set(metrics)!r}"
assert type(metrics["initial_rows"]) is int and metrics["initial_rows"] == 9
assert type(metrics["rows_after_missing_drop"]) is int and metrics["rows_after_missing_drop"] == 5
assert type(metrics["rows_after_outlier_drop"]) is int and metrics["rows_after_outlier_drop"] == 3
expected_mean = (-10.0 + 50.0 + mid_temp) / 3.0
assert isinstance(metrics["final_mean_temperature"], (int, float)) and not isinstance(metrics["final_mean_temperature"], bool)
assert math.isclose(metrics["final_mean_temperature"], expected_mean, rel_tol=1e-9, abs_tol=1e-9), (
    f"Dynamic mean mismatch: expected {expected_mean}, got {metrics['final_mean_temperature']}"
)
DYNAMIC_EOF
}

if verify; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
