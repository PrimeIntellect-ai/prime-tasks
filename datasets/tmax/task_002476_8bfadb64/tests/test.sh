#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import math
import secrets
import time
from collections import defaultdict
from datetime import datetime

import pytest
import requests

BASE_URL = "http://127.0.0.1:8282"
ALL_RECORDS = []
REGIONS = {
    "10.0.0.1": "APAC",
    "10.0.0.2": "EMEA",
    "10.0.0.3": "NORAM",
}


def wait_for_service(url, timeout=10):
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    return False


def post_records(payload):
    try:
        response = requests.post(f"{BASE_URL}/ingest", json=payload, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to POST /ingest: {exc}")
    assert response.status_code == 200, (
        f"Expected POST /ingest to return HTTP 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    ALL_RECORDS.extend(payload)


def get_anomalies():
    try:
        response = requests.get(f"{BASE_URL}/anomalies", timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to GET /anomalies: {exc}")
    assert response.status_code == 200, (
        f"Expected GET /anomalies to return HTTP 200, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except (json.JSONDecodeError, ValueError):
        pytest.fail(f"GET /anomalies did not return valid JSON. Response: {response.text}")
    assert isinstance(data, dict), f"Expected a JSON object, got: {data!r}"
    for region, timestamps in data.items():
        assert isinstance(region, str), f"Region keys must be strings, got: {region!r}"
        assert isinstance(timestamps, list), f"Anomalies for {region} must be a list"
        assert all(isinstance(ts, str) for ts in timestamps), (
            f"Anomaly timestamps for {region} must all be strings"
        )
    return data


def expected_anomalies(records):
    counts = defaultdict(lambda: defaultdict(int))
    for record in records:
        region = REGIONS.get(record["ip"], "UNKNOWN")
        minute = datetime.fromisoformat(record["timestamp"]).strftime("%Y-%m-%dT%H:%M:00")
        # A minute containing only non-international logs is still an available window.
        counts[region][minute] += 0
        message = record["message"]
        non_ascii = sum(ord(char) > 127 for char in message)
        ascii_chars = len(message) - non_ascii
        if non_ascii > ascii_chars:
            counts[region][minute] += 1

    result = {}
    for region, windows in counts.items():
        values = list(windows.values())
        mean = sum(values) / len(values)
        variance = sum((value - mean) ** 2 for value in values) / len(values)
        sigma = math.sqrt(variance)
        anomalies = [] if sigma == 0 else sorted(
            minute for minute, value in windows.items()
            if value > mean + 2.0 * sigma
        )
        if anomalies:
            result[region] = anomalies
    return result


def test_service_ingest_and_anomalies():
    assert wait_for_service(f"{BASE_URL}/anomalies"), (
        f"Service at {BASE_URL} is not reachable after 10 seconds. "
        "Is it listening on port 8282?"
    )

    # Preserve the original fixed scenario and its assertions.
    payload = []
    for i in range(9):
        payload.append({
            "timestamp": f"2023-10-01T10:0{i}:15",
            "ip": "10.0.0.1",
            "message": "こんにちは世界",
        })
        payload.append({
            "timestamp": f"2023-10-01T10:0{i}:30",
            "ip": "10.0.0.1",
            "message": "hello world",
        })
    for j in range(20):
        payload.append({
            "timestamp": f"2023-10-01T10:09:{j:02d}",
            "ip": "10.0.0.1",
            "message": "こんにちは世界",
        })
    for i in range(10):
        payload.append({
            "timestamp": f"2023-10-01T10:0{i}:15",
            "ip": "10.0.0.2",
            "message": "こんにちは世界",
        })

    post_records(payload)
    anomalies_data = get_anomalies()
    assert "APAC" in anomalies_data, (
        f"Expected 'APAC' in anomalies response, got keys: {list(anomalies_data.keys())}"
    )
    assert "2023-10-01T10:09:00" in anomalies_data["APAC"], (
        "Expected anomaly at '2023-10-01T10:09:00' for APAC, "
        f"got: {anomalies_data['APAC']}"
    )
    if "EMEA" in anomalies_data:
        assert len(anomalies_data["EMEA"]) == 0, (
            f"Expected no anomalies for EMEA, got: {anomalies_data['EMEA']}"
        )

    # Exercise all metadata joins, UNKNOWN fallback, minute aggregation, strict
    # Unicode comparison, persistence across ingests, and the configured threshold
    # at unpredictable timestamps.
    year = 2040 + secrets.randbelow(40)
    month = 1 + secrets.randbelow(12)
    hour = secrets.randbelow(20)
    cases = [
        ("10.0.0.1", "APAC", 1),
        ("10.0.0.2", "EMEA", 2),
        ("10.0.0.3", "NORAM", 3),
        (f"198.51.100.{10 + secrets.randbelow(200)}", "UNKNOWN", 4),
    ]
    randomized_payload = []

    for ip, _region, day in cases:
        for minute in range(10):
            timestamp_prefix = f"{year:04d}-{month:02d}-{day:02d}T{hour:02d}:{minute:02d}"
            true_count = 20 if minute == 9 else 1
            for second in range(true_count):
                randomized_payload.append({
                    "timestamp": f"{timestamp_prefix}:{second:02d}",
                    "ip": ip,
                    # Two non-ASCII characters and one ASCII character: true.
                    "message": "ééa",
                })

            randomized_payload.append({
                "timestamp": f"{timestamp_prefix}:45",
                "ip": ip,
                "message": "plain ASCII",
            })

            # Equality must be false. Concentrating these in a normal minute makes
            # an implementation using >= produce a different anomaly timestamp.
            if minute == 4:
                for second in range(20, 50):
                    randomized_payload.append({
                        "timestamp": f"{timestamp_prefix}:{second:02d}",
                        "ip": ip,
                        "message": "éa",
                    })

    post_records(randomized_payload)
    actual = get_anomalies()
    expected = expected_anomalies(ALL_RECORDS)

    # Empty region lists are permitted, but every reported anomaly and every
    # expected anomalous region/timestamp must otherwise match exactly.
    normalized_actual = {
        region: sorted(timestamps)
        for region, timestamps in actual.items()
        if timestamps
    }
    assert normalized_actual == expected, (
        f"Incorrect anomaly result. Expected {expected}, got {actual}"
    )


if __name__ == "__main__":
    raise SystemExit(pytest.main([__file__, "-x", "--tb=short"]))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
