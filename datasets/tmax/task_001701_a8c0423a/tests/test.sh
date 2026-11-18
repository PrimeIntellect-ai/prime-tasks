#!/bin/bash
mkdir -p /logs/verifier

DB=/home/user/backups.db
JSON=/home/user/routing_plan.json
SRC=/home/user/backup_router.go
MOD=/home/user/go.mod
BACKUP=$(mktemp /tmp/backups.db.XXXXXX)
ok=1

cp -p "$DB" "$BACKUP" || ok=0
restore_db() {
    rm -f "$DB-wal" "$DB-shm" "$DB-journal"
    cp -p "$BACKUP" "$DB"
}
trap 'restore_db; rm -f "$BACKUP"' EXIT

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import stat
import json
import sqlite3
import heapq
import math
import re
import pytest

DB_PATH = "/home/user/backups.db"
JSON_PATH = "/home/user/routing_plan.json"
SOURCE_PATH = "/home/user/backup_router.go"
MODULE_PATH = "/home/user/go.mod"

def get_db_connection():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."
    return sqlite3.connect(DB_PATH)

def compute_expected_routing_plan():
    conn = get_db_connection()
    cursor = conn.cursor()

    cursor.execute("SELECT id, name FROM datacenters")
    datacenters = {row[0]: row[1] for row in cursor.fetchall()}

    alpha_id = next((k for k, v in datacenters.items() if v == 'DC-Alpha'), None)
    omega_id = next((k for k, v in datacenters.items() if v == 'DC-Omega'), None)

    assert alpha_id is not None, "DC-Alpha not found in database"
    assert omega_id is not None, "DC-Omega not found in database"

    cursor.execute("SELECT source_id, dest_id, latency_ms FROM network_links")
    links = cursor.fetchall()

    graph = {k: {} for k in datacenters.keys()}
    for u, v, w in links:
        graph[u][v] = w

    pq = [(0, alpha_id, [])]
    visited = set()
    shortest_path = None

    while pq:
        dist, current_node, path = heapq.heappop(pq)
        if current_node in visited:
            continue
        visited.add(current_node)
        path = path + [current_node]
        if current_node == omega_id:
            shortest_path = path
            break
        for neighbor, weight in graph[current_node].items():
            if neighbor not in visited:
                heapq.heappush(pq, (dist + weight, neighbor, path))

    assert shortest_path is not None, "No path found from DC-Alpha to DC-Omega"

    expected_plan = []
    for i in range(len(shortest_path) - 1):
        u = shortest_path[i]
        v = shortest_path[i + 1]
        cursor.execute("""
            SELECT bytes_transferred, duration_ms
            FROM transfer_logs
            WHERE source_id = ? AND dest_id = ? AND status = 'SUCCESS'
            ORDER BY timestamp DESC
            LIMIT 3
        """, (u, v))
        logs = cursor.fetchall()
        if not logs:
            avg_speed = 0.0
        else:
            speeds = [bytes_ / duration for bytes_, duration in logs]
            avg_speed = sum(speeds) / len(speeds)
        expected_plan.append({
            "source": datacenters[u],
            "dest": datacenters[v],
            "avg_speed_bytes_per_ms": round(avg_speed, 2)
        })

    conn.close()
    return expected_plan

def test_program_and_module_exist():
    assert os.path.exists(SOURCE_PATH), f"{SOURCE_PATH} does not exist."
    assert stat.S_ISREG(os.lstat(SOURCE_PATH).st_mode), f"{SOURCE_PATH} must be a regular file."
    assert os.path.exists(MODULE_PATH), f"{MODULE_PATH} does not exist; initialize a Go module in /home/user."
    assert stat.S_ISREG(os.lstat(MODULE_PATH).st_mode), f"{MODULE_PATH} must be a regular file."
    with open(MODULE_PATH, encoding="utf-8") as f:
        assert re.search(r"(?m)^\s*module\s+\S+", f.read()), "go.mod has no module declaration."

def test_sql_window_function_is_present():
    with open(SOURCE_PATH, encoding="utf-8") as f:
        source = f.read()
    assert re.search(r"(?is)\b(?:row_number|rank|dense_rank|avg|sum|count|min|max)\s*\([^;]*?\)\s*over\s*\(", source), \
        "The Go program must use an SQL analytical/window function with an OVER clause."
    assert re.search(r"(?i)\btransfer_logs\b", source), "The SQL must query transfer_logs."

