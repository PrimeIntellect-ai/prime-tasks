#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import sqlite3
import time
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:8000"
DB_PATH = "/app/backup_metadata.db"
SQL_PATH = "/app/report.sql"
RECOVERY_KEY = "RK-992-ALPHA"


@pytest.fixture(scope="session", autouse=True)
def wait_for_server():
    """Wait for the HTTP server to become available."""
    timeout = 10
    start_time = time.time()
    while time.time() - start_time < timeout:
        try:
            requests.get(f"{BASE_URL}/api/report", timeout=1)
            return
        except requests.exceptions.RequestException:
            time.sleep(0.5)
    pytest.fail(f"Server did not start on {BASE_URL} within {timeout} seconds.")


def get_json(path):
    response = requests.get(f"{BASE_URL}{path}", timeout=5)
    assert response.status_code == 200, (
        f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    )
    assert "application/json" in response.headers.get("Content-Type", ""), (
        "Expected Content-Type to be application/json"
    )
    try:
        return response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")


def assert_report_schema(data):
    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"
    for row in data:
        assert isinstance(row, dict), f"Report row is not an object: {row!r}"
        assert set(row) == {"backup_id", "dc_name", "status"}, (
            f"Report row has the wrong schema: {row!r}"
        )
        assert type(row["backup_id"]) is str
        assert type(row["dc_name"]) is str
        assert type(row["status"]) is str


def independently_expected_report():
    with sqlite3.connect(DB_PATH) as conn:
        rows = conn.execute(
            "SELECT b.backup_id, d.dc_name, b.status "
            "FROM backups AS b JOIN data_centers AS d ON b.dc_id = d.id "
            "WHERE b.encryption_key = ?",
            (RECOVERY_KEY,),
        ).fetchall()
    return sorted(
        [
            {"backup_id": backup_id, "dc_name": dc_name, "status": status}
            for backup_id, dc_name, status in rows
        ],
        key=lambda row: (row["backup_id"], row["dc_name"], row["status"]),
    )


def execute_submitted_report_sql():
    with open(SQL_PATH, "r", encoding="utf-8") as handle:
        sql = handle.read().strip()
    assert sql, "/app/report.sql is empty"
    with sqlite3.connect(DB_PATH) as conn:
        cursor = conn.execute(sql)
        assert [column[0] for column in cursor.description] == [
            "backup_id",
            "dc_name",
            "status",
        ], "report.sql must return exactly backup_id, dc_name, and status"
        rows = cursor.fetchall()
    return sorted(
        [
            {"backup_id": row[0], "dc_name": row[1], "status": row[2]}
            for row in rows
        ],
        key=lambda row: (row["backup_id"], row["dc_name"], row["status"]),
    )


def shortest_path_from_db(src, dst):
    with sqlite3.connect(DB_PATH) as conn:
        edges = conn.execute(
            "SELECT source_dc, target_dc, latency_ms FROM network_links"
        ).fetchall()

    graph = {}
    for source, target, latency in edges:
        graph.setdefault(source, []).append((target, latency))

    queue = [(0, (src,), src)]
    best = {src: 0}
    while queue:
        total, path_tuple, node = heapq.heappop(queue)
        if total != best.get(node):
            continue
        if node == dst:
            return list(path_tuple), total
        for neighbor, latency in graph.get(node, []):
            candidate = total + latency
            if candidate < best.get(neighbor, float("inf")):
                best[neighbor] = candidate
                heapq.heappush(queue, (candidate, path_tuple + (neighbor,), neighbor))
    raise AssertionError(f"No path in verifier graph from {src} to {dst}")


def assert_route(src, dst):
    data = get_json(f"/api/route?src={src}&dst={dst}")
    assert isinstance(data, dict), f"Expected a JSON object, got {type(data).__name__}"
    assert set(data) == {"path", "total_latency"}, f"Wrong route schema: {data!r}"
    assert isinstance(data["path"], list)
    assert all(type(node) is str for node in data["path"])
    assert type(data["total_latency"]) is int
    expected_path, expected_latency = shortest_path_from_db(src, dst)
    assert data.get("path") == expected_path, (
        f"Expected path {expected_path}, got {data.get('path')}"
    )
    assert data.get("total_latency") == expected_latency, (
        f"Expected total_latency {expected_latency}, got {data.get('total_latency')}"
    )


