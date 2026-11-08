#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import sqlite3
import time

import pytest
import requests

API_URL = "http://127.0.0.1:8080"
HEADERS = {"Authorization": "Bearer secret_impute_token_99"}
RAW_PATH = "/app/raw_sensor_data.jsonl"
DB_PATH = "/app/cleaned_sensors.db"
EXPORT_PATH = "/app/export.csv"


def pristine_records():
    random.seed(42)
    records = []
    for i in range(1, 501):
        readings = []
        for _ in range(10):
            if random.random() < 0.2:
                readings.append(None)
            else:
                readings.append(round(random.uniform(10.0, 50.0), 2))
        records.append({
            "id": i,
            "messy_log": f"Log_entry #{i}! Error: {random.choice(['None', 'Temp', 'Press'])}.",
            "readings": readings,
        })
    return records


def oracle_semantics(readings):
    vals = [0.0 if value is None else float(value) for value in readings]
    missing = [value is None for value in readings]
    for i in range(len(vals)):
        if missing[i]:
            prev = i - 1
            while prev >= 0 and missing[prev]:
                prev -= 1
            nxt = i + 1
            while nxt < len(vals) and missing[nxt]:
                nxt += 1
            v1 = vals[prev] if prev >= 0 else 0.0
            v2 = vals[nxt] if nxt < len(vals) else 0.0
            if prev >= 0 and nxt < len(vals):
                vals[i] = (v1 + v2) / 2.0
            elif prev >= 0:
                vals[i] = v1
            elif nxt < len(vals):
                vals[i] = v2
    # The supplied binary prints every value using C's default %g precision.
    return [float(format(value, "g")) for value in vals]


def expected_records():
    result = {}
    for record in pristine_records():
        tokens = re.sub(r"[^a-z0-9 ]", "", record["messy_log"].lower()).split()
        result[record["id"]] = {
            "id": record["id"],
            "tokens": tokens,
            "readings": oracle_semantics(record["readings"]),
        }
    return result


EXPECTED = expected_records()


def assert_readings(actual, expected):
    assert isinstance(actual, list), "'readings' should be a list"
    assert len(actual) == len(expected), f"Expected {len(expected)} readings, got {len(actual)}"
    for index, (got, want) in enumerate(zip(actual, expected)):
        assert isinstance(got, (int, float)) and not isinstance(got, bool), f"Reading {index} is not numeric"
        assert got == pytest.approx(want, rel=1e-9, abs=1e-9), f"Incorrect reading at index {index}: {got} != {want}"


def assert_record(actual, expected):
    assert actual["id"] == expected["id"]
    assert actual["tokens"] == expected["tokens"]
    assert all(isinstance(token, str) for token in actual["tokens"])
    assert_readings(actual["readings"], expected["readings"])


def test_raw_source_is_intact():
    assert os.path.isfile(RAW_PATH), f"Raw dataset {RAW_PATH} is missing"
    with open(RAW_PATH, "r", encoding="utf-8") as handle:
        actual = [json.loads(line) for line in handle if line.strip()]
    assert actual == pristine_records(), "The supplied raw sensor dataset was modified"


def test_service_ready_log():
    log_path = "/app/service_ready.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist. Did you start the service and write 'READY'?"
    with open(log_path, "r") as f:
        content = f.read().strip()
    assert "READY" in content, f"Expected 'READY' in {log_path}, got: {content}"


def test_database_schema_and_all_cleaned_rows():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} does not exist"
    connection = sqlite3.connect(f"file:{DB_PATH}?mode=ro", uri=True)
    try:
        schema = connection.execute("PRAGMA table_info(sensor_data)").fetchall()
        assert schema, "Table sensor_data does not exist"
        assert [row[1] for row in schema] == ["id", "tokens", "readings"]
        assert schema[0][2].upper() == "INTEGER" and schema[0][5] == 1, "id must be an INTEGER PRIMARY KEY"
        assert schema[1][2].upper() == "TEXT", "tokens must be TEXT"
        assert schema[2][2].upper() == "TEXT", "readings must be TEXT"

        rows = connection.execute("SELECT id, tokens, readings FROM sensor_data ORDER BY id").fetchall()
        assert len(rows) == 500, f"Expected 500 imported records, got {len(rows)}"
        assert [row[0] for row in rows] == list(range(1, 501)), "Database IDs are incomplete or incorrect"
        for record_id, tokens_text, readings_text in rows:
            try:
                tokens = json.loads(tokens_text)
                readings = json.loads(readings_text)
            except (TypeError, json.JSONDecodeError) as exc:
                pytest.fail(f"Record {record_id} does not contain JSON-serialized TEXT values: {exc}")
            assert_record({"id": record_id, "tokens": tokens, "readings": readings}, EXPECTED[record_id])
    finally:
        connection.close()


