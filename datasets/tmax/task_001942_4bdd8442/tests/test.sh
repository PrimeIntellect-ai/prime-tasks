#!/bin/bash
set -e
mkdir -p /logs/verifier

cp -p /home/user/network.db /tmp/network.db.verifier_backup
cp -p /app/link_cost_oracle /tmp/link_cost_oracle.verifier_backup

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import os
import random
import sqlite3
import subprocess
import uuid

import pytest
import requests

BASE_URL = "http://127.0.0.1:9000"
AUTH_HEADER = {"Authorization": "Bearer ADMIN_TOKEN_99"}
DB_PATH = "/home/user/network.db"
ORACLE_PATH = "/app/link_cost_oracle"


def get_oracle_cost(src: int, dst: int) -> int:
    result = subprocess.run(
        [ORACLE_PATH, str(src), str(dst)],
        capture_output=True,
        text=True,
        check=True,
    )
    return int(result.stdout.strip())


def compute_shortest_path(start: int, end: int):
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT source_id, target_id FROM links")
    links = cursor.fetchall()
    conn.close()

    graph = {}
    for u, v in links:
        graph.setdefault(u, []).append(v)

    pq = [(0, start, [start])]
    visited = set()
    while pq:
        cost, current, path = heapq.heappop(pq)
        if current == end:
            return path, cost
        if current in visited:
            continue
        visited.add(current)
        for neighbor in graph.get(current, []):
            if neighbor not in visited:
                edge_cost = get_oracle_cost(current, neighbor)
                heapq.heappush(pq, (cost + edge_cost, neighbor, path + [neighbor]))
    return None, None


