#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import math
import os
import pytest

PROCESSED_FILE = "/home/user/sensors_processed.csv"
RAW_FILE = "/home/user/sensors_raw.csv"
RAW_HEADERS = ["Timestamp", "SensorID", "CoordX", "CoordY", "Temperature"]
EXPECTED_RAW_ROWS = [
    {"Timestamp": "100", "SensorID": "S1", "CoordX": "3.0", "CoordY": "4.0", "Temperature": "20.0"},
    {"Timestamp": "101", "SensorID": "S2", "CoordX": "5.0", "CoordY": "12.0", "Temperature": "25.0"},
    {"Timestamp": "102", "SensorID": "S1", "CoordX": "3.0", "CoordY": "4.0", "Temperature": "20.0"},
    {"Timestamp": "103", "SensorID": "S1", "CoordX": "3.0", "CoordY": "4.0", "Temperature": "21.0"},
    {"Timestamp": "104", "SensorID": "S1", "CoordX": "3.0", "CoordY": "4.0", "Temperature": "22.0"},
    {"Timestamp": "105", "SensorID": "S2", "CoordX": "5.0", "CoordY": "12.0", "Temperature": "26.0"},
    {"Timestamp": "106", "SensorID": "S1", "CoordX": "3.0", "CoordY": "4.0", "Temperature": "23.0"},
    {"Timestamp": "107", "SensorID": "S1", "CoordX": "3.0", "CoordY": "4.0", "Temperature": "35.0"},
    {"Timestamp": "108", "SensorID": "S2", "CoordX": "5.0", "CoordY": "12.0", "Temperature": "26.0"},
    {"Timestamp": "109", "SensorID": "S2", "CoordX": "5.0", "CoordY": "12.0", "Temperature": "27.0"},
    {"Timestamp": "110", "SensorID": "S2", "CoordX": "5.0", "CoordY": "12.0", "Temperature": "45.0"},
]

def compute_expected_data():
    """Derives expected data after verifying the raw input is the supplied dataset."""
    if not os.path.exists(RAW_FILE):
        pytest.fail(f"Raw file {RAW_FILE} is missing, cannot compute expected state.")

    with open(RAW_FILE, "r", newline="") as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == RAW_HEADERS, (
            f"Raw file headers were modified. Expected {RAW_HEADERS}, got {reader.fieldnames}."
        )
        rows = list(reader)

    assert rows == EXPECTED_RAW_ROWS, "The supplied raw sensor dataset was modified."

    # Ensure sorted by timestamp for chronological processing
    rows.sort(key=lambda x: int(x["Timestamp"]))

    seen = set()
    deduped = []
    for row in rows:
        key = (row["SensorID"], row["CoordX"], row["CoordY"], row["Temperature"])
        if key not in seen:
            seen.add(key)
            deduped.append(row)

    history = {}
    processed = []
    for row in deduped:
        ts = int(row["Timestamp"])
        sid = row["SensorID"]
        cx = float(row["CoordX"])
        cy = float(row["CoordY"])
        temp = float(row["Temperature"])

        dist = round(math.sqrt(cx**2 + cy**2), 2)

        if sid not in history:
            history[sid] = []

        prev_temps = history[sid][-3:]
        if not prev_temps:
            rolling_avg = "N/A"
            status = "NORMAL"
        else:
            avg_temp = sum(prev_temps) / len(prev_temps)
            rolling_avg = round(avg_temp, 2)
            if temp > 1.5 * rolling_avg:
                status = "ANOMALY"
            else:
                status = "NORMAL"

        history[sid].append(temp)

        processed.append({
            "Timestamp": ts,
            "SensorID": sid,
            "Distance": dist,
            "RollingAvgTemp": rolling_avg,
            "Status": status
        })

    processed.sort(key=lambda x: (x["Timestamp"], x["SensorID"]))
    return processed

def test_processed_file_exists():
    """Test that the processed CSV file exists."""
    assert os.path.exists(PROCESSED_FILE), f"The file {PROCESSED_FILE} was not created."
    assert os.path.isfile(PROCESSED_FILE), f"The path {PROCESSED_FILE} is not a file."

def test_processed_file_headers():
    """Test that the processed CSV has the exact expected headers."""
    expected_headers = ["Timestamp", "SensorID", "Distance", "RollingAvgTemp", "Status"]

    with open(PROCESSED_FILE, "r", newline="") as f:
        reader = csv.reader(f)
        try:
            headers = next(reader)
        except StopIteration:
            pytest.fail(f"The file {PROCESSED_FILE} is empty.")

    assert headers == expected_headers, f"Headers in {PROCESSED_FILE} are incorrect. Expected {expected_headers}, got {headers}."

def test_processed_file_contents():
    """Test that the processed CSV contains the correctly derived data, allowing flexible float formatting."""
    expected_data = compute_expected_data()

    actual_data = []
    with open(PROCESSED_FILE, "r", newline="") as f:
        reader = csv.DictReader(f)
        for row in reader:
            actual_data.append(row)

    assert len(actual_data) == len(expected_data), f"Expected {len(expected_data)} rows, but found {len(actual_data)} rows. Deduplication or processing failed."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert int(actual["Timestamp"]) == expected["Timestamp"], f"Row {i+1}: Timestamp mismatch."
        assert actual["SensorID"] == expected["SensorID"], f"Row {i+1}: SensorID mismatch."

        actual_dist = float(actual["Distance"])
        assert math.isclose(actual_dist, expected["Distance"], rel_tol=1e-5), f"Row {i+1}: Distance mismatch. Expected {expected['Distance']}, got {actual_dist}."

        if expected["RollingAvgTemp"] == "N/A":
            assert actual["RollingAvgTemp"] == "N/A", f"Row {i+1}: RollingAvgTemp mismatch. Expected 'N/A', got '{actual['RollingAvgTemp']}'."
        else:
            actual_avg = float(actual["RollingAvgTemp"])
            assert math.isclose(actual_avg, expected["RollingAvgTemp"], rel_tol=1e-5), f"Row {i+1}: RollingAvgTemp mismatch. Expected {expected['RollingAvgTemp']}, got {actual_avg}."

        assert actual["Status"] == expected["Status"], f"Row {i+1}: Status mismatch. Expected {expected['Status']}, got {actual['Status']}."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
