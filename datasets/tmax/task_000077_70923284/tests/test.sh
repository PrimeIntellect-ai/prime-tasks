#!/bin/bash
set -e
mkdir -p /logs/verifier

DB_SNAPSHOT=$(mktemp)
cp /home/user/backup_network.db "$DB_SNAPSHOT"
trap 'cp "$DB_SNAPSHOT" /home/user/backup_network.db; rm -f "$DB_SNAPSHOT"' EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import heapq
import json
import os
import sqlite3
import subprocess
import sys
import uuid
import pytest

DB_PATH = "/home/user/backup_network.db"
SCRIPT_PATH = "/home/user/plan_route.py"
BACKUP_ID = "BKP-9001"
OUTPUT_FILE = f"/home/user/route_{BACKUP_ID}.json"


def compute_expected_route(db_path, backup_id):
    if not os.path.exists(db_path):
        pytest.fail(f"Database file missing: {db_path}")

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT source_dc_id, dest_dc_id FROM pending_backups WHERE backup_id = ?", (backup_id,))
    row = cursor.fetchone()
    if not row:
        pytest.fail(f"Backup ID {backup_id} not found in pending_backups")
    src, dest = row

    cursor.execute("SELECT source_id, dest_id, latency_ms FROM network_links WHERE status = 'UP'")
    links = cursor.fetchall()

    cursor.execute("SELECT id, name FROM datacenters")
    dc_names = dict(cursor.fetchall())
    conn.close()

    graph = {}
    for u, v, w in links:
        graph.setdefault(u, []).append((v, w))

    pq = [(0, src, [src])]
    visited = set()

    while pq:
        dist, current, path = heapq.heappop(pq)

        if current == dest:
            return dist, [dc_names[n] for n in path]

        if current in visited:
            continue
        visited.add(current)

        for neighbor, weight in graph.get(current, []):
            if neighbor not in visited:
                heapq.heappush(pq, (dist + weight, neighbor, path + [neighbor]))

    return None, None


def run_script(backup_id):
    output_file = f"/home/user/route_{backup_id}.json"
    if os.path.lexists(output_file):
        os.remove(output_file)
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH, backup_id],
        text=True,
        capture_output=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"plan_route.py failed for {backup_id!r}\n"
        f"stdout: {result.stdout}\nstderr: {result.stderr}"
    )
    return output_file


def test_01_script_exists_and_uses_parameterized_backup_query():
    assert os.path.exists(SCRIPT_PATH), f"Expected script not found: {SCRIPT_PATH}"
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file"

    with open(SCRIPT_PATH, "r", encoding="utf-8") as f:
        source = f.read()
    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"{SCRIPT_PATH} is not valid Python: {exc}")

    string_bindings = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Assign) and isinstance(node.value, ast.Constant) and isinstance(node.value.value, str):
            for target in node.targets:
                if isinstance(target, ast.Name):
                    string_bindings[target.id] = node.value.value

    found_parameterized_query = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in ("execute", "executemany") or len(node.args) < 2:
            continue
        query_node = node.args[0]
        query = None
        if isinstance(query_node, ast.Constant) and isinstance(query_node.value, str):
            query = query_node.value
        elif isinstance(query_node, ast.Name):
            query = string_bindings.get(query_node.id)
        if query:
            lowered = query.lower()
            has_placeholder = any(marker in query for marker in ("?", ":", "@", "$"))
            if "pending_backups" in lowered and "backup_id" in lowered and has_placeholder:
                found_parameterized_query = True
                break

    assert found_parameterized_query, (
        "The backup lookup must use a parameterized SQLite execute call with the "
        "backup_id supplied separately from the SQL string"
    )


def test_json_output():
    run_script(BACKUP_ID)

    assert os.path.exists(OUTPUT_FILE), f"Expected output file not found: {OUTPUT_FILE}"
    assert os.path.isfile(OUTPUT_FILE), f"{OUTPUT_FILE} is not a file"

    with open(OUTPUT_FILE, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {OUTPUT_FILE} does not contain valid JSON")

    expected_latency, expected_path = compute_expected_route(DB_PATH, BACKUP_ID)
    if expected_latency is None:
        pytest.fail("Could not compute a valid path from the database")

    assert "backup_id" in data, "Missing 'backup_id' in JSON output"
    assert data["backup_id"] == BACKUP_ID, f"Expected backup_id '{BACKUP_ID}', got '{data['backup_id']}'"

    assert "total_latency_ms" in data, "Missing 'total_latency_ms' in JSON output"
    assert data["total_latency_ms"] == expected_latency, f"Expected total_latency_ms {expected_latency}, got {data['total_latency_ms']}"

    assert "path" in data, "Missing 'path' in JSON output"
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}"


def test_script_is_reusable_for_runtime_database_input():
    dynamic_id = "BKP-Q'" + uuid.uuid4().hex
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(
            "INSERT INTO pending_backups (backup_id, source_dc_id, dest_dc_id, data_size_tb) VALUES (?, ?, ?, ?)",
            (dynamic_id, 2, 5, None),
        )
        conn.execute(
            "INSERT INTO network_links (source_id, dest_id, latency_ms, status) VALUES (?, ?, ?, ?)",
            (2, 5, 7, "UP"),
        )
        conn.commit()
    finally:
        conn.close()

    output_file = run_script(dynamic_id)
    try:
        assert os.path.isfile(output_file), f"Expected output file not found: {output_file}"
        with open(output_file, "r", encoding="utf-8") as f:
            data = json.load(f)

        expected_latency, expected_path = compute_expected_route(DB_PATH, dynamic_id)
        assert data.get("backup_id") == dynamic_id
        assert data.get("total_latency_ms") == expected_latency
        assert data.get("path") == expected_path
    finally:
        if os.path.lexists(output_file):
            os.remove(output_file)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
