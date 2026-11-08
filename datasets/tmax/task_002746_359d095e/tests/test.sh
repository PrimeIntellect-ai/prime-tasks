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
mkdir -p /logs/verifier
reward=0
trap 'printf "%s\n" "$reward" > /logs/verifier/reward.txt' EXIT

SERVER_DIR=/home/user/app/server
SERVER_BIN="$SERVER_DIR/server"

# Rebuild the submitted source so the tested service is necessarily the requested C++ artifact.
if ! (cd "$SERVER_DIR" && g++ -std=c++17 main.cpp -lsqlite3 -lpthread -o server); then
    exit 0
fi

# Stop anything currently listening on port 8080 before launching the freshly built binary.
python3 - <<'PY'
import os
import signal

inodes = set()
for table in ("/proc/net/tcp", "/proc/net/tcp6"):
    try:
        with open(table) as f:
            next(f, None)
            for line in f:
                fields = line.split()
                if len(fields) > 9 and fields[1].rsplit(":", 1)[-1].upper() == "1F90" and fields[3] == "0A":
                    inodes.add(fields[9])
    except OSError:
        pass

for entry in os.listdir("/proc"):
    if not entry.isdigit() or int(entry) == os.getpid():
        continue
    fd_dir = f"/proc/{entry}/fd"
    try:
        for fd in os.listdir(fd_dir):
            try:
                target = os.readlink(f"{fd_dir}/{fd}")
            except OSError:
                continue
            if target.startswith("socket:[") and target[8:-1] in inodes:
                os.kill(int(entry), signal.SIGTERM)
                break
    except OSError:
        pass
PY
sleep 1

(cd "$SERVER_DIR" && nohup ./server >/tmp/verifier_server.log 2>&1 &)

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess
import time

import pytest
import requests

DB_PATH = "/home/user/app/data/research.db"
SOURCE_PATH = "/home/user/app/server/main.cpp"
SERVER_PATH = "/home/user/app/server/server"
SERVER_URL = "http://127.0.0.1:8080/api/v1/stats"


def test_database_integrity_and_index():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing"

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    # Preserve the original existence and integrity assertions.
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name='idx_time';")
    assert cursor.fetchone() is not None, "Index 'idx_time' is missing"

    cursor.execute("PRAGMA integrity_check;")
    result = cursor.fetchone()[0]
    assert result == "ok", f"Database integrity check failed: {result}"

    # Confirm idx_time is the required timestamp index and is usable by SQLite.
    cursor.execute("PRAGMA index_info('idx_time')")
    indexed_columns = [row[2] for row in cursor.fetchall()]
    assert indexed_columns == ["timestamp"], f"idx_time indexes unexpected columns: {indexed_columns}"

    cursor.execute("EXPLAIN QUERY PLAN SELECT * FROM measurements ORDER BY timestamp")
    plan = " ".join(str(row[3]) for row in cursor.fetchall())
    assert "idx_time" in plan, f"SQLite did not use idx_time for timestamp ordering: {plan}"
    conn.close()


def test_submitted_source_and_binary():
    assert os.path.isfile(SOURCE_PATH), "C++ server source is missing"
    assert os.path.isfile(SERVER_PATH), "Compiled C++ server is missing"

    with open(SERVER_PATH, "rb") as f:
        assert f.read(4) == b"\x7fELF", "server is not a compiled ELF executable"

    source = open(SOURCE_PATH, encoding="utf-8").read()
    assert re.search(r'Get\s*\(\s*["\']/api/v1/stats["\']', source), "Missing GET /api/v1/stats route"
    assert re.search(r'\bAVG\s*\(', source, re.I), "SQL does not calculate AVG"
    assert re.search(r'\bOVER\s*\(', source, re.I), "SQL does not use a window function"
    assert re.search(r'\bPARTITION\s+BY\s+(?:\w+\.)?exp_id\b', source, re.I), "Window is not partitioned by exp_id"
    assert re.search(r'\bORDER\s+BY\s+(?:\w+\.)?timestamp\b', source, re.I), "Window/query is not ordered by timestamp"


def test_services_running():
    try:
        ps_output = subprocess.check_output(["ps", "aux"]).decode("utf-8")
    except subprocess.CalledProcessError:
        pytest.fail("Failed to execute ps aux")

    assert "ingestor.py" in ps_output, "ingestor.py is not running"
    assert "./server" in ps_output or "server" in ps_output, "C++ server is not running"


def get_stats(exp_id):
    try:
        return requests.get(SERVER_URL, params={"exp_id": exp_id}, timeout=5)
    except requests.RequestException as e:
        pytest.fail(f"Failed to connect to the C++ server: {e}")


