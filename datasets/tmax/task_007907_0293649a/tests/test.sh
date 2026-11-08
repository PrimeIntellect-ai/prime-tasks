#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import hashlib
import json
import os
from pathlib import Path
import random
import secrets
import sqlite3
import subprocess
import uuid

DB_PATH = '/home/user/logs/anomalies.db'
RAW_PATH = '/home/user/logs/raw_requests.jsonl'


def test_database_exists():
    assert os.path.exists(DB_PATH), f"The database file {DB_PATH} was not found."
    assert os.path.isfile(DB_PATH), f"The path {DB_PATH} is not a file."


def test_database_schema_and_contents():
    assert os.path.exists(DB_PATH), f"Cannot check contents, {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='flagged_logs';")
    table_exists = cursor.fetchone()
    assert table_exists is not None, "The table 'flagged_logs' does not exist in the database."

    cursor.execute("SELECT timestamp, endpoint, status_code, response_time_ms, rolling_avg FROM flagged_logs ORDER BY timestamp;")
    rows = cursor.fetchall()

    assert len(rows) == 2, f"Expected exactly 2 anomalous records in the database, but found {len(rows)}."

    row1 = rows[0]
    assert row1[0] == 107, f"Expected timestamp 107 for the first anomaly, got {row1[0]}."
    assert row1[1] == "/api/v1/users", f"Expected endpoint '/api/v1/users' for the first anomaly, got {row1[1]}."
    assert row1[2] == 500, f"Expected status_code 500 for the first anomaly, got {row1[2]}."
    assert float(row1[3]) == 150.0, f"Expected response_time_ms 150.0 for the first anomaly, got {row1[3]}."
    assert abs(float(row1[4]) - 71.2) < 0.01, f"Expected rolling_avg ~71.20 for the first anomaly, got {row1[4]}."

    row2 = rows[1]
    assert row2[0] == 203, f"Expected timestamp 203 for the second anomaly, got {row2[0]}."
    assert row2[1] == "/api/v2/items", f"Expected endpoint '/api/v2/items' for the second anomaly, got {row2[1]}."
    assert row2[2] == 503, f"Expected status_code 503 for the second anomaly, got {row2[2]}."
    assert float(row2[3]) == 40.0, f"Expected response_time_ms 40.0 for the second anomaly, got {row2[3]}."
    assert abs(float(row2[4]) - 20.67) < 0.01, f"Expected rolling_avg ~20.67 for the second anomaly, got {row2[4]}."

    conn.close()


def make_dynamic_fixture():
    token = uuid.uuid4().hex
    endpoint_a = f"/dynamic/{token}/alpha"
    endpoint_b = f"/dynamic/{token}/beta"
    base = secrets.randbelow(500000) + 10000
    scale_a = secrets.randbelow(7) + 2
    scale_b = secrets.randbelow(7) + 2

    def rec(offset, endpoint, status, latency, payload):
        return {
            "timestamp": base + offset,
            "endpoint": endpoint,
            "status_code": status,
            "response_time_ms": latency,
            "request_payload": f"{token}:{payload}",
        }

    records = [
        rec(10, endpoint_a, 200, 10 * scale_a, "a1"),
        rec(20, endpoint_a, 201, 12 * scale_a, "a2"),
        rec(30, endpoint_a, 400, 11 * scale_a, "a3"),
        rec(40, endpoint_a, 401, 13 * scale_a, "a4"),
        rec(50, endpoint_a, 403, 14 * scale_a, "a5"),
        rec(60, endpoint_a, 500, 60 * scale_a, "a6"),
        rec(70, endpoint_a, 200, 15 * scale_a, "a7"),
        # Later duplicate of a2; it must not replace or supplement the earliest row.
        rec(80, endpoint_a, 502, 900 * scale_a, "a2"),
        rec(15, endpoint_b, 200, 16 * scale_b, "b1"),
        rec(25, endpoint_b, 201, 17 * scale_b, "b2"),
        rec(35, endpoint_b, 404, 18 * scale_b, "b3"),
        rec(45, endpoint_b, 502, 19 * scale_b, "b4"),
        # Exactly 1.5 times its five-row average, so strict comparison must not flag it.
        rec(55, endpoint_b, 503, 30 * scale_b, "b5"),
        rec(65, endpoint_b, 503, 80 * scale_b, "b6"),
        rec(32, endpoint_a, 999, 10000, "invalid-status-value"),
        rec(33, endpoint_a, 200.0, 10000, "invalid-status-type"),
        rec(34, endpoint_a, 200, 0, "invalid-zero-time"),
        rec(36, endpoint_b, 200, -5, "invalid-negative-time"),
        rec(37, endpoint_b, 200, "500", "invalid-time-type"),
    ]
    invalid_timestamp = rec(38, endpoint_b, 200, 10000, "invalid-timestamp")
    invalid_timestamp["timestamp"] = str(base + 38)
    records.append(invalid_timestamp)

    random.SystemRandom().shuffle(records)
    return records


