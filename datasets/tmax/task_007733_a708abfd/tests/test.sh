#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import csv
import pytest

RAW_FILE = "/home/user/raw_sensors.csv"
OUT_FILE = "/home/user/high_risk_sensors.csv"
CANONICAL_RAW = b"""Sensor_ID,Temp,Pressure,Humidity,Vibration
S1,10.0,100.0,50.0,10.0
S2,15.5,80.0,40.0,5.0
S3,20.0,bad,50.0,10.0
S4,100.0,150.0,20.0,20.0,extra
S5,0.0,200.0,10.0,30.0
S6,-10.0,120.0,60.0,5.0
S7,-5.0,90.0,50.0,0.0
S8,5.0,100.0,-20.0,10.0
S9,10,100,50,10
"""

def is_float(val):
    try:
        float(val)
        return True
    except ValueError:
        return False

def compute_expected_data():
    if not os.path.exists(RAW_FILE):
        return []

    expected = []
    with open(RAW_FILE, "r") as f:
        reader = csv.reader(f)
        for i, row in enumerate(reader):
            if i == 0 and row and row[0] == "Sensor_ID":
                continue # Skip header

            if len(row) != 5:
                continue

            sensor_id, temp, pressure, humidity, vibration = row

            if not all(is_float(x) for x in [temp, pressure, humidity, vibration]):
                continue

            t_val = float(temp)
            p_val = float(pressure)
            h_val = float(humidity)
            v_val = float(vibration)

            risk_score = t_val * 0.2 + p_val * 0.5 + h_val * -0.1 + v_val * 1.2

            if risk_score > 50.0:
                expected.append({
                    "Sensor_ID": sensor_id,
                    "Temp": temp,
                    "Pressure": pressure,
                    "Humidity": humidity,
                    "Vibration": vibration,
                    "Risk_Score": float(f"{risk_score:.2f}"),
                    "Risk_Score_Str": f"{risk_score:.2f}"
                })

    # Sort descending by Risk_Score
    expected.sort(key=lambda x: x["Risk_Score"], reverse=True)
    return expected

def test_raw_input_unchanged():
    assert os.path.exists(RAW_FILE), f"The input file {RAW_FILE} was deleted."
    assert os.path.isfile(RAW_FILE), f"{RAW_FILE} is not a regular file."
    with open(RAW_FILE, "rb") as f:
        actual_raw = f.read()
    assert actual_raw == CANONICAL_RAW, f"The input file {RAW_FILE} was modified."

def test_output_file_exists():
    assert os.path.exists(OUT_FILE), f"The output file {OUT_FILE} was not created."
    assert os.path.isfile(OUT_FILE), f"{OUT_FILE} is not a regular file."

def test_output_format_and_data():
    expected_data = compute_expected_data()

    assert os.path.exists(OUT_FILE), f"Missing {OUT_FILE}"

    actual_rows = []
    with open(OUT_FILE, "r") as f:
        reader = csv.reader(f)
        for row in reader:
            actual_rows.append(row)

    assert len(actual_rows) == len(expected_data), f"Expected {len(expected_data)} rows, got {len(actual_rows)}."

    # Check sorting and content
    previous_score = float('inf')

    # We will map expected rows by Sensor_ID to easily check values
    expected_map = {d["Sensor_ID"]: d for d in expected_data}

    for i, row in enumerate(actual_rows):
        assert len(row) == 6, f"Row {i+1} does not have exactly 6 columns: {row}"

        sensor_id, temp, pressure, humidity, vibration, risk_score_str = row

        assert sensor_id in expected_map, f"Unexpected Sensor_ID '{sensor_id}' found in output."

        expected_row = expected_map[sensor_id]

        assert temp == expected_row["Temp"], f"Temp mismatch for {sensor_id}: expected {expected_row['Temp']}, got {temp}"
        assert pressure == expected_row["Pressure"], f"Pressure mismatch for {sensor_id}: expected {expected_row['Pressure']}, got {pressure}"
        assert humidity == expected_row["Humidity"], f"Humidity mismatch for {sensor_id}: expected {expected_row['Humidity']}, got {humidity}"
        assert vibration == expected_row["Vibration"], f"Vibration mismatch for {sensor_id}: expected {expected_row['Vibration']}, got {vibration}"

        assert risk_score_str == expected_row["Risk_Score_Str"], f"Risk_Score mismatch or formatting error for {sensor_id}: expected {expected_row['Risk_Score_Str']}, got {risk_score_str}"

        current_score = float(risk_score_str)
        assert current_score <= previous_score, f"Output is not sorted descending by Risk_Score. Row {i+1} has score {current_score} but previous was {previous_score}."
        previous_score = current_score

        # Remove from map to track duplicates/missing
        del expected_map[sensor_id]

    assert len(expected_map) == 0, f"Some expected sensors were missing from the output: {list(expected_map.keys())}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
