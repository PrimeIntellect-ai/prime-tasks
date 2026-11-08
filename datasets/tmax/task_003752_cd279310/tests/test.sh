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
import json
import os
import random
import socket
import subprocess
import time
import uuid
from datetime import datetime, timedelta, timezone

import pytest
import redis
import requests

INGEST_URL = "http://localhost:8080/ingest"
METRICS_URL = "http://localhost:8080/metrics"


def wait_for_http(url, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            requests.get(url, timeout=1)
            return True
        except requests.exceptions.RequestException:
            time.sleep(0.25)
    return False


def wait_for_port(port, timeout=8):
    deadline = time.time() + timeout
    while time.time() < deadline:
        try:
            with socket.create_connection(("127.0.0.1", port), timeout=1):
                return True
        except OSError:
            time.sleep(0.25)
    return False


def redis_client():
    client = redis.Redis(host="localhost", port=6379, db=0, socket_timeout=2)
    assert client.ping() is True, "Redis is not responding to PING on port 6379"
    return client


def post_json_lines(objects):
    payload = "\n".join(json.dumps(obj, ensure_ascii=True) for obj in objects)
    response = requests.post(
        INGEST_URL,
        data=payload.encode("utf-8"),
        headers={"Content-Type": "application/json"},
        timeout=5,
    )
    assert response.status_code in (200, 201, 202, 204), (
        f"POST /ingest failed with status {response.status_code}: {response.text}"
    )


def iso_minute(value):
    return value.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:00Z")


def test_01_original_system_behavior():
    assert wait_for_http("http://localhost:8080/"), "Nginx/App is not reachable on port 8080"
    assert wait_for_port(5000), "Python backend is not listening on port 5000"
    assert wait_for_port(6379), "Redis is not listening on port 6379"
    assert subprocess.run(["pgrep", "-x", "nginx"], stdout=subprocess.DEVNULL).returncode == 0, "Nginx is not running"
    assert subprocess.run(
        ["nginx", "-t", "-c", "/app/nginx/nginx.conf"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    ).returncode == 0, "/app/nginx/nginx.conf is not a valid Nginx configuration"

    r = redis_client()
    r.flushall()

    payload = (
        '{"timestamp": "2023-10-01T12:00:00Z", "data": "{\\"key\\": \\"val1\\"}"}\n'
        '{"timestamp": "2023-10-01T12:00:30Z", "data": "{\\"key\\": \\"val1\\"}"}\n'
        '{"timestamp": "2023-10-01T12:01:15Z", "data": "{\\"key\\": \\"m\\u00fcsta\\u00f1\\"}"}\n'
        '{"timestamp": "2023-10-01T12:04:45Z", "data": "{\\"key\\": \\"val3\\"}"}'
    )

    try:
        post_resp = requests.post(
            INGEST_URL,
            data=payload.encode("utf-8"),
            headers={"Content-Type": "application/json"},
            timeout=5,
        )
        assert post_resp.status_code in (200, 201, 202, 204), f"POST /ingest failed with status {post_resp.status_code}: {post_resp.text}"
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"POST /ingest request failed: {exc}")

    params = {"start": "2023-10-01T11:58:00Z", "end": "2023-10-01T12:05:00Z"}
    try:
        get_resp = requests.get(METRICS_URL, params=params, timeout=5)
        assert get_resp.status_code == 200, f"GET /metrics failed with status {get_resp.status_code}: {get_resp.text}"
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"GET /metrics request failed: {exc}")

    try:
        data = get_resp.json()
    except ValueError:
        pytest.fail(f"GET /metrics did not return valid JSON. Response text: {get_resp.text}")

    expected_data = [
        {"minute": "2023-10-01T11:58:00Z", "changes": 0, "rolling_5m_count": 0},
        {"minute": "2023-10-01T11:59:00Z", "changes": 0, "rolling_5m_count": 0},
        {"minute": "2023-10-01T12:00:00Z", "changes": 1, "rolling_5m_count": 1},
        {"minute": "2023-10-01T12:01:00Z", "changes": 1, "rolling_5m_count": 2},
        {"minute": "2023-10-01T12:02:00Z", "changes": 0, "rolling_5m_count": 2},
        {"minute": "2023-10-01T12:03:00Z", "changes": 0, "rolling_5m_count": 2},
        {"minute": "2023-10-01T12:04:00Z", "changes": 1, "rolling_5m_count": 3},
        {"minute": "2023-10-01T12:05:00Z", "changes": 0, "rolling_5m_count": 2},
    ]

    assert isinstance(data, list), f"Expected response to be a list, got {type(data)}"
    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(data)}. Data: {data}"
    for index, expected_item in enumerate(expected_data):
        actual_item = data[index]
        assert actual_item.get("minute") == expected_item["minute"], f"Mismatch at index {index}: expected minute {expected_item['minute']}, got {actual_item.get('minute')}"
        assert actual_item.get("changes") == expected_item["changes"], f"Mismatch at index {index} ({expected_item['minute']}): expected changes {expected_item['changes']}, got {actual_item.get('changes')}"
        assert actual_item.get("rolling_5m_count") == expected_item["rolling_5m_count"], f"Mismatch at index {index} ({expected_item['minute']}): expected rolling_5m_count {expected_item['rolling_5m_count']}, got {actual_item.get('rolling_5m_count')}"