def derive_expected(records):
    deduplicated = {}
    for row in records:
        digest = hashlib.md5(row["request_payload"].encode()).hexdigest()
        previous = deduplicated.get(digest)
        if previous is None:
            deduplicated[digest] = row
        elif isinstance(row.get("timestamp"), int) and isinstance(previous.get("timestamp"), int):
            if row["timestamp"] < previous["timestamp"]:
                deduplicated[digest] = row

    allowed = {200, 201, 400, 401, 403, 404, 500, 502, 503}
    valid = []
    for row in deduplicated.values():
        status = row.get("status_code")
        latency = row.get("response_time_ms")
        timestamp = row.get("timestamp")
        if type(status) is not int or status not in allowed:
            continue
        if type(timestamp) is not int:
            continue
        if type(latency) not in (int, float) or isinstance(latency, bool) or latency <= 0:
            continue
        valid.append(row)

    groups = {}
    for row in valid:
        groups.setdefault(row["endpoint"], []).append(row)

    expected = []
    for endpoint, group in groups.items():
        group.sort(key=lambda row: row["timestamp"])
        history = []
        for row in group:
            history.append(float(row["response_time_ms"]))
            rolling = sum(history[-5:]) / len(history[-5:])
            if float(row["response_time_ms"]) > 1.5 * rolling:
                expected.append((
                    row["timestamp"], endpoint, row["status_code"],
                    float(row["response_time_ms"]), round(rolling, 2)
                ))
    return sorted(expected, key=lambda row: row[0])


def write_fixture(records):
    os.makedirs(os.path.dirname(RAW_PATH), exist_ok=True)
    with open(RAW_PATH, 'w', encoding='utf-8') as handle:
        for row in records:
            handle.write(json.dumps(row) + '\n')
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)


def validate_dynamic_database(expected):
    if not os.path.isfile(DB_PATH):
        return "anomalies.db was not created"
    try:
        conn = sqlite3.connect(DB_PATH)
        cur = conn.cursor()
        cur.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='flagged_logs'")
        if cur.fetchone() is None:
            return "flagged_logs table was not created"
        cur.execute("PRAGMA table_info(flagged_logs)")
        schema = [(row[1], row[2].upper()) for row in cur.fetchall()]
        required = [
            ("timestamp", "INTEGER"), ("endpoint", "TEXT"),
            ("status_code", "INTEGER"), ("response_time_ms", "REAL"),
            ("rolling_avg", "REAL"),
        ]
        if schema != required:
            return f"incorrect schema: {schema!r}"
        cur.execute("SELECT timestamp, endpoint, status_code, response_time_ms, rolling_avg FROM flagged_logs ORDER BY timestamp")
        actual = cur.fetchall()
        conn.close()
    except Exception as exc:
        return f"could not read output database: {exc}"

    if len(actual) != len(expected):
        return f"expected {len(expected)} dynamic anomalies, found {len(actual)}: {actual!r}"
    for got, want in zip(actual, expected):
        if got[:3] != want[:3]:
            return f"incorrect dynamic row: got {got!r}, expected {want!r}"
        if abs(float(got[3]) - want[3]) > 1e-9:
            return f"incorrect response time: got {got[3]!r}, expected {want[3]!r}"
        if abs(float(got[4]) - want[4]) >= 0.005:
            return f"incorrect rounded rolling average: got {got[4]!r}, expected {want[4]!r}"
    return None


def test_zz_pipeline_runs_on_changed_input():
    candidates = []
    for path in Path('/home/user').rglob('*.py'):
        if path.is_file() and '__pycache__' not in path.parts:
            candidates.append(path)
    assert candidates, "No Python pipeline artifact was found under /home/user."

    records = make_dynamic_fixture()
    expected = derive_expected(records)
    assert len(expected) == 2, "Internal dynamic fixture error."
    failures = []

    for candidate in sorted(candidates):
        write_fixture(records)
        try:
            result = subprocess.run(
                ['python3', str(candidate)],
                cwd=str(candidate.parent),
                stdout=subprocess.PIPE,
                stderr=subprocess.STDOUT,
                text=True,
                timeout=20,
            )
        except Exception as exc:
            failures.append(f"{candidate}: execution failed: {exc}")
            continue
        if result.returncode != 0:
            failures.append(f"{candidate}: exited {result.returncode}: {result.stdout[-300:]}")
            continue
        problem = validate_dynamic_database(expected)
        if problem is None:
            return
        failures.append(f"{candidate}: {problem}")

    raise AssertionError(
        "No submitted Python pipeline correctly processed a changed input. "
        + " | ".join(failures[-8:])
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
