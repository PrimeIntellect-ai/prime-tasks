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

cat <<'TEST_EOF' > /tmp/test_final_state.py
import importlib.util
import json
import os
from pathlib import Path
import py_compile
import secrets
import sqlite3
import stat
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080/api/v1/records/USR-9942A"
TOKEN = "SEC-7719-XY"
SOURCE = Path("/home/user/api_server.py")
DATABASE = Path("/home/user/records.db")

ORIGINAL_BUGGY = """from flask import Flask, request, jsonify
import sqlite3

app = Flask(__name__)

@app.route('/api/v1/records/<user_id>', methods=['GET'])
def get_records(user_id):
    token = request.args.get('token')
    if token != 'SEC-7719-XY':
        return jsonify({'error': 'Unauthorized'}), 401

    payload = request.get_json(silent=True) or request.args

    # Convert string to bool if it comes from query args
    include_archived = payload.get('include_archived')
    if isinstance(include_archived, str):
        include_archived = include_archived.lower() == 'true'

    sort = payload.get('sort')

    query = "SELECT * FROM records"

    # Bug: wrong order of WHERE and ORDER BY
    if sort == 'desc':
        query += " ORDER BY id DESC"

    if include_archived:
        query += " WHERE archived=1"

    try:
        conn = sqlite3.connect('/home/user/records.db')
        cur = conn.cursor()
        cur.execute(query)
        rows = cur.fetchall()
        conn.close()
        return jsonify({'data': rows})
    except Exception as e:
        return jsonify({'error': str(e)}), 500

if __name__ == '__main__':
    app.run(host='127.0.0.1', port=8080)
""".encode()


def expected_rows(rows, payload):
    result = list(rows)
    include_archived = payload.get("include_archived")
    if isinstance(include_archived, str):
        include_archived = include_archived.lower() == "true"
    if include_archived:
        result = [row for row in result if row[1] == 1]
    if payload.get("sort") == "desc":
        result.sort(key=lambda row: row[0], reverse=True)
    else:
        result.sort(key=lambda row: row[0])
    return [list(row) for row in result]


@pytest.fixture(scope="module", autouse=True)
def randomized_database_and_server():
    backup = DATABASE.read_bytes()
    temporary = DATABASE.with_name("records.verifier.tmp.db")
    temporary.unlink(missing_ok=True)

    randomizer = secrets.SystemRandom()
    generated = []
    conn = sqlite3.connect(temporary)
    conn.execute("CREATE TABLE records (id INTEGER PRIMARY KEY, archived INTEGER, data TEXT)")
    for record_id in range(1, randomizer.randint(7, 12)):
        archived = record_id % 2
        data = "verify-" + secrets.token_hex(8)
        conn.execute(
            "INSERT INTO records (id, archived, data) VALUES (?, ?, ?)",
            (record_id, archived, data),
        )
        generated.append((record_id, archived, data))
    conn.commit()
    conn.close()
    os.replace(temporary, DATABASE)

    for _ in range(20):
        try:
            requests.get("http://127.0.0.1:8080/", timeout=1)
            break
        except requests.exceptions.ConnectionError:
            time.sleep(0.25)
    else:
        pytest.fail("API server is not running or not listening on 127.0.0.1:8080")

    yield generated

    restore = DATABASE.with_name("records.verifier.restore.db")
    restore.write_bytes(backup)
    os.replace(restore, DATABASE)


def assert_live_response(payload, rows):
    try:
        response = requests.get(
            BASE_URL,
            params={"token": TOKEN},
            json=payload,
            timeout=2,
        )
    except requests.exceptions.ConnectionError:
        pytest.fail("API server is not running or not listening on 127.0.0.1:8080")

    assert response.status_code != 500, f"Server returned 500 for payload {payload}"
    assert response.status_code == 200, (
        f"Expected status code 200 for payload {payload}, got {response.status_code}"
    )
    try:
        body = response.json()
    except ValueError:
        pytest.fail("Server did not return JSON")
    assert isinstance(body, dict) and body.get("data") == expected_rows(rows, payload), (
        f"Incorrect records for payload {payload}: {body}"
    )


def test_api_server_running_and_fixed_bug(randomized_database_and_server):
    assert_live_response(
        {"include_archived": True, "sort": "desc"},
        randomized_database_and_server,
    )


def test_api_server_full_payload(randomized_database_and_server):
    assert_live_response(
        {
            "include_archived": True,
            "sort": "desc",
            "limit": 100,
            "status": "pending",
        },
        randomized_database_and_server,
    )


def test_api_server_other_combinations(randomized_database_and_server):
    payloads = [
        {"include_archived": False, "sort": "desc"},
        {"include_archived": True, "sort": "asc"},
        {"limit": 10, "status": "approved"},
    ]
    for payload in payloads:
        assert_live_response(payload, randomized_database_and_server)


def test_query_parameters_and_authentication(randomized_database_and_server):
    response = requests.get(
        BASE_URL,
        params={"token": TOKEN, "include_archived": "true", "sort": "desc"},
        timeout=2,
    )
    assert response.status_code == 200
    assert response.json().get("data") == expected_rows(
        randomized_database_and_server,
        {"include_archived": "true", "sort": "desc"},
    )

    unauthorized = requests.get(BASE_URL, params={"token": "incorrect-token"}, timeout=2)
    assert unauthorized.status_code == 401


def test_fixed_artifact_exists_compiles_and_executes(randomized_database_and_server, tmp_path):
    assert SOURCE.exists(), "/home/user/api_server.py is missing"
    assert stat.S_ISREG(SOURCE.stat().st_mode), "/home/user/api_server.py is not a regular file"
    assert SOURCE.read_bytes() != ORIGINAL_BUGGY, "The buggy source file was not changed"
    py_compile.compile(str(SOURCE), cfile=str(tmp_path / "api_server.pyc"), doraise=True)

    module_name = "submitted_api_" + secrets.token_hex(6)
    spec = importlib.util.spec_from_file_location(module_name, SOURCE)
    assert spec is not None and spec.loader is not None
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert hasattr(module, "app") and hasattr(module.app, "test_client"), (
        "api_server.py does not define an executable Flask app"
    )

    payload = {"include_archived": True, "sort": "desc"}
    with module.app.test_client() as client:
        response = client.get(
            "/api/v1/records/USR-9942A",
            query_string={"token": TOKEN},
            json=payload,
        )
    assert response.status_code == 200
    body = response.get_json()
    assert isinstance(body, dict)
    assert body.get("data") == expected_rows(randomized_database_and_server, payload)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
