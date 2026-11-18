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
import base64
import json
import os
import secrets
import socket
import sqlite3
import subprocess
import time

import pytest
import requests

BASE_URL = "http://127.0.0.1:8080"
DB_PATH = "/home/user/app/data.db"


def test_service_is_listening():
    """Ensure the student's HTTP service is up and listening on port 8080."""
    max_retries = 5
    for i in range(max_retries):
        try:
            requests.get(BASE_URL, timeout=2)
            break
        except requests.exceptions.ConnectionError:
            if i == max_retries - 1:
                pytest.fail(f"Could not connect to the service at {BASE_URL}. Is it running?")
            time.sleep(1)


def test_sync_endpoint():
    """Test that the /sync endpoint processes the WebSocket stream correctly."""
    try:
        response = requests.post(f"{BASE_URL}/sync", timeout=10)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request to /sync failed: {e}")

    assert response.status_code == 200, f"Expected status code 200 from /sync, got {response.status_code}. Response: {response.text}"
    try:
        json_data = response.json()
    except ValueError:
        pytest.fail(f"Response from /sync is not valid JSON: {response.text}")
    assert json_data.get("status") == "success", f"Expected {{'status': 'success'}} from /sync, got {json_data}"


def test_database_file_exists():
    """Ensure the SQLite database file was created at the correct path."""
    assert os.path.exists(DB_PATH), f"Database file not found at {DB_PATH}"
    assert os.path.isfile(DB_PATH), f"Path {DB_PATH} exists but is not a file"


def test_query_endpoint():
    """Retain the original fixed-stream assertion."""
    payload = {"query": "SELECT * FROM users ORDER BY id ASC"}
    try:
        response = requests.post(f"{BASE_URL}/query", json=payload, timeout=5)
    except requests.exceptions.RequestException as e:
        pytest.fail(f"Request to /query failed: {e}")

    assert response.status_code == 200, f"Expected status code 200 from /query, got {response.status_code}. Response: {response.text}"
    try:
        json_data = response.json()
    except ValueError:
        pytest.fail(f"Response from /query is not valid JSON: {response.text}")
    assert "results" in json_data, f"Expected key 'results' in /query response, got {json_data}"

    expected_results = [
        {"id": 1, "name": "Alice Smith", "email": "alice@example.com"},
        {"id": 2, "name": "Bob", "email": "bob@example.com"}
    ]
    actual_results = json_data["results"]
    assert actual_results == expected_results, f"Expected results {expected_results}, but got {actual_results}"


def _wait_for_file(path, proc, timeout=5):
    deadline = time.time() + timeout
    while time.time() < deadline:
        if os.path.exists(path):
            return
        if proc.poll() is not None:
            pytest.fail("Challenge WebSocket server exited before becoming ready")
        time.sleep(0.05)
    pytest.fail("Challenge WebSocket server did not become ready")


def _redis_json_values():
    scan = subprocess.run(["redis-cli", "--raw", "--scan"], capture_output=True, text=True, timeout=5)
    assert scan.returncode == 0, f"Could not inspect Redis: {scan.stderr}"
    values = []
    for key in scan.stdout.splitlines():
        got = subprocess.run(["redis-cli", "--raw", "GET", key], capture_output=True, text=True, timeout=5)
        if got.returncode != 0:
            continue
        try:
            values.append(json.loads(got.stdout.rstrip("\n")))
        except (TypeError, ValueError):
            pass
    return values