def test_api_endpoint():
    # Preserve the original exp_id=1 API checks.
    time.sleep(1)
    response = get_stats(1)

    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type application/json"

    try:
        data = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert "schema_version" in data, "Missing 'schema_version' in response"
    assert data["schema_version"] == "1.0", f"Expected schema_version '1.0', got {data['schema_version']}"
    assert "data" in data, "Missing 'data' in response"
    assert isinstance(data["data"], list), "'data' should be a list"

    measurements = data["data"]
    if not measurements:
        pytest.fail("No data returned for exp_id=1, expected at least some measurements.")

    running_sum = 0.0
    count = 0
    last_timestamp = None
    for row in measurements:
        assert "id" in row, "Missing 'id' in row"
        assert "timestamp" in row, "Missing 'timestamp' in row"
        assert "sensor_value" in row, "Missing 'sensor_value' in row"
        assert "cumulative_avg" in row, "Missing 'cumulative_avg' in row"

        if last_timestamp is not None:
            assert row["timestamp"] >= last_timestamp, "Results are not ordered by timestamp ascending"
        last_timestamp = row["timestamp"]

        val = float(row["sensor_value"])
        running_sum += val
        count += 1
        expected_avg = running_sum / count
        actual_avg = float(row["cumulative_avg"])
        assert abs(actual_avg - expected_avg) < 1e-5, (
            f"Incorrect cumulative_avg at id {row['id']}: expected {expected_avg}, got {actual_avg}"
        )


def test_api_matches_random_database_rows():
    # Insert unpredictable, isolated data so a fixed response cannot pass.
    conn = sqlite3.connect(DB_PATH, timeout=10)
    cursor = conn.cursor()
    while True:
        exp_id = secrets.randbelow(1_500_000_000) + 100_000
        cursor.execute("SELECT 1 FROM measurements WHERE exp_id=? LIMIT 1", (exp_id,))
        if cursor.fetchone() is None:
            break

    nonce = secrets.token_hex(6)
    rows = [
        (f"2042-04-05T00:00:00.{nonce}Z", secrets.randbelow(900000) / 137.0 - 1000.0),
        (f"2042-04-01T00:00:00.{nonce}Z", secrets.randbelow(900000) / 137.0 - 1000.0),
        (f"2042-04-04T00:00:00.{nonce}Z", secrets.randbelow(900000) / 137.0 - 1000.0),
        (f"2042-04-02T00:00:00.{nonce}Z", secrets.randbelow(900000) / 137.0 - 1000.0),
        (f"2042-04-03T00:00:00.{nonce}Z", secrets.randbelow(900000) / 137.0 - 1000.0),
    ]
    cursor.executemany(
        "INSERT INTO measurements(exp_id, timestamp, sensor_value) VALUES (?, ?, ?)",
        [(exp_id, timestamp, value) for timestamp, value in rows],
    )
    conn.commit()

    cursor.execute(
        "SELECT id, timestamp, sensor_value FROM measurements WHERE exp_id=? ORDER BY timestamp ASC",
        (exp_id,),
    )
    expected_rows = cursor.fetchall()
    conn.close()

    response = get_stats(exp_id)
    assert response.status_code == 200, f"Expected status code 200, got {response.status_code}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type application/json"
    try:
        payload = response.json()
    except ValueError:
        pytest.fail("Response is not valid JSON")

    assert payload.get("schema_version") == "1.0"
    assert isinstance(payload.get("data"), list)
    actual_rows = payload["data"]
    assert len(actual_rows) == len(expected_rows), (
        f"Expected {len(expected_rows)} database rows, got {len(actual_rows)}"
    )

    running_sum = 0.0
    for position, (actual, expected) in enumerate(zip(actual_rows, expected_rows), start=1):
        expected_id, expected_timestamp, expected_value = expected
        assert set(("id", "timestamp", "sensor_value", "cumulative_avg")).issubset(actual)
        assert actual["id"] == expected_id, f"Wrong id at row {position}"
        assert actual["timestamp"] == expected_timestamp, f"Wrong timestamp at row {position}"
        assert abs(float(actual["sensor_value"]) - float(expected_value)) < 1e-9, (
            f"Wrong sensor_value at row {position}"
        )
        running_sum += float(expected_value)
        expected_avg = running_sum / position
        assert abs(float(actual["cumulative_avg"]) - expected_avg) < 1e-5, (
            f"Wrong cumulative_avg at row {position}: expected {expected_avg}"
        )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    reward=1
fi
exit 0
