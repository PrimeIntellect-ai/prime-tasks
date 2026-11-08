#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py
import os
import json
import sqlite3
import heapq
import pytest

DB_PATH = '/home/user/supply_chain.db'
OUTPUT_FILE = '/home/user/optimal_route.json'

def compute_expected_route(db_path, start_name, end_name):
    """
    Dynamically compute the expected shortest path from the database,
    excluding connections with an 'active' disruption.
    """
    if not os.path.exists(db_path):
        pytest.fail(f"Database file {db_path} is missing.")

    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    # Load facilities
    c.execute("SELECT id, name FROM facilities")
    facilities = {row[0]: row[1] for row in c.fetchall()}
    name_to_id = {v: k for k, v in facilities.items()}

    if start_name not in name_to_id or end_name not in name_to_id:
        pytest.fail("Start or end facility not found in the database.")

    # Load active disruptions
    c.execute("SELECT connection_id FROM disruptions WHERE status = 'active'")
    disrupted_conn_ids = {row[0] for row in c.fetchall()}

    # Load valid connections
    c.execute("SELECT rowid, source_id, dest_id, transit_time, cost FROM connections")
    graph = {fid: [] for fid in facilities}
    for rowid, source_id, dest_id, transit_time, cost in c.fetchall():
        if rowid not in disrupted_conn_ids:
            graph[source_id].append((dest_id, transit_time, cost))

    conn.close()

    # Dijkstra's algorithm prioritizing transit_time
    start_id = name_to_id[start_name]
    end_id = name_to_id[end_name]

    # Priority queue stores tuples of: (total_time, total_cost, current_node_id, path_of_ids)
    pq = [(0, 0, start_id, [start_id])]
    visited = set()

    while pq:
        time, cost, curr, path = heapq.heappop(pq)

        if curr == end_id:
            return {
                "total_transit_time": time,
                "total_cost": cost,
                "path": [facilities[node] for node in path]
            }

        if curr in visited:
            continue
        visited.add(curr)

        for neighbor, t_time, t_cost in graph[curr]:
            if neighbor not in visited:
                heapq.heappush(pq, (time + t_time, cost + t_cost, neighbor, path + [neighbor]))

    return None

def test_optimal_route_output():
    assert os.path.exists(OUTPUT_FILE), f"Output file {OUTPUT_FILE} was not created."

    with open(OUTPUT_FILE, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"Output file {OUTPUT_FILE} does not contain valid JSON.")

    expected_data = compute_expected_route(DB_PATH, 'Origin-Alpha', 'Dest-Omega')

    assert expected_data is not None, "Could not compute a valid path from the database."

    assert "total_transit_time" in actual_data, "Missing 'total_transit_time' in JSON output."
    assert "total_cost" in actual_data, "Missing 'total_cost' in JSON output."
    assert "path" in actual_data, "Missing 'path' in JSON output."

    assert actual_data["total_transit_time"] == expected_data["total_transit_time"], \
        f"Expected transit time {expected_data['total_transit_time']}, got {actual_data['total_transit_time']}."

    assert actual_data["total_cost"] == expected_data["total_cost"], \
        f"Expected total cost {expected_data['total_cost']}, got {actual_data['total_cost']}."

    assert actual_data["path"] == expected_data["path"], \
        f"Expected path {expected_data['path']}, got {actual_data['path']}."
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
