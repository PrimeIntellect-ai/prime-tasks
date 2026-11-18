#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "requests:requests"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import secrets
import subprocess
from datetime import datetime, timezone

import pytest
import requests


def get_expected_distance(details):
    out = subprocess.check_output(["/app/log_distance", "root shell attempt", details])
    return float(out.strip())


def parse_timestamp(ts_str):
    try:
        ts = float(ts_str)
        dt = datetime.fromtimestamp(ts, tz=timezone.utc)
    except ValueError:
        dt = datetime.strptime(ts_str, "%m/%d/%Y %H:%M:%S").replace(tzinfo=timezone.utc)
    return dt.strftime("%Y-%m-%dT%H:%M:%SZ")


def get_expected_logs(max_distance):
    logs = []
    with open("/home/user/logs.csv", "r") as f:
        reader = csv.DictReader(f)
        for row in reader:
            dist = get_expected_distance(row["details"])
            if dist <= max_distance:
                logs.append({
                    "timestamp": parse_timestamp(row["raw_timestamp"]),
                    "ip": "X.X.X.X",
                    "action": row["action"],
                    "distance": dist,
                })
    logs.sort(key=lambda x: x["timestamp"])
    return logs


def fetch_logs(max_distance):
    url = "http://127.0.0.1:8080/api/anomalies"
    try:
        response = requests.get(url, params={"max_distance": repr(max_distance)}, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to the API at {url}: {e}")

    assert response.status_code == 200, f"Expected HTTP 200 OK, got {response.status_code}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Expected JSON response, got: {response.text}")
    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    return data


def assert_logs_equal(actual_data, expected_data, max_distance):
    assert len(actual_data) == len(expected_data), (
        f"Expected {len(expected_data)} logs for max_distance={max_distance}, "
        f"got {len(actual_data)}"
    )
    for i, (actual, expected) in enumerate(zip(actual_data, expected_data)):
        assert isinstance(actual, dict), f"Log {i} is not a JSON object"
        assert actual["timestamp"] == expected["timestamp"], (
            f"Log {i} timestamp mismatch: expected {expected['timestamp']}, "
            f"got {actual.get('timestamp')}"
        )
        assert actual["ip"] == expected["ip"], (
            f"Log {i} IP mismatch: expected {expected['ip']}, got {actual.get('ip')}"
        )
        assert actual["action"] == expected["action"], (
            f"Log {i} action mismatch: expected {expected['action']}, "
            f"got {actual.get('action')}"
        )
        assert abs(float(actual["distance"]) - expected["distance"]) < 0.01, (
            f"Log {i} distance mismatch: expected {expected['distance']}, "
            f"got {actual.get('distance')}"
        )


def test_api_anomalies_endpoint():
    """Retain the original max_distance=1.5 behavior check."""
    max_dist = 1.5
    data = fetch_logs(max_dist)
    expected_data = get_expected_logs(max_dist)

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} logs, got {len(data)}"
    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert actual["timestamp"] == expected["timestamp"], f"Log {i} timestamp mismatch: expected {expected['timestamp']}, got {actual.get('timestamp')}"
        assert actual["ip"] == expected["ip"], f"Log {i} IP mismatch: expected {expected['ip']}, got {actual.get('ip')}"
        assert actual["action"] == expected["action"], f"Log {i} action mismatch: expected {expected['action']}, got {actual.get('action')}"
        assert abs(float(actual["distance"]) - expected["distance"]) < 0.01, f"Log {i} distance mismatch: expected {expected['distance']}, got {actual.get('distance')}"


def test_api_anomalies_endpoint_strict():
    """Retain and strengthen the original max_distance=0.1 check."""
    max_dist = 0.1
    data = fetch_logs(max_dist)
    expected_data = get_expected_logs(max_dist)

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} logs for max_distance={max_dist}, got {len(data)}"
    assert_logs_equal(data, expected_data, max_dist)


def test_api_anomalies_random_thresholds():
    """Exercise unpredictable thresholds in every distance interval."""
    rng = secrets.SystemRandom()
    with open("/home/user/logs.csv", "r") as f:
        distances = sorted({get_expected_distance(row["details"]) for row in csv.DictReader(f)})

    thresholds = []
    # Random values below the smallest and above the largest observed distance.
    thresholds.append(distances[0] - rng.uniform(0.01, 0.75))
    thresholds.append(distances[-1] + rng.uniform(0.01, 0.75))

    # Unpredictable values in every interval force all filtering boundaries.
    for lower, upper in zip(distances, distances[1:]):
        thresholds.append(rng.uniform(lower + (upper - lower) * 0.1,
                                      upper - (upper - lower) * 0.1))

    # Also exercise unpredictable values immediately above observed boundaries.
    for i, distance in enumerate(distances):
        next_distance = distances[i + 1] if i + 1 < len(distances) else distance + 1.0
        margin = min(0.005, (next_distance - distance) / 4.0)
        thresholds.append(distance + rng.uniform(margin / 4.0, margin))

    rng.shuffle(thresholds)
    for max_dist in thresholds:
        data = fetch_logs(max_dist)
        expected_data = get_expected_logs(max_dist)
        assert_logs_equal(data, expected_data, max_dist)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
