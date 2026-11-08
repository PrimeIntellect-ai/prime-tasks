#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import random
import secrets
import sqlite3
import time
import uuid

import pytest
import requests

URL = "http://127.0.0.1:8000/api/v1/ingest"
DB_PATH = "/home/user/logs.db"


def encode_log(log_str: str) -> str:
    """Encode a log using the oracle's XOR-and-hex format."""
    return bytes([b ^ 0x5C for b in log_str.encode("utf-8")]).hex()


def post_batch(batch_id, raw_logs, timeout):
    payload = {
        "batch_id": batch_id,
        "obfuscated_logs": [encode_log(log) for log in raw_logs],
    }
    try:
        return requests.post(URL, json=payload, timeout=timeout)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the ingestion service at {URL}: {exc}")


def read_batch(batch_id):
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"
    try:
        with sqlite3.connect(DB_PATH, timeout=10) as conn:
            return conn.execute(
                "SELECT timestamp, ip, severity, message "
                "FROM system_logs WHERE batch_id = ? ORDER BY timestamp ASC",
                (batch_id,),
            ).fetchall()
    except sqlite3.Error as exc:
        pytest.fail(f"Database error: {exc}")


def assert_success(response, expected_count):
    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    try:
        body = response.json()
    except (json.JSONDecodeError, ValueError):
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert body.get("status") == "success", (
        f"Expected status 'success', got {body.get('status')}"
    )
    assert body.get("processed_count") == expected_count, (
        f"Expected processed_count {expected_count}, got {body.get('processed_count')}"
    )


def test_ingest_endpoint_and_database():
    # Preserve the original fixed behavioral check.
    batch_id = str(uuid.uuid4())
    raw_logs = [
        "2023-10-01T12:00:00Z|192.168.001.001|warn|User login failed",
        "2023-10-01T12:00:01Z|010.000.000.002|error|Database connection lost",
        "2023-10-01T12:00:02Z|172.016.254.001|info|Service started successfully",
    ]
    expected_normalized = [
        ("2023-10-01T12:00:00Z", "192.168.1.1", "WARN", "User login failed"),
        ("2023-10-01T12:00:01Z", "10.0.0.2", "ERROR", "Database connection lost"),
        ("2023-10-01T12:00:02Z", "172.16.254.1", "INFO", "Service started successfully"),
    ]

    response = post_batch(batch_id, raw_logs, timeout=5)
    assert_success(response, len(raw_logs))
    rows = read_batch(batch_id)

    assert len(rows) == len(expected_normalized), (
        f"Expected {len(expected_normalized)} rows in DB for batch {batch_id}, "
        f"found {len(rows)}"
    )
    for row, expected in zip(rows, expected_normalized):
        assert row[0] == expected[0], f"Timestamp mismatch: expected {expected[0]}, got {row[0]}"
        assert row[1] == expected[1], f"IP mismatch: expected {expected[1]}, got {row[1]}"
        assert row[2] == expected[2], f"Severity mismatch: expected {expected[2]}, got {row[2]}"
        assert row[3] == expected[3], f"Message mismatch: expected {expected[3]}, got {row[3]}"

    try:
        with sqlite3.connect(DB_PATH) as conn:
            columns = {row[1]: row[2].upper() for row in conn.execute("PRAGMA table_info(system_logs)")}
    except sqlite3.Error as exc:
        pytest.fail(f"Database schema error: {exc}")
    for name in ("batch_id", "timestamp", "ip", "severity", "message"):
        assert columns.get(name) == "TEXT", f"Missing TEXT column system_logs.{name}"


def test_unpredictable_50000_record_bulk_batch():
    # The random seed and token are chosen only at verification time, so a service
    # cannot pass by inserting rows for the original three hardcoded examples.
    rng = random.Random(secrets.randbits(128))
    token = secrets.token_hex(12)
    severities = ["debug", "Warn", "ERROR", "iNfO", "critical"]
    count = 50000
    batch_id = str(uuid.uuid4())
    raw_logs = []
    expected = []

    for i in range(count):
        timestamp = f"2026-09-11T13:00:00.{i:06d}Z"
        octets = [rng.randrange(256) for _ in range(4)]
        encoded_ip = ".".join(f"{octet:03d}" for octet in octets)
        normalized_ip = ".".join(str(octet) for octet in octets)
        severity = rng.choice(severities)
        message = f"bulk-{token}-{i:05d}-{rng.getrandbits(48):012x}"
        raw_logs.append(f"{timestamp}|{encoded_ip}|{severity}|{message}")
        expected.append((timestamp, normalized_ip, severity.upper(), message))

    started = time.monotonic()
    response = post_batch(batch_id, raw_logs, timeout=(5, 35))
    elapsed = time.monotonic() - started

    assert_success(response, count)
    assert elapsed <= 30.0, (
        f"A 50,000-record bulk request took {elapsed:.2f}s; expected at most 30s"
    )

    rows = read_batch(batch_id)
    assert len(rows) == count, f"Expected {count} rows for batch {batch_id}, found {len(rows)}"
    assert rows == expected, "Bulk batch contained missing, reordered, or incorrectly normalized rows"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