def test_api_unauthorized():
    try:
        resp = requests.get(f"{API_URL}/api/record/1", timeout=2)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Failed to connect to API at {API_URL}: {e}")
    assert resp.status_code in (401, 403), f"Expected 401 or 403 for unauthorized request, got {resp.status_code}"

    wrong_headers = {"Authorization": "Bearer wrong_token"}
    resp = requests.get(f"{API_URL}/api/record/1", headers=wrong_headers, timeout=2)
    assert resp.status_code in (401, 403), f"Expected 401 or 403 for invalid token, got {resp.status_code}"

    resp = requests.post(f"{API_URL}/api/export", timeout=2)
    assert resp.status_code in (401, 403), f"Expected export to require authorization, got {resp.status_code}"


def test_api_get_record_success():
    resp = requests.get(f"{API_URL}/api/record/1", headers=HEADERS, timeout=2)
    assert resp.status_code == 200, f"Expected 200 OK for valid record, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert "id" in data, "Response JSON missing 'id'"
    assert "tokens" in data, "Response JSON missing 'tokens'"
    assert "readings" in data, "Response JSON missing 'readings'"
    assert data["id"] == 1, f"Expected id=1, got {data['id']}"
    assert isinstance(data["tokens"], list), "'tokens' should be a list"
    assert isinstance(data["readings"], list), "'readings' should be a list"
    assert set(data) == {"id", "tokens", "readings"}
    assert_record(data, EXPECTED[1])


def test_api_exposes_every_cleaned_record():
    session = requests.Session()
    for record_id in range(1, 501):
        resp = session.get(f"{API_URL}/api/record/{record_id}", headers=HEADERS, timeout=2)
        assert resp.status_code == 200, f"Expected 200 for record {record_id}, got {resp.status_code}"
        try:
            data = resp.json()
        except ValueError:
            pytest.fail(f"Response for record {record_id} is not valid JSON")
        assert set(data) == {"id", "tokens", "readings"}
        assert_record(data, EXPECTED[record_id])


def test_api_get_record_not_found():
    resp = requests.get(f"{API_URL}/api/record/9999", headers=HEADERS, timeout=2)
    assert resp.status_code == 404, f"Expected 404 for non-existent record, got {resp.status_code}"


def test_api_post_export():
    if os.path.exists(EXPORT_PATH):
        os.remove(EXPORT_PATH)

    resp = requests.post(f"{API_URL}/api/export", headers=HEADERS, timeout=5)
    assert resp.status_code == 200, f"Expected 200 OK for export, got {resp.status_code}"
    try:
        data = resp.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")
    assert data.get("status") == "success", f"Expected {{'status': 'success'}}, got {data}"

    for _ in range(10):
        if os.path.exists(EXPORT_PATH):
            break
        time.sleep(0.1)
    assert os.path.exists(EXPORT_PATH), f"Export file {EXPORT_PATH} was not created"
    assert os.path.getsize(EXPORT_PATH) > 0, f"Export file {EXPORT_PATH} is empty"

    with open(EXPORT_PATH, "r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle)
        assert reader.fieldnames == ["id", "tokens", "readings"], f"Incorrect CSV header: {reader.fieldnames}"
        rows = list(reader)
    assert len(rows) == 500, f"Expected 500 CSV data rows, got {len(rows)}"

    seen = set()
    for row in rows:
        try:
            record_id = int(row["id"])
            tokens = json.loads(row["tokens"])
            readings = json.loads(row["readings"])
        except (TypeError, ValueError, json.JSONDecodeError) as exc:
            pytest.fail(f"Invalid exported CSV row {row}: {exc}")
        assert record_id in EXPECTED, f"Unexpected exported ID {record_id}"
        assert record_id not in seen, f"Duplicate exported ID {record_id}"
        seen.add(record_id)
        assert_record({"id": record_id, "tokens": tokens, "readings": readings}, EXPECTED[record_id])
    assert seen == set(EXPECTED), "CSV export is missing database records"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
