#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import subprocess
import json
import sqlite3
import requests
import pytest

def get_expected_frames():
    """Derive the expected number of frames using ffprobe."""
    cmd = [
        "ffprobe", "-v", "error", "-select_streams", "v:0",
        "-count_frames", "-show_entries", "stream=nb_read_frames",
        "-of", "default=nokey=1:noprint_wrappers=1", "/app/experiment.mp4"
    ]
    try:
        out = subprocess.check_output(cmd, text=True).strip()
        return int(out)
    except Exception:
        # Fallback to the known setup value if ffprobe fails
        return 150

def get_expected_max_sensor_id():
    """Derive the expected max sensor ID by computing the 3-row moving average."""
    conn = sqlite3.connect("/app/sensors.db")
    cur = conn.cursor()
    cur.execute("SELECT id, value FROM readings ORDER BY timestamp")
    rows = cur.fetchall()
    conn.close()

    max_avg = -1
    max_id = -1
    for i in range(len(rows)):
        start = max(0, i - 2)
        window = rows[start:i+1]
        avg = sum(r[1] for r in window) / len(window)
        if avg > max_avg:
            max_avg = avg
            max_id = rows[i][0]
    return max_id

def find_path(node, target, path):
    """Recursively find the path to the target node."""
    if node.get("name") == target:
        return path + [target]
    for child in node.get("children", []):
        res = find_path(child, target, path + [node.get("name")])
        if res:
            return res
    return None

def get_expected_anomaly_path():
    """Derive the expected anomaly path from the taxonomy JSON."""
    with open("/app/taxonomy.json") as f:
        data = json.load(f)
    path = find_path(data, "TargetAnomaly", [])
    return ".".join(path) if path else "root.experiments.active.TargetAnomaly"

def test_http_server_and_data():
    """Verify the HTTP server is running and serves the correct data.json payload."""
    expected_frames = get_expected_frames()
    expected_max_id = get_expected_max_sensor_id()
    expected_path = get_expected_anomaly_path()

    try:
        resp = requests.get("http://127.0.0.1:8080/data.json", timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to HTTP server at 127.0.0.1:8080/data.json: {e}. Ensure the server is running.")

    assert resp.status_code == 200, f"Expected HTTP 200, got {resp.status_code}. Response: {resp.text[:100]}"

    try:
        data = resp.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {resp.text[:100]}")

    assert "total_frames" in data, "Missing 'total_frames' in JSON response."
    assert data["total_frames"] == expected_frames, f"Expected total_frames={expected_frames}, got {data['total_frames']}."

    assert "max_sensor_id" in data, "Missing 'max_sensor_id' in JSON response."
    assert data["max_sensor_id"] == expected_max_id, f"Expected max_sensor_id={expected_max_id}, got {data['max_sensor_id']}."

    assert "anomaly_path" in data, "Missing 'anomaly_path' in JSON response."
    assert data["anomaly_path"] == expected_path, f"Expected anomaly_path='{expected_path}', got '{data['anomaly_path']}'."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
