#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import glob
import pytest
import requests
import pandas as pd
import numpy as np

def compute_expected_data(server_id):
    csv_files = glob.glob("/app/data/*.csv")
    df_list = [pd.read_csv(f) for f in csv_files]
    df = pd.concat(df_list, ignore_index=True)
    df['timestamp'] = pd.to_datetime(df['timestamp'])
    df = df.sort_values('timestamp').reset_index(drop=True)

    server_df = df[df['server_id'] == server_id].copy()
    server_df = server_df.set_index('timestamp')

    server_df['cpu'] = server_df['cpu'].interpolate(method='time').bfill().ffill()
    server_df['mem'] = server_df['mem'].interpolate(method='time').bfill().ffill()

    resampled = server_df.resample('30min').mean()
    resampled['cpu'] = resampled['cpu'].round(2)
    resampled['mem'] = resampled['mem'].round(2)

    resampled = resampled.reset_index()

    expected = []
    for _, row in resampled.iterrows():
        expected.append({
            "timestamp": row['timestamp'].strftime("%Y-%m-%dT%H:%M:%S"),
            "cpu": row['cpu'],
            "mem": row['mem']
        })
    return expected

def test_api_unauthorized():
    """Test that the API returns 401 when no token or incorrect token is provided."""
    url = "http://127.0.0.1:8080/api/metrics?server_id=srv-A"

    # Missing token
    try:
        resp = requests.get(url, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")
    assert resp.status_code == 401, f"Expected 401 Unauthorized without token, got {resp.status_code}"

    # Incorrect token
    resp = requests.get(url, headers={"Authorization": "Bearer wrong-token"}, timeout=5)
    assert resp.status_code == 401, f"Expected 401 Unauthorized with wrong token, got {resp.status_code}"

def test_api_authorized_srv_A():
    """Test that the API returns correct processed data for srv-A."""
    url = "http://127.0.0.1:8080/api/metrics?server_id=srv-A"
    headers = {"Authorization": "Bearer alpha-77X"}

    try:
        resp = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"

    data = resp.json()
    assert isinstance(data, list), "Expected response to be a JSON array"
    assert len(data) > 0, "Expected non-empty array"

    expected_data = compute_expected_data('srv-A')
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} buckets, got {len(data)}"

    for i in range(len(expected_data)):
        assert "timestamp" in data[i], "Missing 'timestamp' key"
        assert "cpu" in data[i], "Missing 'cpu' key"
        assert "mem" in data[i], "Missing 'mem' key"

        # Check values allowing small float differences
        assert data[i]["timestamp"] == expected_data[i]["timestamp"], f"Timestamp mismatch at index {i}"
        assert abs(data[i]["cpu"] - expected_data[i]["cpu"]) <= 0.02, f"CPU mismatch at index {i}: expected {expected_data[i]['cpu']}, got {data[i]['cpu']}"
        assert abs(data[i]["mem"] - expected_data[i]["mem"]) <= 0.02, f"Mem mismatch at index {i}: expected {expected_data[i]['mem']}, got {data[i]['mem']}"

def test_api_authorized_srv_B():
    """Test that the API returns correct processed data for srv-B."""
    url = "http://127.0.0.1:8080/api/metrics?server_id=srv-B"
    headers = {"Authorization": "Bearer alpha-77X"}

    try:
        resp = requests.get(url, headers=headers, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API: {e}")

    assert resp.status_code == 200, f"Expected 200 OK, got {resp.status_code}. Response: {resp.text}"

    data = resp.json()
    assert isinstance(data, list), "Expected response to be a JSON array"

    expected_data = compute_expected_data('srv-B')
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} buckets, got {len(data)}"

    for i in range(len(expected_data)):
        assert "timestamp" in data[i], "Missing 'timestamp' key"
        assert "cpu" in data[i], "Missing 'cpu' key"
        assert "mem" in data[i], "Missing 'mem' key"

        assert data[i]["timestamp"] == expected_data[i]["timestamp"], f"Timestamp mismatch at index {i}"
        assert abs(data[i]["cpu"] - expected_data[i]["cpu"]) <= 0.02, f"CPU mismatch at index {i}: expected {expected_data[i]['cpu']}, got {data[i]['cpu']}"
        assert abs(data[i]["mem"] - expected_data[i]["mem"]) <= 0.02, f"Mem mismatch at index {i}: expected {expected_data[i]['mem']}, got {data[i]['mem']}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