def test_02_randomized_bucketing_deduplication_and_redis_storage():
    r = redis_client()
    r.flushall()

    nonce = uuid.uuid4().hex
    base = datetime(
        random.randint(2035, 2045),
        random.randint(1, 12),
        random.randint(1, 20),
        random.randint(1, 20),
        random.randint(0, 59),
        tzinfo=timezone.utc,
    ).replace(second=0, microsecond=0)

    value_a = f'{nonce}:alpha'
    value_unicode = f'{nonce}:Grüße-東京-ñ'
    value_b = f'{nonce}:beta'
    value_c = f'{nonce}:gamma'
    value_d = f'{nonce}:delta'

    batches = [
        [
            {"timestamp": (base + timedelta(seconds=2)).isoformat().replace("+00:00", "Z"), "data": value_a},
            {"timestamp": (base + timedelta(seconds=48)).isoformat().replace("+00:00", "Z"), "data": value_a},
            {"timestamp": (base + timedelta(minutes=1, seconds=7)).isoformat().replace("+00:00", "Z"), "data": value_a},
            {"timestamp": (base + timedelta(minutes=1, seconds=19)).isoformat().replace("+00:00", "Z"), "data": value_unicode},
            {"timestamp": (base + timedelta(minutes=3, seconds=4)).isoformat().replace("+00:00", "Z"), "data": value_b},
        ],
        [
            {"timestamp": (base + timedelta(minutes=1, seconds=51)).isoformat().replace("+00:00", "Z"), "data": value_unicode},
            {"timestamp": (base + timedelta(minutes=3, seconds=37)).isoformat().replace("+00:00", "Z"), "data": value_c},
            {"timestamp": (base + timedelta(minutes=7, seconds=22)).isoformat().replace("+00:00", "Z"), "data": value_d},
            {"timestamp": (base + timedelta(minutes=7, seconds=55)).isoformat().replace("+00:00", "Z"), "data": value_d},
        ],
    ]

    expected_sets = {}
    for batch in batches:
        post_json_lines(batch)
        for event in batch:
            timestamp = datetime.fromisoformat(event["timestamp"].replace("Z", "+00:00"))
            minute = timestamp.replace(second=0, microsecond=0)
            expected_sets.setdefault(minute, set()).add(event["data"])

    total_redis_keys = 0
    configured_dbs = int(r.config_get("databases").get("databases", 16))
    for db_number in range(configured_dbs):
        total_redis_keys += redis.Redis(host="localhost", port=6379, db=db_number, socket_timeout=2).dbsize()
    assert total_redis_keys > 0, "Ingest did not store any state in Redis"

    start = base - timedelta(minutes=3)
    end = base + timedelta(minutes=10)
    response = requests.get(
        METRICS_URL,
        params={"start": iso_minute(start), "end": iso_minute(end)},
        timeout=5,
    )
    assert response.status_code == 200, f"GET /metrics failed with status {response.status_code}: {response.text}"
    try:
        actual = response.json()
    except ValueError:
        pytest.fail(f"GET /metrics did not return valid JSON: {response.text}")

    expected = []
    minute = start
    while minute <= end:
        changes = len(expected_sets.get(minute, set()))
        rolling = sum(
            len(expected_sets.get(minute - timedelta(minutes=offset), set()))
            for offset in range(5)
        )
        expected.append({"minute": iso_minute(minute), "changes": changes, "rolling_5m_count": rolling})
        minute += timedelta(minutes=1)

    assert isinstance(actual, list), f"Expected response to be a list, got {type(actual)}"
    assert len(actual) == len(expected), f"Expected every inclusive minute ({len(expected)} rows), got {len(actual)}: {actual}"
    for index, expected_item in enumerate(expected):
        assert isinstance(actual[index], dict), f"Metrics row {index} is not an object: {actual[index]}"
        assert actual[index].get("minute") == expected_item["minute"], f"Wrong minute at row {index}: {actual[index]}"
        assert actual[index].get("changes") == expected_item["changes"], f"Wrong deduplicated count at {expected_item['minute']}: {actual[index]}"
        assert actual[index].get("rolling_5m_count") == expected_item["rolling_5m_count"], f"Wrong rolling count at {expected_item['minute']}: {actual[index]}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