def test_api_report_endpoint():
    url = f"{BASE_URL}/api/report"
    response = requests.get(url, timeout=5)

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type to be application/json"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    assert isinstance(data, list), f"Expected a JSON array, got {type(data).__name__}"

    expected_records = [
        {"backup_id": "B-100", "dc_name": "US-EAST-1", "status": "SUCCESS"},
        {"backup_id": "B-101", "dc_name": "EU-WEST-1", "status": "FAILED"},
        {"backup_id": "B-103", "dc_name": "AP-SOUTH-1", "status": "SUCCESS"}
    ]

    assert len(data) == len(expected_records), f"Expected {len(expected_records)} records, got {len(data)}. Data: {data}"

    sorted_actual = sorted(data, key=lambda x: x.get("backup_id", ""))
    sorted_expected = sorted(expected_records, key=lambda x: x["backup_id"])

    assert sorted_actual == sorted_expected, f"Report data mismatch. Expected: {sorted_expected}, Actual: {sorted_actual}"


def test_submitted_sql_is_correct():
    assert execute_submitted_report_sql() == independently_expected_report()


def test_api_route_endpoint():
    url = f"{BASE_URL}/api/route?src=US-EAST-1&dst=AP-SOUTH-1"
    response = requests.get(url, timeout=5)

    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}. Response: {response.text}"
    assert "application/json" in response.headers.get("Content-Type", ""), "Expected Content-Type to be application/json"

    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"Response body is not valid JSON: {response.text}")

    assert isinstance(data, dict), f"Expected a JSON object, got {type(data).__name__}"

    expected_path = ["US-EAST-1", "EU-WEST-1", "AP-SOUTH-1"]
    expected_latency = 210

    assert data.get("path") == expected_path, f"Expected path {expected_path}, got {data.get('path')}"
    assert data.get("total_latency") == expected_latency, f"Expected total_latency {expected_latency}, got {data.get('total_latency')}"


def test_report_uses_sqlite_data_and_recovery_filter():
    token = uuid.uuid4().hex[:12]
    dc_id = 1000000 + int(token[:6], 16)
    dc_name = f"DYNAMIC-DC-{token}"
    good_id = f"DYN-GOOD-{token}"
    wrong_id = f"DYN-WRONG-{token}"
    orphan_id = f"DYN-ORPHAN-{token}"
    dynamic_status = f"STATUS-{token}"

    with sqlite3.connect(DB_PATH, timeout=5) as conn:
        conn.execute("INSERT INTO data_centers(id, dc_name) VALUES (?, ?)", (dc_id, dc_name))
        conn.execute(
            "INSERT INTO backups(backup_id, dc_id, status, encryption_key) VALUES (?, ?, ?, ?)",
            (good_id, dc_id, dynamic_status, RECOVERY_KEY),
        )
        conn.execute(
            "INSERT INTO backups(backup_id, dc_id, status, encryption_key) VALUES (?, ?, ?, ?)",
            (wrong_id, dc_id, "MUST-NOT-APPEAR", f"WRONG-{token}"),
        )
        conn.execute(
            "INSERT INTO backups(backup_id, dc_id, status, encryption_key) VALUES (?, ?, ?, ?)",
            (orphan_id, dc_id + 1, "MUST-NOT-APPEAR", RECOVERY_KEY),
        )
        conn.commit()

    expected = independently_expected_report()
    sql_result = execute_submitted_report_sql()
    assert sql_result == expected, "report.sql does not implement the required join and key filter"

    data = get_json("/api/report")
    assert_report_schema(data)
    actual = sorted(data, key=lambda row: (row["backup_id"], row["dc_name"], row["status"]))
    assert actual == expected, "The report API did not reflect the current database/query result"
    assert any(row["backup_id"] == good_id for row in data)
    assert all(row["backup_id"] not in {wrong_id, orphan_id} for row in data)


def test_route_traverses_dynamic_graph_and_reacts_to_weights():
    token = uuid.uuid4().hex[:12]
    src = f"SRC-{token}"
    mid = f"MID-{token}"
    alternate = f"ALT-{token}"
    dst = f"DST-{token}"

    with sqlite3.connect(DB_PATH, timeout=5) as conn:
        conn.executemany(
            "INSERT INTO network_links(source_dc, target_dc, latency_ms) VALUES (?, ?, ?)",
            [
                (src, dst, 90),
                (src, mid, 11),
                (mid, dst, 13),
                (src, alternate, 5),
                (alternate, dst, 40),
                (mid, alternate, 30),
            ],
        )
        conn.commit()

    assert_route(src, dst)
    assert_route(src, alternate)
    assert_route(mid, dst)

    with sqlite3.connect(DB_PATH, timeout=5) as conn:
        conn.execute(
            "UPDATE network_links SET latency_ms = 1 WHERE source_dc = ? AND target_dc = ?",
            (src, dst),
        )
        conn.commit()

    assert_route(src, dst)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
