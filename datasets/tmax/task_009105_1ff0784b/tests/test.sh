#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess

DB_PATH = "/home/user/logistics.db"
EVENTS_PATH = "/home/user/events.jsonl"

EXPECTED_SCHEMAS = {
    "hubs": [
        (0, "id", "INTEGER", 0, None, 1),
        (1, "name", "TEXT", 0, None, 0),
    ],
    "routes": [
        (0, "id", "INTEGER", 0, None, 1),
        (1, "src_hub", "INTEGER", 0, None, 0),
        (2, "dst_hub", "INTEGER", 0, None, 0),
        (3, "distance", "REAL", 0, None, 0),
    ],
    "deliveries": [
        (0, "id", "INTEGER", 0, None, 1),
        (1, "route_id", "INTEGER", 0, None, 0),
        (2, "duration_hours", "REAL", 0, None, 0),
    ],
}

EXPECTED_HUBS = [
    (1, "HubA"), (2, "HubB"), (3, "HubC"), (4, "HubD"), (5, "HubE")
]
EXPECTED_ROUTES = [
    (1, 1, 3, 150.5),
    (2, 3, 4, 200.0),
    (3, 1, 2, 50.0),
    (4, 2, 4, 120.0),
    (5, 4, 5, 300.0),
    (6, 3, 5, 100.0),
]
EXPECTED_DELIVERIES = [
    (1, 1, 90.0),
    (2, 2, 110.0),
    (3, 3, 40.0),
    (4, 4, 105.0),
    (5, 5, 150.0),
    (6, 6, 80.0),
]
EXPECTED_EVENTS = [
    {"hub_id": 1, "event": "processing", "time_spent": 12.5},
    {"hub_id": 1, "event": "processing", "time_spent": 11.5},
    {"hub_id": 2, "event": "processing", "time_spent": 5.0},
    {"hub_id": 3, "event": "processing", "time_spent": 14.0},
    {"hub_id": 3, "event": "processing", "time_spent": 16.0},
    {"hub_id": 4, "event": "processing", "time_spent": 10.5},
    {"hub_id": 5, "event": "processing", "time_spent": 8.0},
]


def read_events():
    with open(EVENTS_PATH, "r") as f:
        return [json.loads(line) for line in f if line.strip()]


def test_source_inputs_unchanged():
    assert os.path.isfile(DB_PATH), f"Database file {DB_PATH} is missing."
    assert os.path.isfile(EVENTS_PATH), f"{EVENTS_PATH} is missing."

    assert read_events() == EXPECTED_EVENTS, \
        "events.jsonl was modified; results must be derived from the supplied events."

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        for table, expected_schema in EXPECTED_SCHEMAS.items():
            cursor.execute(f"PRAGMA table_info('{table}')")
            assert cursor.fetchall() == expected_schema, f"Schema for {table} was modified."

        cursor.execute("SELECT id, name FROM hubs ORDER BY id")
        assert cursor.fetchall() == EXPECTED_HUBS, "The supplied hubs data was modified."
        cursor.execute("SELECT id, src_hub, dst_hub, distance FROM routes ORDER BY id")
        assert cursor.fetchall() == EXPECTED_ROUTES, "The supplied routes data was modified."
        cursor.execute("SELECT id, route_id, duration_hours FROM deliveries ORDER BY id")
        assert cursor.fetchall() == EXPECTED_DELIVERIES, "The supplied deliveries data was modified."
    finally:
        conn.close()


def test_phase1_index_created():
    db_path = DB_PATH
    assert os.path.isfile(db_path), f"Database file {db_path} is missing."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    # Check if an index exists on deliveries table for duration_hours
    cursor.execute("PRAGMA index_list('deliveries');")
    indexes = cursor.fetchall()

    index_found = False
    for idx in indexes:
        idx_name = idx[1]
        escaped_name = idx_name.replace("'", "''")
        cursor.execute(f"PRAGMA index_info('{escaped_name}');")
        columns = cursor.fetchall()
        for col in columns:
            if col[2] == 'duration_hours':
                index_found = True
                break
        if index_found:
            break

    conn.close()
    assert index_found, "Optimal index on deliveries.duration_hours was not created."


def _plan_details(content):
    lines = [line.rstrip() for line in content.splitlines() if line.strip()]
    assert lines and lines[0] == "QUERY PLAN", \
        "query_plan.txt is not in sqlite3's default EXPLAIN QUERY PLAN format."

    details = []
    for line in lines[1:]:
        match = re.fullmatch(r"(?:\|  |   )*(?:\|--|`--)(.+)", line)
        assert match, f"Invalid sqlite3 query-plan line: {line!r}"
        details.append(match.group(1))
    return details


def _assert_required_plan_shape(details, valid_indexes):
    assert len(details) == 4, \
        "The query plan must contain accesses for deliveries, routes, and both hub joins."
    assert all(detail.startswith("SEARCH ") for detail in details), \
        "The optimized query plan must use searches rather than full table scans."

    index_nodes = []
    pk_nodes = 0
    for detail in details:
        match = re.fullmatch(
            r"SEARCH .+ USING INDEX (.+) \(duration_hours>\?\)", detail,
            flags=re.IGNORECASE,
        )
        if match:
            index_nodes.append(match.group(1))
        if re.fullmatch(
            r"SEARCH .+ USING INTEGER PRIMARY KEY \(rowid=\?\)", detail,
            flags=re.IGNORECASE,
        ):
            pk_nodes += 1

    assert len(index_nodes) == 1, \
        "The plan must show an indexed duration_hours search on deliveries."
    assert index_nodes[0].casefold() in {name.casefold() for name in valid_indexes}, \
        "The plan names no real deliveries index led by duration_hours."
    assert pk_nodes == 3, \
        "The plan must include primary-key searches for routes and the two hub joins."


