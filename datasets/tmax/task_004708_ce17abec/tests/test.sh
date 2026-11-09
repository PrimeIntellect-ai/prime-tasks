#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import time
import uuid
import socket
import signal
import subprocess
import requests
import pytest


def psql(sql, *extra):
    cmd = ["psql", "-U", "postgres", "-d", "company", "-X", "-v", "ON_ERROR_STOP=1", *extra, "-c", sql]
    return subprocess.run(cmd, capture_output=True, text=True)


def stop_port_8080_listeners():
    """Stop any pre-existing listener so /app/start.sh must bring up the tested service."""
    inodes = set()
    for table in ("/proc/net/tcp", "/proc/net/tcp6"):
        try:
            with open(table) as f:
                next(f, None)
                for line in f:
                    fields = line.split()
                    if len(fields) >= 10 and fields[3] == "0A":
                        port = int(fields[1].rsplit(":", 1)[1], 16)
                        if port == 8080:
                            inodes.add(fields[9])
        except OSError:
            pass

    for pid in os.listdir("/proc"):
        if not pid.isdigit() or int(pid) == os.getpid():
            continue
        fd_dir = f"/proc/{pid}/fd"
        try:
            for fd in os.listdir(fd_dir):
                try:
                    target = os.readlink(os.path.join(fd_dir, fd))
                except OSError:
                    continue
                if target.startswith("socket:[") and target[8:-1] in inodes:
                    os.kill(int(pid), signal.SIGTERM)
                    break
        except (OSError, ProcessLookupError, PermissionError):
            pass
    if inodes:
        time.sleep(1)


@pytest.fixture(scope="session", autouse=True)
def ensure_service_running():
    assert os.path.isfile("/app/start.sh"), "/app/start.sh does not exist"
    stop_port_8080_listeners()

    proc = subprocess.Popen(
        ["bash", "/app/start.sh"],
        stdout=subprocess.DEVNULL,
        stderr=subprocess.DEVNULL,
    )
    try:
        rc = proc.wait(timeout=20)
    except subprocess.TimeoutExpired:
        proc.kill()
        pytest.fail("/app/start.sh did not finish after starting its background services")
    assert rc == 0, f"/app/start.sh exited with status {rc}"

    for _ in range(40):
        try:
            with socket.create_connection(("127.0.0.1", 8080), timeout=0.5):
                return
        except OSError:
            time.sleep(0.5)
    pytest.fail("Service on port 8080 did not start after running /app/start.sh")


def fetch(manager_id):
    try:
        response = requests.get(
            "http://127.0.0.1:8080/api/subordinates",
            params={"manager_id": manager_id},
            timeout=5,
        )
    except requests.exceptions.RequestException as exc:
        pytest.fail(f"HTTP request failed: {exc}")

    assert response.status_code == 200, (
        f"Expected HTTP 200, got {response.status_code}. Response: {response.text}"
    )
    content_type = response.headers.get("Content-Type", "")
    assert "application/json" in content_type, (
        f"Expected Content-Type: application/json, got {content_type}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response is not valid JSON: {response.text}")
    assert isinstance(data, list), "Expected response body to be a JSON array."
    return data


def assert_rows(actual, expected):
    actual_sorted = sorted(actual, key=lambda row: row.get("id", -1))
    expected_sorted = sorted(expected, key=lambda row: row["id"])
    assert len(actual_sorted) == len(expected_sorted), (
        f"Expected {len(expected_sorted)} records, got {len(actual_sorted)}: {actual_sorted}"
    )
    for actual_item, expected_item in zip(actual_sorted, expected_sorted):
        assert actual_item.get("id") == expected_item["id"]
        assert actual_item.get("name") == expected_item["name"]
        assert actual_item.get("depth") == expected_item["depth"]


