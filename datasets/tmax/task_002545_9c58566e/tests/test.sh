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
import collections
import csv
import io
import json
import os
import secrets
import sqlite3
import subprocess
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:5000"
DB_PATH = "/home/user/data.db"
SCORER_PATH = "/app/scorer_bin"


@pytest.fixture(scope="session", autouse=True)
def wait_for_server():
    """Wait for the server to be up before running tests."""
    max_retries = 10
    for _ in range(max_retries):
        try:
            requests.get(BASE_URL, timeout=1)
            return
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    pytest.fail("Server did not start on 127.0.0.1:5000")


def get_expected_embedding(description):
    """Run the binary to get the expected embedding for a description."""
    result = subprocess.run(
        [SCORER_PATH, description], capture_output=True, text=True, check=True
    )
    return [float(x) for x in result.stdout.strip().split()]


def test_upload_and_validation():
    csv_content = """id,category,description,metric
1,ALPHA,test description,4.5
2,DELTA,invalid category row,1.0
3,BETA,another valid row,0.0
4,GAMMA,negative metric,-1.2
5,GAMMA,valid again,10.1
"""
    files = {'file': ('test.csv', csv_content, 'text/csv')}
    response = requests.post(f"{BASE_URL}/upload", files=files, timeout=15)
    assert response.status_code == 200, f"Expected 200 OK for upload, got {response.status_code}. Response: {response.text}"


def test_get_valid_records():
    valid_records = [
        (1, "ALPHA", "test description", 4.5),
        (3, "BETA", "another valid row", 0.0),
        (5, "GAMMA", "valid again", 10.1)
    ]

    for rec_id, category, description, metric in valid_records:
        response = requests.get(f"{BASE_URL}/record/{rec_id}", timeout=5)
        assert response.status_code == 200, f"Expected 200 OK for record {rec_id}, got {response.status_code}"

        data = response.json()
        assert data.get("id") == rec_id, f"Expected id {rec_id}, got {data.get('id')}"
        assert data.get("category") == category, f"Expected category {category}, got {data.get('category')}"
        assert data.get("description") == description, f"Expected description '{description}', got {data.get('description')}"
        assert float(data.get("metric")) == metric, f"Expected metric {metric}, got {data.get('metric')}"

        expected_embedding = get_expected_embedding(description)
        actual_embedding = data.get("embedding")
        assert isinstance(actual_embedding, list) and len(actual_embedding) == 4, "Embedding must be a list of 4 floats"

        for exp, act in zip(expected_embedding, actual_embedding):
            assert abs(exp - float(act)) <= 0.0001, f"Embedding mismatch for record {rec_id}. Expected {expected_embedding}, got {actual_embedding}"


def test_get_invalid_records():
    invalid_ids = [2, 4]
    for rec_id in invalid_ids:
        response = requests.get(f"{BASE_URL}/record/{rec_id}", timeout=5)
        assert response.status_code == 404, f"Expected 404 Not Found for record {rec_id}, got {response.status_code}"


def test_database_state():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("PRAGMA table_info(records)")
    columns = {row[1]: row[2].upper() for row in cursor.fetchall()}

    expected_columns = {
        'id': 'INTEGER',
        'category': 'TEXT',
        'description': 'TEXT',
        'metric': 'REAL',
        'emb_0': 'REAL',
        'emb_1': 'REAL',
        'emb_2': 'REAL',
        'emb_3': 'REAL'
    }

    for col, col_type in expected_columns.items():
        assert col in columns, f"Column '{col}' missing from records table"
        assert col_type in columns[col], f"Column '{col}' has incorrect type. Expected {col_type}, got {columns[col]}"

    cursor.execute("SELECT COUNT(*) FROM records")
    count = cursor.fetchone()[0]
    assert count >= 3, f"Expected at least 3 records in database, got {count}"
    conn.close()


def _unused_id_block(size):
    for _ in range(100):
        base = secrets.randbelow(1_500_000_000) + 100_000_000
        with sqlite3.connect(DB_PATH) as conn:
            found = conn.execute(
                "SELECT COUNT(*) FROM records WHERE id BETWEEN ? AND ?",
                (base, base + size),
            ).fetchone()[0]
        if found == 0:
            return base
    pytest.fail("Could not allocate unused randomized record IDs")