def test_randomized_websocket_sqlite_redis_and_queries():
    """Exercise a fresh, unpredictable stream and inspect the required backing systems."""
    token = secrets.token_hex(5)
    table = f"records_{token}"
    first_id = secrets.randbelow(500000) + 10000
    second_id = first_id + secrets.randbelow(1000) + 1
    initial_name = f"initial_{secrets.token_hex(4)}"
    final_name = f"updated_{secrets.token_hex(4)}"
    second_name = f"other_{secrets.token_hex(4)}"
    first_score = secrets.randbelow(500) + 20
    final_score = first_score + secrets.randbelow(100) + 1
    second_score = secrets.randbelow(500) + 20
    first_note = f"note_{secrets.token_hex(5)}"
    second_note = f"note_{secrets.token_hex(5)}"
    first_rank = secrets.randbelow(50) + 1
    second_rank = first_rank + secrets.randbelow(50) + 1

    messages = [
        {"type": "schema", "table": table, "columns": {"id": "int", "name": "string", "score": "int"}},
        {"type": "base_data", "table": table, "data": {"id": first_id, "name": initial_name, "score": first_score}},
        {"type": "patch", "table": table, "id": first_id, "patch": [
            {"op": "replace", "path": "/name", "value": final_name},
            {"op": "replace", "path": "/score", "value": final_score}
        ]},
        {"type": "schema_migration", "table": table, "changes": [
            {"op": "add_column", "name": "note", "datatype": "string"},
            {"op": "add_column", "name": "rank", "datatype": "int"}
        ]},
        {"type": "patch", "table": table, "id": first_id, "patch": [
            {"op": "add", "path": "/note", "value": first_note},
            {"op": "add", "path": "/rank", "value": first_rank}
        ]},
        {"type": "base_data", "table": table, "data": {"id": second_id, "name": second_name, "score": second_score}},
        {"type": "patch", "table": table, "id": second_id, "patch": [
            {"op": "add", "path": "/note", "value": second_note},
            {"op": "add", "path": "/rank", "value": second_rank}
        ]},
        {"type": "done"}
    ]

    expected_objects = [
        {"id": first_id, "name": final_name, "score": final_score, "note": first_note, "rank": first_rank},
        {"id": second_id, "name": second_name, "score": second_score, "note": second_note, "rank": second_rank}
    ]

    subprocess.run(["pkill", "-f", "/home/user/ws_server.py"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    time.sleep(0.3)

    server_code = r'''
import asyncio
import base64
import json
import os
import websockets

messages = json.loads(base64.b64decode(os.environ["CHALLENGE_MESSAGES"]).decode())
ready = os.environ["CHALLENGE_READY"]
marker = os.environ["CHALLENGE_MARKER"]

async def handler(ws, *args):
    path = args[0] if args else getattr(getattr(ws, "request", None), "path", None)
    if path is None:
        path = getattr(ws, "path", None)
    if path != "/stream":
        await ws.close()
        return
    with open(marker, "a") as f:
        f.write("connected\\n")
    for message in messages:
        await ws.send(json.dumps(message))
        await asyncio.sleep(0.02)
    with open(marker, "a") as f:
        f.write("done_sent\\n")

async def main():
    async with websockets.serve(handler, "127.0.0.1", 8081):
        with open(ready, "w") as f:
            f.write("ready")
        await asyncio.Future()

asyncio.run(main())
'''
    server_path = f"/tmp/challenge_ws_{token}.py"
    ready_path = f"/tmp/challenge_ready_{token}"
    marker_path = f"/tmp/challenge_marker_{token}"
    with open(server_path, "w") as f:
        f.write(server_code)
    env = os.environ.copy()
    env["CHALLENGE_MESSAGES"] = base64.b64encode(json.dumps(messages).encode()).decode()
    env["CHALLENGE_READY"] = ready_path
    env["CHALLENGE_MARKER"] = marker_path
    proc = subprocess.Popen(["python3", server_path], env=env, stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)

    try:
        _wait_for_file(ready_path, proc)
        response = requests.post(f"{BASE_URL}/sync", timeout=15)
        assert response.status_code == 200, response.text
        assert response.json().get("status") == "success", response.text

        assert os.path.exists(marker_path), "The service did not connect to the challenge WebSocket server"
        with open(marker_path) as f:
            marker = f.read()
        assert "connected" in marker and "done_sent" in marker, "The WebSocket stream was not consumed through done"

        with sqlite3.connect(DB_PATH) as db:
            schema = db.execute(f'PRAGMA table_info("{table}")').fetchall()
            assert [(r[1], r[2].upper(), r[5]) for r in schema] == [
                ("id", "INTEGER", 1),
                ("name", "TEXT", 0),
                ("score", "INTEGER", 0),
                ("note", "TEXT", 0),
                ("rank", "INTEGER", 0)
            ]
            rows = db.execute(f'SELECT id, name, score, note, rank FROM "{table}" ORDER BY id').fetchall()
            expected_rows = sorted([
                (first_id, final_name, final_score, first_note, first_rank),
                (second_id, second_name, second_score, second_note, second_rank)
            ])
            assert rows == expected_rows

            sentinel_table = f"verifier_{token}"
            sentinel_value = f"sentinel_{secrets.token_hex(6)}"
            db.execute(f'CREATE TABLE "{sentinel_table}" (value TEXT)')
            db.execute(f'INSERT INTO "{sentinel_table}" VALUES (?)', (sentinel_value,))
            db.commit()

        redis_values = _redis_json_values()
        for expected in expected_objects:
            assert expected in redis_values, f"Latest full row state was not found in Redis: {expected}"

        query = f'SELECT name, rank FROM "{table}" WHERE id = {first_id}'
        response = requests.post(f"{BASE_URL}/query", json={"query": query}, timeout=5)
        assert response.status_code == 200, response.text
        assert response.json() == {"results": [{"name": final_name, "rank": first_rank}]}

        aggregate = f'SELECT COUNT(*) AS row_count, SUM(score) AS total_score FROM "{table}"'
        response = requests.post(f"{BASE_URL}/query", json={"query": aggregate}, timeout=5)
        assert response.status_code == 200, response.text
        assert response.json() == {"results": [{"row_count": 2, "total_score": final_score + second_score}]}

        response = requests.post(
            f"{BASE_URL}/query",
            json={"query": f'SELECT value FROM "{sentinel_table}"'},
            timeout=5
        )
        assert response.status_code == 200, response.text
        assert response.json() == {"results": [{"value": sentinel_value}]}
    finally:
        proc.terminate()
        try:
            proc.wait(timeout=2)
        except subprocess.TimeoutExpired:
            proc.kill()

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
