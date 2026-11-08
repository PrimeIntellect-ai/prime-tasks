#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import json
import pytest

def test_output_file_exists():
    """Check if the output file is created at the correct location."""
    output_path = "/home/user/output/validated_sensors.csv"
    assert os.path.isfile(output_path), f"Output file {output_path} does not exist."

def test_output_content_and_logic():
    """Verify that the output file contains the correctly reshaped, merged, filtered, and formatted data."""
    output_path = "/home/user/output/validated_sensors.csv"

    # 1. Load the rules
    rules_path = "/home/user/data/rules.json"
    with open(rules_path, "r") as f:
        rules = json.load(f)

    # 2. Process Factory 1 (Wide Format)
    wide_path = "/home/user/data/factory_wide.csv"
    combined_data = []
    with open(wide_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            combined_data.append({
                "timestamp": row["timestamp"],
                "factory_id": row["factory"],
                "temp": row.get("temp"),
                "pressure": row.get("pressure"),
                "humidity": row.get("humidity")
            })

    # 3. Process Factory 2 (Long Format)
    long_path = "/home/user/data/factory_long.csv"
    long_temp = {}
    with open(long_path, "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            key = (row["time_log"], row["fid"])
            if key not in long_temp:
                long_temp[key] = {"timestamp": key[0], "factory_id": key[1]}
            long_temp[key][row["metric"]] = row["val"]

    combined_data.extend(long_temp.values())

    # 4. Filter, Validate, and Format
    expected_rows = []
    for row in combined_data:
        # Check completeness
        if not all(k in row and row[k] is not None and row[k] != "" for k in ["temp", "pressure", "humidity"]):
            continue

        try:
            temp = float(row["temp"])
            pressure = float(row["pressure"])
            humidity = float(row["humidity"])
        except ValueError:
            continue # Drop if non-numeric

        # Check constraints
        if not (rules["temp"]["min"] <= temp <= rules["temp"]["max"]):
            continue
        if not (rules["pressure"]["min"] <= pressure <= rules["pressure"]["max"]):
            continue
        if not (rules["humidity"]["min"] <= humidity <= rules["humidity"]["max"]):
            continue

        # Format to 1 decimal place
        expected_rows.append({
            "timestamp": row["timestamp"],
            "factory_id": row["factory_id"],
            "temp": f"{temp:.1f}",
            "pressure": f"{pressure:.1f}",
            "humidity": f"{humidity:.1f}"
        })

    # 5. Sort by timestamp, then factory_id
    expected_rows.sort(key=lambda x: (x["timestamp"], x["factory_id"]))

    # 6. Read actual output and compare
    with open(output_path, "r") as f:
        reader = csv.DictReader(f)
        actual_rows = list(reader)
        actual_fieldnames = reader.fieldnames

    expected_fieldnames = ["timestamp", "factory_id", "temp", "pressure", "humidity"]
    assert actual_fieldnames == expected_fieldnames, f"Header mismatch. Expected {expected_fieldnames}, got {actual_fieldnames}."

    assert len(actual_rows) == len(expected_rows), f"Row count mismatch. Expected {len(expected_rows)} valid rows, got {len(actual_rows)}."

    for i, (actual, expected) in enumerate(zip(actual_rows, expected_rows)):
        assert actual == expected, f"Data mismatch at row {i+1} (excluding header). Expected {expected}, got {actual}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