def test_database_index_created():
    result = psql(
        "SELECT indexname FROM pg_indexes "
        "WHERE tablename = 'employees' AND indexname = 'idx_manager_id';",
        "-tA",
    )
    assert result.returncode == 0, f"Failed to query database: {result.stderr}"
    assert "idx_manager_id" in result.stdout, (
        "The index 'idx_manager_id' was not found on the employees table."
    )

    definition = psql("""
        SELECT i.indisvalid, i.indisready,
               i.indpred IS NULL,
               i.indexprs IS NULL,
               array_to_string(ARRAY(
                   SELECT a.attname
                   FROM unnest(i.indkey) WITH ORDINALITY AS k(attnum, ord)
                   JOIN pg_attribute a
                     ON a.attrelid = i.indrelid AND a.attnum = k.attnum
                   WHERE k.ord <= i.indnkeyatts
                   ORDER BY k.ord
               ), ',')
        FROM pg_index i
        JOIN pg_class idx ON idx.oid = i.indexrelid
        JOIN pg_class tbl ON tbl.oid = i.indrelid
        WHERE idx.relname = 'idx_manager_id'
          AND tbl.relname = 'employees';
    "", "-tA")
    assert definition.returncode == 0, definition.stderr
    assert definition.stdout.strip() == "t|t|t|t|manager_id", (
        "idx_manager_id must be a valid, non-partial index on employees(manager_id); "
        f"catalog result was {definition.stdout!r}"
    )


def test_recursive_query_and_index_execution_plan():
    assert os.path.isfile("/app/query.sql"), "/app/query.sql does not exist"
    with open("/app/query.sql") as f:
        query_text = f.read()
    assert re.search(r"\bWITH\s+RECURSIVE\b", query_text, re.IGNORECASE), (
        "/app/query.sql must use WITH RECURSIVE"
    )

    explain_path = "/tmp/explain_submission.sql"
    with open(explain_path, "w") as f:
        f.write("SET enable_seqscan = off;\nEXPLAIN (COSTS OFF)\n")
        f.write(query_text)
        if not query_text.rstrip().endswith(";"):
            f.write(";")
        f.write("\n")

    result = subprocess.run(
        ["psql", "-U", "postgres", "-d", "company", "-X", "-v", "ON_ERROR_STOP=1",
         "-v", "v_manager_id=1", "-f", explain_path],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Could not EXPLAIN /app/query.sql: {result.stderr}"
    assert "Recursive Union" in result.stdout, (
        "The execution plan for /app/query.sql does not contain a recursive traversal"
    )
    assert "idx_manager_id" in result.stdout, (
        "The recursive execution plan does not use idx_manager_id for hierarchy traversal. "
        f"Plan:\n{result.stdout}"
    )


def test_api_subordinates_response():
    expected = [
        {"id": 1, "name": "Alice", "depth": 0},
        {"id": 2, "name": "Bob", "depth": 1},
        {"id": 4, "name": "Diana", "depth": 1},
        {"id": 3, "name": "Charlie", "depth": 2},
        {"id": 5, "name": "Eve", "depth": 2},
    ]
    assert_rows(fetch(1), expected)


def test_query_and_api_on_unpredictable_hierarchy():
    token = uuid.uuid4().hex[:10]
    base = 100000000 + (uuid.uuid4().int % 900000000)
    ids = [base + i for i in range(5)]
    names = [f"verify_{token}_{i}" for i in range(5)]
    rows = [
        (ids[0], names[0], None),
        (ids[1], names[1], ids[0]),
        (ids[2], names[2], ids[0]),
        (ids[3], names[3], ids[1]),
        (ids[4], names[4], ids[3]),
    ]

    values = []
    for emp_id, name, manager_id in rows:
        manager = "NULL" if manager_id is None else str(manager_id)
        values.append(f"({emp_id}, '{name}', {manager})")
    inserted = psql(
        "INSERT INTO employees(id, name, manager_id) VALUES " + ",".join(values) + ";"
    )
    assert inserted.returncode == 0, inserted.stderr

    expected_root = [
        {"id": ids[0], "name": names[0], "depth": 0},
        {"id": ids[1], "name": names[1], "depth": 1},
        {"id": ids[2], "name": names[2], "depth": 1},
        {"id": ids[3], "name": names[3], "depth": 2},
        {"id": ids[4], "name": names[4], "depth": 3},
    ]
    expected_branch = [
        {"id": ids[1], "name": names[1], "depth": 0},
        {"id": ids[3], "name": names[3], "depth": 1},
        {"id": ids[4], "name": names[4], "depth": 2},
    ]
    expected_leaf = [{"id": ids[2], "name": names[2], "depth": 0}]

    direct = subprocess.run(
        ["psql", "-U", "postgres", "-d", "company", "-X", "-v", "ON_ERROR_STOP=1",
         "-v", f"v_manager_id={ids[0]}", "-tA", "-F", "|", "-f", "/app/query.sql"],
        capture_output=True,
        text=True,
    )
    assert direct.returncode == 0, f"/app/query.sql failed: {direct.stderr}"
    parsed = []
    for line in direct.stdout.splitlines():
        if not line.strip():
            continue
        parts = line.split("|")
        assert len(parts) == 3, f"Unexpected query row: {line!r}"
        parsed.append({"id": int(parts[0]), "name": parts[1], "depth": int(parts[2])})
    assert_rows(parsed, expected_root)

    assert_rows(fetch(ids[0]), expected_root)
    assert_rows(fetch(ids[1]), expected_branch)
    assert_rows(fetch(ids[2]), expected_leaf)
    assert_rows(fetch(base + 100), [])
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