def test_auth_missing():
    response = requests.get(f"{BASE_URL}/routers?tier=edge&limit=1&offset=0")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_auth_invalid():
    response = requests.get(
        f"{BASE_URL}/routers?tier=edge&limit=1&offset=0",
        headers={"Authorization": "Bearer WRONG_TOKEN"},
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_routers_endpoint():
    response = requests.get(
        f"{BASE_URL}/routers?tier=edge&limit=1&offset=1", headers=AUTH_HEADER
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

    data = response.json()
    assert "data" in data, "Response missing 'data' key"
    assert len(data["data"]) == 1, "Expected exactly 1 router in data"

    router = data["data"][0]
    assert router["id"] == 5, f"Expected router ID 5, got {router.get('id')}"
    assert router["name"] == "edge-1", f"Expected router name 'edge-1', got {router.get('name')}"
    assert router["tier"] == "edge", f"Expected router tier 'edge', got {router.get('tier')}"


def test_route_endpoint_success():
    start_id = 1
    end_id = 6
    expected_path, expected_cost = compute_shortest_path(start_id, end_id)
    assert expected_path is not None, "Test setup error: no path exists in DB"

    response = requests.get(
        f"{BASE_URL}/route?start={start_id}&end={end_id}", headers=AUTH_HEADER
    )
    assert response.status_code == 200, f"Expected 200 OK, got {response.status_code}"

    data = response.json()
    assert "path" in data, "Response missing 'path' key"
    assert "total_cost" in data, "Response missing 'total_cost' key"
    assert data["path"] == expected_path, f"Expected path {expected_path}, got {data['path']}"
    assert data["total_cost"] == expected_cost, f"Expected cost {expected_cost}, got {data['total_cost']}"


def test_route_endpoint_not_found():
    response = requests.get(f"{BASE_URL}/route?start=1&end=999", headers=AUTH_HEADER)
    assert response.status_code == 404, f"Expected 404 Not Found, got {response.status_code}"
    data = response.json()
    assert "error" in data, "Response missing 'error' key"


def test_route_authentication():
    response = requests.get(f"{BASE_URL}/route?start=1&end=6")
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"

    response = requests.get(
        f"{BASE_URL}/route?start=1&end=6",
        headers={"Authorization": "Bearer WRONG_TOKEN"},
    )
    assert response.status_code == 401, f"Expected 401 Unauthorized, got {response.status_code}"


def test_zz_dynamic_database_and_oracle_behavior():
    rng = random.SystemRandom()
    nonce = uuid.uuid4().hex
    tier = f"verify-{nonce}"

    conn = sqlite3.connect(DB_PATH)
    existing = {row[0] for row in conn.execute("SELECT id FROM routers")}
    while True:
        base = rng.randrange(100000, 900000)
        ids = [base, base + 1, base + 2, base + 3]
        if not any(node in existing for node in ids):
            break
    a, b, c, d = ids

    rows = [
        (a, f"node-a-{nonce}", tier),
        (b, f"node-b-{nonce}", tier),
        (c, f"node-c-{nonce}", tier),
        (d, f"node-d-{nonce}", tier),
    ]
    conn.executemany("INSERT INTO routers(id, name, tier) VALUES (?, ?, ?)", rows)
    conn.executemany(
        "INSERT INTO links(source_id, target_id) VALUES (?, ?)",
        [(a, b), (a, c), (b, d), (c, d)],
    )
    conn.commit()
    conn.close()

    expected_desc = [
        {"id": node_id, "name": name, "tier": row_tier}
        for node_id, name, row_tier in sorted(rows, key=lambda row: row[0], reverse=True)
    ]
    for limit, offset in [(10, 0), (2, 1), (1, 3), (3, 4)]:
        response = requests.get(
            f"{BASE_URL}/routers",
            params={"tier": tier, "limit": limit, "offset": offset},
            headers=AUTH_HEADER,
        )
        assert response.status_code == 200, response.text
        assert response.json() == {"data": expected_desc[offset:offset + limit]}

    while True:
        coef_a = rng.randrange(1, 1_000_000_000)
        coef_b = rng.randrange(1, 1_000_000_000)
        coef_c = rng.randrange(1, 1_000_000_000)

        def dynamic_cost(src, dst):
            return ((src * coef_a + dst * coef_b + coef_c) % 97) + 1

        via_b = dynamic_cost(a, b) + dynamic_cost(b, d)
        via_c = dynamic_cost(a, c) + dynamic_cost(c, d)
        if via_b != via_c:
            break

    call_log = f"/tmp/oracle_calls_{nonce}"
    wrapper = f'''#!/usr/bin/env python3
import sys
src = int(sys.argv[1])
dst = int(sys.argv[2])
with open({call_log!r}, "a") as fh:
    fh.write(f"{{src}} {{dst}}\\n")
print(((src * {coef_a} + dst * {coef_b} + {coef_c}) % 97) + 1)
'''
    replacement = f"/tmp/link_cost_oracle_{nonce}"
    with open(replacement, "w") as fh:
        fh.write(wrapper)
    os.chmod(replacement, 0o755)
    os.replace(replacement, ORACLE_PATH)

    if os.path.exists(call_log):
        os.unlink(call_log)

    if via_b < via_c:
        expected_path = [a, b, d]
        expected_cost = via_b
    else:
        expected_path = [a, c, d]
        expected_cost = via_c

    response = requests.get(
        f"{BASE_URL}/route", params={"start": a, "end": d}, headers=AUTH_HEADER
    )
    assert response.status_code == 200, response.text
    assert response.json() == {"path": expected_path, "total_cost": expected_cost}

    assert os.path.exists(call_log), "The API did not invoke /app/link_cost_oracle"
    with open(call_log) as fh:
        calls = {tuple(map(int, line.split())) for line in fh if line.strip()}
    expected_path_edges = set(zip(expected_path, expected_path[1:]))
    assert expected_path_edges.issubset(calls), (
        f"Oracle was not invoked for path edges {expected_path_edges}; calls were {calls}"
    )

    for start, end, path in [
        (a, b, [a, b]),
        (a, c, [a, c]),
        (b, d, [b, d]),
        (c, d, [c, d]),
    ]:
        response = requests.get(
            f"{BASE_URL}/route",
            params={"start": start, "end": end},
            headers=AUTH_HEADER,
        )
        assert response.status_code == 200, response.text
        expected = sum(dynamic_cost(x, y) for x, y in zip(path, path[1:]))
        assert response.json() == {"path": path, "total_cost": expected}

    response = requests.get(
        f"{BASE_URL}/route", params={"start": d, "end": a}, headers=AUTH_HEADER
    )
    assert response.status_code == 404, response.text
    assert response.json() == {"error": "No path found"}
TEST_EOF

set +e
python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
status=$?
set -e

cp -p /tmp/network.db.verifier_backup /home/user/network.db
cp -p /tmp/link_cost_oracle.verifier_backup /app/link_cost_oracle

if [ "$status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
