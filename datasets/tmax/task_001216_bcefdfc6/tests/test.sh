#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import json
import csv
import re
from datetime import datetime, timedelta

BASE_DIR = "/home/user/sensor_etl"
DATA_DIR = os.path.join(BASE_DIR, "data")
OUTPUT_FILE = os.path.join(BASE_DIR, "output", "final_metrics.csv")
MAKEFILE = os.path.join(BASE_DIR, "Makefile")

def parse_iso(dt_str):
    return datetime.strptime(dt_str, "%Y-%m-%dT%H:%M:%SZ")

def format_iso(dt):
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")

def compute_expected_data():
    # 1. Read metadata
    with open(os.path.join(DATA_DIR, "metadata.json"), "r") as f:
        metadata = json.load(f)

    # 2. Read calibrations
    calibrations = []
    calib_pattern = re.compile(r"\[.*?\] (.*?) - Sensor \[(.*?)\] calibrated\. New multiplier: (.*)")
    with open(os.path.join(DATA_DIR, "calibrations.log"), "r") as f:
        for line in f:
            match = calib_pattern.search(line)
            if match:
                ts, sensor, mult = match.groups()
                calibrations.append({
                    "timestamp": parse_iso(ts),
                    "sensor": sensor,
                    "multiplier": float(mult)
                })

    # 3. Read raw readings
    raw_readings = []
    with open(os.path.join(DATA_DIR, "raw_readings.csv"), "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            raw_readings.append({
                "timestamp": parse_iso(row["timestamp"]),
                "sensor": row["sensor_id"],
                "raw_value": float(row["raw_value"])
            })

    # Compute true values
    true_readings = []
    for r in raw_readings:
        sensor = r["sensor"]
        ts = r["timestamp"]
        raw_val = r["raw_value"]

        # Find latest calibration at or before ts
        applicable_calibs = [c for c in calibrations if c["sensor"] == sensor and c["timestamp"] <= ts]
        mult = 1.0
        if applicable_calibs:
            applicable_calibs.sort(key=lambda x: x["timestamp"])
            mult = applicable_calibs[-1]["multiplier"]

        baseline = metadata.get(sensor, {}).get("baseline", 0.0)
        true_val = (raw_val * mult) - baseline
        true_readings.append({
            "timestamp": ts,
            "sensor": sensor,
            "true_value": true_val
        })

    # Resample
    start_time = parse_iso("2023-11-01T10:00:00Z")
    end_time = parse_iso("2023-11-01T10:10:00Z")

    sensors = sorted(list(metadata.keys()))
    resampled = {s: {} for s in sensors}

    curr_time = start_time
    while curr_time <= end_time:
        for s in sensors:
            # Forward fill: find latest reading at or before curr_time
            past_readings = [r for r in true_readings if r["sensor"] == s and r["timestamp"] <= curr_time]
            if past_readings:
                past_readings.sort(key=lambda x: x["timestamp"])
                val = past_readings[-1]["true_value"]
            else:
                val = None
            resampled[s][curr_time] = val
        curr_time += timedelta(minutes=1)

    # Rolling average and format
    expected_rows = []
    curr_time = start_time
    while curr_time <= end_time:
        for s in sensors:
            val = resampled[s][curr_time]

            # 3-min window: curr, curr-1m, curr-2m
            window_vals = []
            for offset in [0, 1, 2]:
                t = curr_time - timedelta(minutes=offset)
                if t in resampled[s] and resampled[s][t] is not None:
                    window_vals.append(resampled[s][t])

            if window_vals:
                avg = sum(window_vals) / len(window_vals)
            else:
                avg = None

            expected_rows.append({
                "timestamp": format_iso(curr_time),
                "sensor_id": s,
                "resampled_true_value": f"{val:.2f}" if val is not None else "",
                "rolling_3min_avg": f"{avg:.2f}" if avg is not None else ""
            })
        curr_time += timedelta(minutes=1)

    return expected_rows

def test_makefile_exists():
    assert os.path.isfile(MAKEFILE), f"Makefile not found at {MAKEFILE}"

def test_output_file_exists():
    assert os.path.isfile(OUTPUT_FILE), f"Output file not found at {OUTPUT_FILE}"

