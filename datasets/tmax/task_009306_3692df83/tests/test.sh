#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import socket
import sqlite3
import time

import pytest
import requests

DB_PATH = "/home/user/artifacts.db"
INCOMING_PATH = "/home/user/incoming_artifacts.json"


def load_incoming():
    with open(INCOMING_PATH, "r", encoding="utf-8") as f:
        return json.load(f)


def test_artifacts_db_schema_migrated():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("PRAGMA table_info(packages);")
    info = {row[1]: row for row in cursor.fetchall()}
    conn.close()

    columns = set(info)
    assert "checksum" in columns, "Column 'checksum' is missing from the packages table."
    assert "dependencies" in columns, "Column 'dependencies' is missing from the packages table."
    assert info["checksum"][2].upper() == "TEXT", "Column 'checksum' must have type TEXT."
    assert info["dependencies"][2].upper() == "TEXT", "Column 'dependencies' must have type TEXT."


def test_artifacts_db_rows_and_metadata():
    incoming = load_incoming()
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    rows = conn.execute(
        "SELECT name, version, path, checksum, dependencies, active FROM packages"
    ).fetchall()
    conn.close()

    assert len(rows) == 7, f"Expected exactly 7 package rows, got {len(rows)}"

    for artifact in incoming:
        matches = [
            row for row in rows
            if row["name"] == artifact["name"] and row["version"] == artifact["version"]
        ]
        assert len(matches) == 1, (
            f"Expected exactly one row for {artifact['name']} {artifact['version']}, "
            f"got {len(matches)}"
        )
        row = matches[0]
        assert row["path"] == artifact["path"], f"Incorrect path for {artifact['name']}"
        assert row["checksum"] == artifact["checksum"], f"Incorrect checksum for {artifact['name']}"
        assert isinstance(row["dependencies"], str), (
            f"Dependencies for {artifact['name']} must be stored as JSON text"
        )
        try:
            dependencies = json.loads(row["dependencies"])
        except (TypeError, json.JSONDecodeError) as exc:
            pytest.fail(f"Invalid dependency JSON for {artifact['name']}: {exc}")
        assert dependencies == artifact["dependencies"], (
            f"Incorrect dependencies for {artifact['name']}: {dependencies}"
        )

    expected_initial = {
        ("BaseLib", "1.0", "/repo/baselib/1.0"),
        ("OldTool", "0.9", "/repo/oldtool/0.9"),
    }
    actual_initial = {
        (row["name"], row["version"], row["path"])
        for row in rows
        if (row["name"], row["version"]) in {("BaseLib", "1.0"), ("OldTool", "0.9")}
    }
    assert actual_initial == expected_initial


def test_artifacts_db_active_packages():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()

    cursor.execute("SELECT name, version FROM packages WHERE active=1 ORDER BY name;")
    active_rows = cursor.fetchall()

    expected_active = {
        ("BaseLib", "1.1"),
        ("DataParser", "1.5"),
        ("DataPipeline", "2.0"),
        ("MathLib", "3.0")
    }
    assert set(active_rows) == expected_active, f"Active packages are incorrect. Expected {expected_active}, got {set(active_rows)}"

    cursor.execute("SELECT name, version FROM packages WHERE active=0 ORDER BY name;")
    inactive_rows = cursor.fetchall()

    expected_inactive = {
        ("BaseLib", "1.0"),
        ("OldTool", "0.9"),
        ("UnusedLib", "1.0")
    }
    assert set(inactive_rows) == expected_inactive, f"Inactive packages are incorrect. Expected {expected_inactive}, got {set(inactive_rows)}"

    conn.close()


def test_active_set_is_recursive_dependency_closure():
    incoming = load_incoming()
    by_name = {artifact["name"]: artifact for artifact in incoming}
    closure = set()
    pending = ["DataPipeline"]
    while pending:
        name = pending.pop()
        if name in closure:
            continue
        assert name in by_name, f"Dependency {name} has no incoming artifact"
        closure.add(name)
        pending.extend(by_name[name]["dependencies"])

    expected = {(name, by_name[name]["version"]) for name in closure}
    conn = sqlite3.connect(DB_PATH)
    actual = set(conn.execute("SELECT name, version FROM packages WHERE active=1"))
    conn.close()
    assert actual == expected, f"Active rows do not match the recursive dependency closure: {actual}"


def test_rate_limit_test_log():
    log_path = "/home/user/rate_limit_test.log"
    assert os.path.exists(log_path), f"Log file {log_path} does not exist."

    with open(log_path, "r", encoding="utf-8") as f:
        lines = [line.strip() for line in f if line.strip()]

    expected_lines = ["200", "200", "200", "429"]
    assert lines == expected_lines, f"Rate limit log contents are incorrect. Expected {expected_lines}, got {lines}"


def test_live_query_server_and_rate_limit():
    try:
        with socket.create_connection(("127.0.0.1", 8080), timeout=3):
            pass
    except OSError as exc:
        pytest.fail(f"No query server is listening on port 8080: {exc}")

    # Let requests made by the agent's verification script age out so this is an
    # independent rate-limit window from the same loopback IP.
    time.sleep(61)

    incoming = {item["name"]: item for item in load_incoming()}
    names = ["DataPipeline", "BaseLib", "DataParser", "MathLib"]
    session = requests.Session()
    session.trust_env = False
    responses = []
    for name in names:
        responses.append(session.get(
            "http://127.0.0.1:8080/package",
            params={"name": name},
            timeout=5,
        ))

    statuses = [response.status_code for response in responses]
    assert statuses == [200, 200, 200, 429], (
        f"Live server did not enforce 3 requests per minute per IP: got {statuses}"
    )

    for name, response in zip(names[:3], responses[:3]):
        assert response.headers.get("Content-Type", "").lower().startswith("application/json"), (
            f"Response for {name} is not JSON"
        )
        assert response.json() == {
            "name": name,
            "version": incoming[name]["version"],
            "checksum": incoming[name]["checksum"],
        }, f"Incorrect live server response for {name}: {response.text}"
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
