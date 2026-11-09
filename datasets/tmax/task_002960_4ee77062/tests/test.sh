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
import glob
import json
import os
import re
import secrets
import sqlite3
import subprocess
import time

import pytest
import requests

DB_PATH = "/home/user/cleaned.db"
BASE_URL = "http://127.0.0.1:8080"
AUTH_TOKEN = "X9F2-K1M8"
TABLE_NAME = "active_users"
AUTH_HEADERS = {"Authorization": f"Bearer {AUTH_TOKEN}"}


def derive_configuration():
    text = subprocess.check_output(
        ["tesseract", "/app/schema_rules.png", "stdout"],
        text=True,
        stderr=subprocess.DEVNULL,
    )
    table_match = re.search(r"TABLE_NAME\s*:\s*([A-Za-z_][A-Za-z0-9_]*)", text, re.I)
    token_match = re.search(r"AUTH_TOKEN\s*:\s*([A-Za-z0-9-]+)", text, re.I)
    assert table_match, f"Could not OCR TABLE_NAME from image; OCR output was {text!r}"
    assert token_match, f"Could not OCR AUTH_TOKEN from image; OCR output was {text!r}"
    return table_match.group(1), token_match.group(1)


def derive_expected_rows():
    newest = {}
    with open("/app/dirty_data.jsonl", encoding="utf-8") as handle:
        for line in handle:
            record = json.loads(line)
            for key, value in list(record.items()):
                if isinstance(value, str):
                    record[key] = re.sub(
                        r"\\u([0-9a-fA-F]{4})",
                        lambda match: chr(int(match.group(1), 16)),
                        value,
                    )
            uid = int(record["user_id"])
            if uid not in newest or int(record["timestamp"]) > int(newest[uid]["timestamp"]):
                newest[uid] = record

    references = {}
    with open("/app/reference.csv", newline="", encoding="utf-8") as handle:
        for row in csv.DictReader(handle):
            references[int(row["user_id"])] = row

    expected = {}
    for uid, record in newest.items():
        if uid in references:
            expected[uid] = {
                "user_id": uid,
                "name": record["name"],
                "timestamp": int(record["timestamp"]),
                "status": references[uid]["status"],
                "score": int(references[uid]["score"]),
            }
    return expected


def request_user(user_id, headers=AUTH_HEADERS):
    try:
        return requests.get(f"{BASE_URL}/user/{user_id}", headers=headers, timeout=5)
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"Failed to connect to the HTTP server: {exc}")


def assert_record(data, expected):
    assert int(data.get("user_id", 0)) == expected["user_id"]
    assert data.get("name") == expected["name"]
    assert int(data.get("timestamp", 0)) == expected["timestamp"]
    assert data.get("status") == expected["status"]
    assert int(data.get("score", 0)) == expected["score"]


def listener_pid_and_executable():
    inodes = set()
    with open("/proc/net/tcp", encoding="ascii") as handle:
        next(handle)
        for line in handle:
            fields = line.split()
            local_address, state = fields[1], fields[3]
            if local_address.upper() == "0100007F:1F90" and state == "0A":
                inodes.add(fields[9])
    assert inodes, "No process is listening on 127.0.0.1:8080"

    for proc_dir in glob.glob("/proc/[0-9]*"):
        for fd in glob.glob(f"{proc_dir}/fd/*"):
            try:
                target = os.readlink(fd)
            except OSError:
                continue
            if any(target == f"socket:[{inode}]" for inode in inodes):
                pid = int(proc_dir.rsplit("/", 1)[1])
                return pid, os.path.realpath(f"/proc/{pid}/exe")
    pytest.fail("Could not identify the process listening on 127.0.0.1:8080")


def test_sqlite_db_exists():
    """Verify that the SQLite database file was created at the expected path."""
    assert os.path.exists(DB_PATH), f"SQLite database not found at {DB_PATH}"


def test_sqlite_table_exists():
    """Verify that the SQLite database contains the correct table name extracted via OCR."""
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name=?", (TABLE_NAME,))
    table = cursor.fetchone()
    conn.close()
    assert table is not None, f"Table '{TABLE_NAME}' not found in SQLite database. Ensure OCR extraction was successful."


def test_image_configuration_matches_required_values():
    table_name, auth_token = derive_configuration()
    assert table_name == TABLE_NAME
    assert auth_token == AUTH_TOKEN


def test_http_endpoint_auth_missing():
    """Verify that omitting the Authorization header results in a 401 Unauthorized."""
    response = request_user(1, headers={})
    assert response.status_code == 401, f"Expected 401 Unauthorized for missing auth, got {response.status_code}"


def test_http_endpoint_auth_wrong():
    """Verify that providing an incorrect Authorization header results in a 401 Unauthorized."""
    response = request_user(1, headers={"Authorization": "Bearer INVALID-TOKEN"})
    assert response.status_code == 401, f"Expected 401 Unauthorized for wrong auth, got {response.status_code}"