def test_output_content():
    expected_rows = compute_expected_data()

    actual_rows = []
    with open(OUTPUT_FILE, "r") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["timestamp", "sensor_id", "resampled_true_value", "rolling_3min_avg"], \
            "CSV headers do not match the required specification."
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows in output, but got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual["timestamp"] == expected["timestamp"], f"Row {i+1}: expected timestamp {expected['timestamp']}, got {actual['timestamp']}"
        assert actual["sensor_id"] == expected["sensor_id"], f"Row {i+1}: expected sensor_id {expected['sensor_id']}, got {actual['sensor_id']}"
        assert actual["resampled_true_value"] == expected["resampled_true_value"], \
            f"Row {i+1} ({expected['timestamp']} {expected['sensor_id']}): expected resampled_true_value {expected['resampled_true_value']}, got {actual['resampled_true_value']}"
        assert actual["rolling_3min_avg"] == expected["rolling_3min_avg"], \
            f"Row {i+1} ({expected['timestamp']} {expected['sensor_id']}): expected rolling_3min_avg {expected['rolling_3min_avg']}, got {actual['rolling_3min_avg']}"
TEST_EOF

BASE_DIR=/home/user/sensor_etl
DATA_DIR="$BASE_DIR/data"
OUTPUT_FILE="$BASE_DIR/output/final_metrics.csv"
BACKUP_DIR=$(mktemp -d)
result=0

restore_inputs() {
    cp "$BACKUP_DIR/metadata.json" "$DATA_DIR/metadata.json" 2>/dev/null || true
    cp "$BACKUP_DIR/calibrations.log" "$DATA_DIR/calibrations.log" 2>/dev/null || true
    cp "$BACKUP_DIR/raw_readings.csv" "$DATA_DIR/raw_readings.csv" 2>/dev/null || true
}

run_pipeline_and_tests() {
    rm -f "$OUTPUT_FILE" || return 1
    timeout 60s make --no-print-directory -C "$BASE_DIR" || return 1
    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short || return 1
}

make_dynamic_inputs() {
    python3 - << 'PY'
import csv
import json
import secrets

base = "/home/user/sensor_etl/data"
b1 = 7 + secrets.randbelow(12)
b2 = 3 + secrets.randbelow(9)
r = [31 + secrets.randbelow(30), 72 + secrets.randbelow(35),
     61 + secrets.randbelow(30), 95 + secrets.randbelow(35),
     125 + secrets.randbelow(30)]
m1 = [0.80, 0.90, 1.20, 1.30][secrets.randbelow(4)]
m2 = [0.70, 0.85, 1.15, 1.25][secrets.randbelow(4)]

with open(base + "/metadata.json", "w") as f:
    json.dump({"S-01": {"baseline": float(b1)},
               "S-02": {"baseline": float(b2)}}, f)

with open(base + "/calibrations.log", "w") as f:
    f.write("[INFO] 2023-11-01T09:54:00Z - System boot sequence initiated.\n")
    f.write(f"[INFO] 2023-11-01T10:02:30Z - Sensor [S-01] calibrated. New multiplier: {m1:.2f}\n")
    f.write("this line is deliberately not a calibration record\n")
    f.write(f"[INFO] 2023-11-01T10:07:00Z - Sensor [S-02] calibrated. New multiplier: {m2:.2f}\n")

rows = [
    ["2023-11-01T10:00:15Z", "S-01", f"{r[0]}.0"],
    ["2023-11-01T10:00:45Z", "S-02", f"{r[1]}.0"],
    ["2023-11-01T10:03:10Z", "S-01", f"{r[2]}.0"],
    ["2023-11-01T10:04:05Z", "S-02", f"{r[3]}.0"],
    ["2023-11-01T10:08:20Z", "S-02", f"{r[4]}.0"],
]
with open(base + "/raw_readings.csv", "w", newline="") as f:
    writer = csv.writer(f)
    writer.writerow(["timestamp", "sensor_id", "raw_value"])
    writer.writerows(rows)
PY
}

if ! cp "$DATA_DIR/metadata.json" "$DATA_DIR/calibrations.log" "$DATA_DIR/raw_readings.csv" "$BACKUP_DIR/"; then
    result=1
else
    # The default target must regenerate a deleted output for the supplied data.
    if ! run_pipeline_and_tests; then
        result=1
    # Then exercise the same pipeline against verifier-generated values so a
    # hardcoded CSV or fixture-specific recipe cannot pass.
    elif ! make_dynamic_inputs; then
        result=1
    elif ! run_pipeline_and_tests; then
        result=1
    else
        restore_inputs
        # Recheck and leave the requested artifact generated from the original inputs.
        if ! run_pipeline_and_tests; then
            result=1
        fi
    fi
fi

restore_inputs
if [ "$result" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    rm -f "$OUTPUT_FILE"
    timeout 60s make --no-print-directory -C "$BASE_DIR" >/dev/null 2>&1 || true
    echo "0" > /logs/verifier/reward.txt
fi
rm -rf "$BACKUP_DIR"
