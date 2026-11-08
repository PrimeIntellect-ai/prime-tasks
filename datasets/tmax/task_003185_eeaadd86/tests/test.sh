#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import sqlite3
import subprocess
import time
import uuid

import pytest

QA_DIR = "/home/user/qa_env"
DB_FILE = os.path.join(QA_DIR, "test_db.sqlite")
RESULT_FILE = os.path.join(QA_DIR, "e2e_result.json")
SERVER_FILE = os.path.join(QA_DIR, "mock_server.py")
CLIENT_FILE = os.path.join(QA_DIR, "ws_client.py")

EXPECTED_SERVER = '''import asyncio
import websockets
import sqlite3
import json

async def handler(websocket, path):
    async for message in websocket:
        data = json.loads(message)
        if data.get("cmd") == "get_state":
            conn = sqlite3.connect('/home/user/qa_env/test_db.sqlite')
            conn.row_factory = sqlite3.Row
            cur = conn.cursor()
            cur.execute("SELECT * FROM state WHERE id = 1")
            row = cur.fetchone()
            conn.close()
            response = dict(row) if row else {}
            await websocket.send(json.dumps({"response": response}))

start_server = websockets.serve(handler, "127.0.0.1", 9999)
asyncio.get_event_loop().run_until_complete(start_server)
asyncio.get_event_loop().run_forever()
'''

EXPECTED_CLIENT = '''import asyncio
import websockets
import sys

async def send_msg(payload):
    async with websockets.connect("ws://127.0.0.1:9999") as websocket:
        await websocket.send(payload)
        response = await websocket.recv()
        print(response, end="")

if __name__ == "__main__":
    if len(sys.argv) > 1:
        asyncio.get_event_loop().run_until_complete(send_msg(sys.argv[1]))
'''


def test_database_migration_applied():
    assert os.path.isfile(DB_FILE), f"Database file {DB_FILE} is missing."

    conn = None
    try:
        conn = sqlite3.connect(DB_FILE)
        cursor = conn.cursor()

        cursor.execute("PRAGMA table_info(state)")
        columns = [col[1] for col in cursor.fetchall()]
        assert 'version' in columns, "Column 'version' was not added to the 'state' table. Migration was not applied correctly."

        cursor.execute("SELECT id, status, version FROM state WHERE id = 1")
        row = cursor.fetchone()
        assert row is not None, "Row with id=1 is missing from the 'state' table."
        assert row[0] == 1, "Row id is incorrect."
        assert row[1] == 'init', "Row status is incorrect."
        assert row[2] == 2, f"Row version is {row[2]}, expected 2. Migration data update was not applied correctly."
    except sqlite3.Error as e:
        pytest.fail(f"Database error while verifying migration: {e}")
    finally:
        if conn is not None:
            conn.close()


def test_e2e_result_file():
    assert os.path.isfile(RESULT_FILE), f"Result file {RESULT_FILE} is missing. Did you save the client output?"

    try:
        with open(RESULT_FILE, 'r') as f:
            content = f.read().strip()

        assert content, f"File {RESULT_FILE} is empty."

        try:
            data = json.loads(content)
        except json.JSONDecodeError:
            pytest.fail(f"Content of {RESULT_FILE} is not valid JSON. Found: {content}")

        expected_data = {"response": {"id": 1, "status": "init", "version": 2}}
        assert data == expected_data, f"JSON content in {RESULT_FILE} does not match expected output. Got: {data}"
    except IOError as e:
        pytest.fail(f"Failed to read {RESULT_FILE}: {e}")


def test_server_process_terminated():
    try:
        result = subprocess.run(["pgrep", "-f", "mock_server.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
        assert result.returncode != 0, "The mock_server.py process is still running. You must terminate the background server process to clean up."
    except Exception as e:
        pytest.fail(f"Failed to check for running processes: {e}")


def _run_client_when_ready(server, payload):
    deadline = time.monotonic() + 10
    last_error = ""
    while time.monotonic() < deadline:
        if server.poll() is not None:
            _, stderr = server.communicate(timeout=1)
            pytest.fail(f"mock_server.py exited before serving requests: {stderr}")
        try:
            result = subprocess.run(
                ["python3", CLIENT_FILE, payload],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=3,
            )
            if result.returncode == 0:
                return result.stdout
            last_error = result.stderr
        except subprocess.TimeoutExpired:
            last_error = "client invocation timed out"
        time.sleep(0.2)
    pytest.fail(f"WebSocket client could not connect to the server: {last_error}")


def test_real_websocket_server_and_provided_client_end_to_end():
    assert os.path.isfile(SERVER_FILE), f"Server script {SERVER_FILE} is missing."
    assert os.path.isfile(CLIENT_FILE), f"Client script {CLIENT_FILE} is missing."
    with open(SERVER_FILE, "r") as f:
        assert f.read() == EXPECTED_SERVER, "The provided mock_server.py script was modified."
    with open(CLIENT_FILE, "r") as f:
        assert f.read() == EXPECTED_CLIENT, "The provided ws_client.py script was modified."

    with open(RESULT_FILE, "r") as f:
        saved_stdout = f.read()

    original_row = None
    server = None
    try:
        conn = sqlite3.connect(DB_FILE)
        original_row = conn.execute("SELECT status, version FROM state WHERE id = 1").fetchone()
        conn.close()
        assert original_row is not None

        server = subprocess.Popen(
            ["python3", SERVER_FILE],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
        )

        payload = '{"cmd": "get_state"}'
        actual_stdout = _run_client_when_ready(server, payload)
        assert actual_stdout == saved_stdout, (
            "e2e_result.json is not the exact stdout produced by the provided client "
            "when connected to the provided server."
        )

        challenge_status = "verify-" + uuid.uuid4().hex
        challenge_version = 1000000 + int(uuid.uuid4().hex[:6], 16)
        conn = sqlite3.connect(DB_FILE)
        conn.execute(
            "UPDATE state SET status = ?, version = ? WHERE id = 1",
            (challenge_status, challenge_version),
        )
        conn.commit()
        conn.close()

        challenge_stdout = _run_client_when_ready(server, payload)
        challenge_expected = {
            "response": {
                "id": 1,
                "status": challenge_status,
                "version": challenge_version,
            }
        }
        assert json.loads(challenge_stdout) == challenge_expected, (
            "The live WebSocket server/client path did not broadcast the state "
            "derived from the challenged database row."
        )
    finally:
        if original_row is not None:
            conn = sqlite3.connect(DB_FILE)
            conn.execute(
                "UPDATE state SET status = ?, version = ? WHERE id = 1",
                original_row,
            )
            conn.commit()
            conn.close()
        if server is not None and server.poll() is None:
            server.terminate()
            try:
                server.wait(timeout=5)
            except subprocess.TimeoutExpired:
                server.kill()
                server.wait(timeout=5)

    result = subprocess.run(["pgrep", "-f", "mock_server.py"], stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    assert result.returncode != 0, "The verifier-started mock server was not cleaned up."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