def test_http_endpoint_success_user_1():
    """Verify that user 1 data is correctly cleaned, deduplicated, joined, and returned."""
    response = request_user(1)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert int(data.get("user_id", 0)) == 1, f"Incorrect user_id: {data.get('user_id')}"
    assert data.get("name") == "José", f"Incorrect name (unicode cleaning failed), expected 'José', got {data.get('name')}"
    assert int(data.get("timestamp", 0)) == 200, f"Incorrect timestamp (deduplication failed), expected 200, got {data.get('timestamp')}"
    assert data.get("status") == "active", f"Incorrect status (join failed), expected 'active', got {data.get('status')}"
    assert int(data.get("score", 0)) == 99, f"Incorrect score (join failed), expected 99, got {data.get('score')}"


def test_http_endpoint_success_user_2():
    """Verify that user 2 data is correctly cleaned, joined, and returned."""
    response = request_user(2)
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Body: {response.text}"
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert int(data.get("user_id", 0)) == 2, f"Incorrect user_id: {data.get('user_id')}"
    assert data.get("name") == "Réne", f"Incorrect name (unicode cleaning failed), expected 'Réne', got {data.get('name')}"
    assert int(data.get("timestamp", 0)) == 150, f"Incorrect timestamp, expected 150, got {data.get('timestamp')}"
    assert data.get("status") == "inactive", f"Incorrect status (join failed), expected 'inactive', got {data.get('status')}"
    assert int(data.get("score", 0)) == 45, f"Incorrect score (join failed), expected 45, got {data.get('score')}"


def test_database_contains_complete_derived_pipeline_output():
    expected = derive_expected_rows()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    try:
        columns = [row[1] for row in conn.execute(f'PRAGMA table_info("{TABLE_NAME}")')]
        for required in ("user_id", "name", "timestamp", "status", "score"):
            assert required in columns, f"Missing required database column {required!r}"
        rows = conn.execute(
            f'SELECT user_id, name, timestamp, status, score FROM "{TABLE_NAME}"'
        ).fetchall()
    finally:
        conn.close()

    actual = {}
    for row in rows:
        uid = int(row["user_id"])
        assert uid not in actual, f"Duplicate database row for user_id {uid}"
        actual[uid] = {
            "user_id": uid,
            "name": row["name"],
            "timestamp": int(row["timestamp"]),
            "status": row["status"],
            "score": int(row["score"]),
        }
    assert actual == expected, f"Database rows do not equal the cleaned, deduplicated join: {actual!r}"


def test_all_derived_users_are_served_including_user_3():
    for uid, expected in derive_expected_rows().items():
        response = request_user(uid)
        assert response.status_code == 200, f"Expected user {uid} to return 200, got {response.status_code}: {response.text}"
        try:
            data = response.json()
        except ValueError:
            pytest.fail(f"Response for user {uid} is not valid JSON: {response.text}")
        assert_record(data, expected)


def test_endpoint_actually_queries_sqlite_for_general_user_ids():
    synthetic = {
        "user_id": 900000000 + secrets.randbelow(90000000),
        "name": f"Verifier-{secrets.token_hex(6)}-é",
        "timestamp": 700000000 + secrets.randbelow(10000000),
        "status": f"check-{secrets.token_hex(4)}",
        "score": 100000 + secrets.randbelow(100000),
    }
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            f'INSERT INTO "{TABLE_NAME}" (user_id, name, timestamp, status, score) VALUES (?, ?, ?, ?, ?)',
            (synthetic["user_id"], synthetic["name"], synthetic["timestamp"], synthetic["status"], synthetic["score"]),
        )
        conn.commit()
        response = request_user(synthetic["user_id"])
        assert response.status_code == 200, (
            "The endpoint did not serve a verifier-generated SQLite row; it may be returning hardcoded users. "
            f"Got {response.status_code}: {response.text}"
        )
        assert_record(response.json(), synthetic)

        unauthorized = request_user(synthetic["user_id"], headers={})
        assert unauthorized.status_code == 401
    finally:
        conn.execute(f'DELETE FROM "{TABLE_NAME}" WHERE user_id=?', (synthetic["user_id"],))
        conn.commit()
        conn.close()


def test_server_is_a_running_rust_binary():
    _, executable = listener_pid_and_executable()
    with open(executable, "rb") as handle:
        binary = handle.read()
    assert binary.startswith(b"\x7fELF"), f"Listening server is not a native executable: {executable}"
    rust_markers = (b"/rustc/", b"rust_eh_personality", b"library/std/src", b"library/core/src")
    assert any(marker in binary for marker in rust_markers), (
        f"The process listening on port 8080 does not appear to be a Rust executable: {executable}"
    )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
