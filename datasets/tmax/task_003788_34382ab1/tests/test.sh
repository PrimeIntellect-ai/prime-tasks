#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import csv
import io
import math
import subprocess
import time
import requests
import pytest

def get_ground_truth():
    # Run the binary
    result = subprocess.run(["/app/sensor_gen", "5000"], capture_output=True, text=True, check=True)
    raw_csv = result.stdout

    # Parse CSV
    reader = csv.DictReader(io.StringIO(raw_csv))

    seen_ids = set()
    clean_rows = []

    for row in reader:
        row_id = row['id']
        if row_id in seen_ids:
            continue
        seen_ids.add(row_id)

        # Check for empty or NaN in sensors
        try:
            val_a = float(row['sensor_A'])
            val_b = float(row['sensor_B'])
            val_c = float(row['sensor_C'])
        except (ValueError, TypeError):
            continue

        if math.isnan(val_a) or math.isnan(val_b) or math.isnan(val_c):
            continue

        clean_rows.append({
            'id': int(row_id),
            'timestamp': int(row['timestamp']),
            'sensor_A': val_a,
            'sensor_B': val_b,
            'sensor_C': val_c
        })

    # Reshape to long format
    long_data = []
    for row in clean_rows:
        long_data.append({'id': row['id'], 'timestamp': row['timestamp'], 'sensor': 'sensor_A', 'value': row['sensor_A']})
        long_data.append({'id': row['id'], 'timestamp': row['timestamp'], 'sensor': 'sensor_B', 'value': row['sensor_B']})
        long_data.append({'id': row['id'], 'timestamp': row['timestamp'], 'sensor': 'sensor_C', 'value': row['sensor_C']})

    # Sort by timestamp ascending
    long_data.sort(key=lambda x: x['timestamp'])

    total_clean_long_records = len(long_data)

    # Group by sensor to calculate anomalies
    sensor_data = {'sensor_A': [], 'sensor_B': [], 'sensor_C': []}
    for row in long_data:
        sensor_data[row['sensor']].append(row)

    anomalies = []
    for sensor, rows in sensor_data.items():
        window = []
        for i, row in enumerate(rows):
            val = row['value']
            if len(window) == 50:
                mean = sum(window) / 50.0
                variance = sum((x - mean) ** 2 for x in window) / 49.0
                std = math.sqrt(variance)

                if abs(val - mean) > 3.0 * std:
                    anomalies.append({
                        'id': row['id'],
                        'timestamp': row['timestamp'],
                        'sensor': sensor,
                        'value': val
                    })

                window.pop(0)
            window.append(val)

    # Sort anomalies by timestamp ascending, then sensor alphabetically
    anomalies.sort(key=lambda x: (x['timestamp'], x['sensor']))

    return total_clean_long_records, anomalies

def test_status_endpoint():
    total_records, _ = get_ground_truth()

    try:
        response = requests.get("http://127.0.0.1:8080/status", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to /status endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    data = response.json()
    assert data.get("status") == "ready", "Expected status to be 'ready'"
    assert data.get("total_clean_long_records") == total_records, f"Expected total_clean_long_records to be {total_records}, got {data.get('total_clean_long_records')}"

def test_anomalies_endpoint():
    _, expected_anomalies = get_ground_truth()

    try:
        response = requests.get("http://127.0.0.1:8080/anomalies", timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to /anomalies endpoint: {e}")

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"

    actual_anomalies = response.json()

    assert len(actual_anomalies) == len(expected_anomalies), f"Expected {len(expected_anomalies)} anomalies, got {len(actual_anomalies)}"

    for i, (actual, expected) in enumerate(zip(actual_anomalies, expected_anomalies)):
        assert actual['id'] == expected['id'], f"Mismatch at index {i}: expected id {expected['id']}, got {actual['id']}"
        assert actual['timestamp'] == expected['timestamp'], f"Mismatch at index {i}: expected timestamp {expected['timestamp']}, got {actual['timestamp']}"
        assert actual['sensor'] == expected['sensor'], f"Mismatch at index {i}: expected sensor {expected['sensor']}, got {actual['sensor']}"
        assert math.isclose(actual['value'], expected['value'], rel_tol=1e-5), f"Mismatch at index {i}: expected value {expected['value']}, got {actual['value']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