def test_phase1_query_plan():
    plan_path = "/home/user/query_plan.txt"
    assert os.path.isfile(plan_path), f"Query plan file {plan_path} is missing."

    with open(plan_path, "r") as f:
        content = f.read()

    # Retain the original requirement that the submitted plan reports index use.
    assert "USING INDEX" in content.upper(), \
        "The query plan does not indicate that an index was used."

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("PRAGMA index_list('deliveries')")
        valid_indexes = []
        for row in cursor.fetchall():
            index_name = row[1]
            escaped_name = index_name.replace("'", "''")
            cursor.execute(f"PRAGMA index_info('{escaped_name}')")
            columns = cursor.fetchall()
            if columns and columns[0][2] == "duration_hours":
                valid_indexes.append(index_name)
        assert valid_indexes, "No usable index led by deliveries.duration_hours exists."

        # Actually execute the required joined query and verify its result.
        query = """
            SELECT src.name, dst.name, d.duration_hours
            FROM deliveries AS d
            JOIN routes AS r ON r.id = d.route_id
            JOIN hubs AS src ON src.id = r.src_hub
            JOIN hubs AS dst ON dst.id = r.dst_hub
            WHERE d.duration_hours > 100
        """
        cursor.execute(query)
        assert sorted(cursor.fetchall()) == sorted([
            ("HubC", "HubD", 110.0),
            ("HubB", "HubD", 105.0),
            ("HubD", "HubE", 150.0),
        ]), "The required joined query does not produce the expected result."
    finally:
        conn.close()

    # Generate a real plan in this database as an additional check that the index
    # is operational, then validate both it and the submitted sqlite3-formatted plan.
    explain_sql = (
        "EXPLAIN QUERY PLAN SELECT src.name, dst.name, d.duration_hours "
        "FROM deliveries AS d "
        "JOIN routes AS r ON r.id=d.route_id "
        "JOIN hubs AS src ON src.id=r.src_hub "
        "JOIN hubs AS dst ON dst.id=r.dst_hub "
        "WHERE d.duration_hours > 100;"
    )
    generated = subprocess.run(
        ["sqlite3", DB_PATH, explain_sql],
        check=True,
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
    ).stdout
    _assert_required_plan_shape(_plan_details(generated), valid_indexes)
    _assert_required_plan_shape(_plan_details(content), valid_indexes)


def test_phase2_slow_hubs():
    jsonl_path = EVENTS_PATH
    csv_path = "/home/user/slow_hubs.csv"

    assert os.path.isfile(jsonl_path), f"{jsonl_path} is missing."
    assert os.path.isfile(csv_path), f"{csv_path} is missing."

    # Recompute truth from the integrity-checked source.
    hub_times = {}
    hub_counts = {}
    with open(jsonl_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            hid = data['hub_id']
            ts = data['time_spent']
            hub_times[hid] = hub_times.get(hid, 0.0) + ts
            hub_counts[hid] = hub_counts.get(hid, 0) + 1

    expected_slow_hubs = []
    for hid in sorted(hub_times.keys()):
        avg = hub_times[hid] / hub_counts[hid]
        if avg > 10.0:
            expected_slow_hubs.append(f"{hid},{avg:.2f}")

    with open(csv_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_slow_hubs, \
        f"slow_hubs.csv content is incorrect. Expected: {expected_slow_hubs}, Got: {actual_lines}"


def test_phase3_slow_graph():
    db_path = DB_PATH
    csv_path = "/home/user/slow_graph.csv"
    jsonl_path = EVENTS_PATH

    assert os.path.isfile(db_path), f"{db_path} is missing."
    assert os.path.isfile(csv_path), f"{csv_path} is missing."

    # Recompute slow hubs from the integrity-checked source.
    hub_times = {}
    hub_counts = {}
    with open(jsonl_path, 'r') as f:
        for line in f:
            if not line.strip():
                continue
            data = json.loads(line)
            hid = data['hub_id']
            ts = data['time_spent']
            hub_times[hid] = hub_times.get(hid, 0.0) + ts
            hub_counts[hid] = hub_counts.get(hid, 0) + 1

    slow_hubs = set()
    for hid, total_time in hub_times.items():
        if (total_time / hub_counts[hid]) > 10.0:
            slow_hubs.add(hid)

    # Recompute graph from the integrity-checked database.
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    cursor.execute("SELECT src_hub, dst_hub, distance FROM routes;")
    routes = cursor.fetchall()
    conn.close()

    expected_graph = []
    for src, dst, dist in routes:
        if src in slow_hubs and dst in slow_hubs:
            expected_graph.append((src, dst, dist))

    expected_graph.sort(key=lambda x: (x[0], x[1]))
    expected_lines = [f"{src},{dst},{dist}" for src, dst, dist in expected_graph]

    with open(csv_path, 'r') as f:
        actual_lines = [line.strip() for line in f if line.strip()]

    assert actual_lines == expected_lines, \
        f"slow_graph.csv content is incorrect. Expected: {expected_lines}, Got: {actual_lines}"
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