def test_routing_plan_exists():
    assert os.path.exists(JSON_PATH), f"Routing plan file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."

def test_routing_plan_format_and_correctness():
    assert os.path.exists(JSON_PATH), f"Routing plan file {JSON_PATH} does not exist."

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse {JSON_PATH} as JSON: {e}")

    assert isinstance(data, list), "JSON output must be a list of objects."
    expected_plan = compute_expected_routing_plan()
    assert len(data) == len(expected_plan), f"Expected {len(expected_plan)} hops in the routing plan, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_plan)):
        assert isinstance(actual, dict), f"Hop {i} is not a JSON object."
        expected_keys = {"source", "dest", "avg_speed_bytes_per_ms"}
        actual_keys = set(actual.keys())
        assert actual_keys == expected_keys, f"Hop {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."
        assert actual["source"] == expected["source"], f"Hop {i} source mismatch. Expected '{expected['source']}', got '{actual['source']}'."
        assert actual["dest"] == expected["dest"], f"Hop {i} dest mismatch. Expected '{expected['dest']}', got '{actual['dest']}'."
        actual_speed = actual["avg_speed_bytes_per_ms"]
        expected_speed = expected["avg_speed_bytes_per_ms"]
        assert isinstance(actual_speed, (int, float)), f"Hop {i} avg_speed_bytes_per_ms must be a number."
        assert math.isclose(actual_speed, expected_speed, rel_tol=1e-5, abs_tol=1e-2), \
            f"Hop {i} avg_speed_bytes_per_ms mismatch. Expected {expected_speed}, got {actual_speed}."
TEST_EOF

run_program() {
    rm -f "$JSON"
    (cd /home/user && timeout 180s go run ./backup_router.go)
}

# Execute and validate against the original database.
original_hash=$(sha256sum "$DB" | awk '{print $1}')
if ! run_program; then ok=0; fi
if [ "$(sha256sum "$DB" | awk '{print $1}')" != "$original_hash" ]; then ok=0; fi
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then ok=0; fi

# Change both the optimal route and transfer history, then execute the submitted
# program again. Expected results are independently derived from this database.
if ! sqlite3 "$DB" <<'SQL'
BEGIN;
DELETE FROM network_links;
INSERT INTO network_links VALUES (1, 2, 1);
INSERT INTO network_links VALUES (2, 5, 100);
INSERT INTO network_links VALUES (1, 4, 7);
INSERT INTO network_links VALUES (4, 5, 8);
INSERT INTO network_links VALUES (1, 3, 40);
INSERT INTO network_links VALUES (3, 5, 40);
DELETE FROM transfer_logs;
INSERT INTO transfer_logs VALUES (101, 1, 4, 100, 10, '2025-01-01 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (102, 1, 4, 900, 10, '2025-01-02 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (103, 1, 4, 9990, 10, '2025-01-03 10:00:00', 'FAILED');
INSERT INTO transfer_logs VALUES (104, 1, 4, 300, 10, '2025-01-04 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (105, 1, 4, 600, 10, '2025-01-05 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (106, 4, 5, 100, 8, '2025-02-01 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (107, 4, 5, 200, 8, '2025-02-02 10:00:00', 'SUCCESS');
INSERT INTO transfer_logs VALUES (108, 4, 5, 8000, 8, '2025-02-03 10:00:00', 'FAILED');
COMMIT;
SQL
then
    ok=0
fi

mutated_hash=$(sha256sum "$DB" | awk '{print $1}')
if ! run_program; then ok=0; fi
if [ "$(sha256sum "$DB" | awk '{print $1}')" != "$mutated_hash" ]; then ok=0; fi
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then ok=0; fi

# Restore the supplied database and leave the required final output generated by
# the submitted program for that original database.
restore_db
original_hash=$(sha256sum "$DB" | awk '{print $1}')
if ! run_program; then ok=0; fi
if [ "$(sha256sum "$DB" | awk '{print $1}')" != "$original_hash" ]; then ok=0; fi
if ! python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short; then ok=0; fi

if [ "$ok" -eq 1 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
