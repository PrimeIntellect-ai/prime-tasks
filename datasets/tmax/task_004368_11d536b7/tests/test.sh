#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json

def test_cleaned_csv_exists():
    """Verify that the cleaned.csv file was generated."""
    assert os.path.isfile("/home/user/cleaned.csv"), "/home/user/cleaned.csv does not exist."

def test_cleaned_csv_contents():
    """Verify the contents of cleaned.csv match the expected data processing."""
    # 1. Derive expected data from the source file
    valid_records = []
    with open("/home/user/telemetry.jsonl", "r") as f:
        for line in f:
            try:
                record = json.loads(line)
                valid_records.append(record)
            except json.JSONDecodeError:
                pass

    # Sort chronologically
    valid_records.sort(key=lambda x: x["ts"])

    expected_rows = []
    for i, rec in enumerate(valid_records):
        start_idx = max(0, i - 2)
        window = [r["metric"] for r in valid_records[start_idx:i+1]]
        rolling_avg = sum(window) / len(window)
        rolling_avg_rounded = round(rolling_avg, 2)
        is_anomaly = rec["metric"] > rolling_avg + 20.0

        expected_rows.append({
            "ts": int(rec["ts"]),
            "user_ip": "***",
            "metric": float(rec["metric"]),
            "rolling_avg": rolling_avg_rounded,
            "is_anomaly": is_anomaly
        })

    # 2. Read the actual output file
    actual_rows = []
    with open("/home/user/cleaned.csv", "r") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ["ts", "user_ip", "metric", "rolling_avg", "is_anomaly"], \
            f"CSV headers are incorrect. Got: {reader.fieldnames}"

        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_rows), \
        f"Expected {len(expected_rows)} rows, but got {len(actual_rows)} rows. Did you filter invalid lines correctly?"

    # 3. Compare rows
    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert int(actual["ts"]) == expected["ts"], f"Row {i+1}: expected ts {expected['ts']}, got {actual['ts']}"
        assert actual["user_ip"] == expected["user_ip"], f"Row {i+1}: expected user_ip {expected['user_ip']}, got {actual['user_ip']}"
        assert float(actual["metric"]) == expected["metric"], f"Row {i+1}: expected metric {expected['metric']}, got {actual['metric']}"

        # rolling_avg might be formatted as '10.0' or '10.00' or '10'
        actual_avg = float(actual["rolling_avg"])
        assert abs(actual_avg - expected["rolling_avg"]) < 1e-5, \
            f"Row {i+1}: expected rolling_avg {expected['rolling_avg']}, got {actual_avg}"

        # is_anomaly could be 'True', 'true', 'False', 'false'
        actual_anomaly_str = actual["is_anomaly"].strip().lower()
        actual_anomaly = actual_anomaly_str == "true"
        assert actual_anomaly == expected["is_anomaly"], \
            f"Row {i+1}: expected is_anomaly {expected['is_anomaly']}, got {actual['is_anomaly']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