def test_randomized_csv_processing_binary_execution_and_storage():
    base = _unused_id_block(20)
    token = uuid.uuid4().hex
    valid = [
        (base + 1, "ALPHA", f"random alpha {token}", 3.125),
        (base + 2, "BETA", f"quoted, comma {token}", 0.0),
        (base + 3, "GAMMA", f"random gamma {token}", 91.75),
    ]
    invalid = [
        (base + 4, "DELTA", f"bad category {token}", "1.0"),
        (base + 5, "ALPHA", "", "2.0"),
        (base + 6, "BETA", f"negative metric {token}", "-0.01"),
        (base + 7, "GAMMA", f"bad metric {token}", "not-a-float"),
        (base + 8, "ALPHA", f"nan metric {token}", "NaN"),
        (f"{base + 9}.0", "BETA", f"noninteger id {token}", "4.0"),
        ("not-an-integer", "GAMMA", f"text id {token}", "5.0"),
        (base + 10, "alpha", f"case category {token}", "6.0"),
    ]

    expected = {}
    for rec_id, _, description, _ in valid:
        expected[description] = [
            round((secrets.randbelow(8000) + 1000) / 10000.0, 4)
            for _ in range(4)
        ]

    output = io.StringIO(newline="")
    writer = csv.writer(output, lineterminator="\n")
    writer.writerow(["id", "category", "description", "metric"])
    writer.writerows(valid)
    writer.writerows(invalid)
    csv_content = output.getvalue()

    suffix = uuid.uuid4().hex
    backup_path = f"/app/.scorer_bin_backup_{suffix}"
    replacement_path = f"/app/.scorer_bin_test_{suffix}"
    log_path = f"/tmp/scorer_calls_{suffix}.jsonl"
    with open(log_path, "w", encoding="utf-8"):
        pass
    os.chmod(log_path, 0o666)

    mapping_json = json.dumps(expected)
    script = f'''#!/usr/bin/env python3
import json
import sys
mapping = json.loads({mapping_json!r})
with open({log_path!r}, "a", encoding="utf-8") as fh:
    fh.write(json.dumps(sys.argv[1:]) + "\\n")
if len(sys.argv) != 2 or sys.argv[1] not in mapping:
    sys.exit(2)
print(" ".join(format(x, ".4f") for x in mapping[sys.argv[1]]))
'''
    with open(replacement_path, "w", encoding="utf-8") as fh:
        fh.write(script)
    os.chmod(replacement_path, 0o755)

    response = None
    os.rename(SCORER_PATH, backup_path)
    os.rename(replacement_path, SCORER_PATH)
    try:
        response = requests.post(
            f"{BASE_URL}/upload",
            files={"file": (f"random-{token}.csv", csv_content, "text/csv")},
            timeout=20,
        )
    finally:
        if os.path.exists(SCORER_PATH):
            os.unlink(SCORER_PATH)
        os.rename(backup_path, SCORER_PATH)
        if os.path.exists(replacement_path):
            os.unlink(replacement_path)

    assert response is not None
    assert response.status_code == 200, response.text

    calls = []
    with open(log_path, encoding="utf-8") as fh:
        for line in fh:
            args = json.loads(line)
            assert len(args) == 1, f"scorer_bin must receive the description as one argument: {args}"
            calls.append(args[0])
    os.unlink(log_path)

    call_counts = collections.Counter(calls)
    for _, _, description, _ in valid:
        assert call_counts[description] >= 1, f"scorer_bin was not executed for valid row {description!r}"
    invalid_descriptions = {str(row[2]) for row in invalid}
    assert not (invalid_descriptions & set(calls)), "scorer_bin was executed for an invalid row"

    with sqlite3.connect(DB_PATH) as conn:
        for rec_id, category, description, metric in valid:
            row = conn.execute(
                "SELECT id, category, description, metric, emb_0, emb_1, emb_2, emb_3 FROM records WHERE id = ?",
                (rec_id,),
            ).fetchone()
            assert row is not None, f"Valid uploaded row {rec_id} was not stored"
            assert row[0] == rec_id
            assert row[1] == category
            assert row[2] == description
            assert float(row[3]) == metric
            for actual, wanted in zip(row[4:], expected[description]):
                assert abs(float(actual) - wanted) <= 0.0001

        for invalid_row in invalid:
            description = str(invalid_row[2])
            assert conn.execute(
                "SELECT COUNT(*) FROM records WHERE description = ?", (description,)
            ).fetchone()[0] == 0, f"Invalid row {description!r} was stored"

    for rec_id, category, description, metric in valid:
        response = requests.get(f"{BASE_URL}/record/{rec_id}", timeout=5)
        assert response.status_code == 200
        data = response.json()
        assert data.get("id") == rec_id
        assert data.get("category") == category
        assert data.get("description") == description
        assert float(data.get("metric")) == metric
        embedding = data.get("embedding")
        assert isinstance(embedding, list) and len(embedding) == 4
        for actual, wanted in zip(embedding, expected[description]):
            assert abs(float(actual) - wanted) <= 0.0001

    for rec_id in range(base + 4, base + 11):
        response = requests.get(f"{BASE_URL}/record/{rec_id}", timeout=5)
        assert response.status_code == 404
        assert response.json() == {"error": "Not found"}


def test_exact_database_schema_and_primary_key():
    with sqlite3.connect(DB_PATH) as conn:
        info = conn.execute("PRAGMA table_info(records)").fetchall()

    expected = [
        ("id", "INTEGER"),
        ("category", "TEXT"),
        ("description", "TEXT"),
        ("metric", "REAL"),
        ("emb_0", "REAL"),
        ("emb_1", "REAL"),
        ("emb_2", "REAL"),
        ("emb_3", "REAL"),
    ]
    assert [(row[1], row[2].upper()) for row in info] == expected
    primary_key_columns = [(row[1], row[5]) for row in info if row[5] != 0]
    assert primary_key_columns == [("id", 1)], "id must be the sole INTEGER PRIMARY KEY"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
