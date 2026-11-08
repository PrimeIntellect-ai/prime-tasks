#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import json
import os
import random
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = '/home/user/process_routes.py'
RESULTS_PATH = '/home/user/route_results.json'
DB_PATH = '/home/user/supply_chain.db'


def run_script():
    if os.path.exists(RESULTS_PATH):
        os.remove(RESULTS_PATH)
    subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        check=True,
        timeout=20,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
    )


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"Script file {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"Path {SCRIPT_PATH} is not a file."


def test_script_runs_successfully():
    run_script()


def test_results_file_exists():
    assert os.path.exists(RESULTS_PATH), f"Results file {RESULTS_PATH} does not exist."
    assert os.path.isfile(RESULTS_PATH), f"Path {RESULTS_PATH} is not a file."


def test_results_content():
    with open(RESULTS_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {RESULTS_PATH} does not contain valid JSON.")

    expected_data = [
        {
            "destination_id": 5,
            "destination_name": "Warehouse_D",
            "total_transit_time": 15
        },
        {
            "destination_id": 4,
            "destination_name": "Warehouse_C",
            "total_transit_time": 17
        },
        {
            "destination_id": 6,
            "destination_name": "Warehouse_E",
            "total_transit_time": 17
        }
    ]

    assert isinstance(data, list), "JSON root should be a list."
    assert len(data) == 3, f"Expected exactly 3 records, got {len(data)}."

    for i, expected_record in enumerate(expected_data):
        actual_record = data[i]
        assert isinstance(actual_record, dict), f"Record at index {i} is not a JSON object."

        expected_keys = {"destination_id", "destination_name", "total_transit_time"}
        actual_keys = set(actual_record.keys())
        assert actual_keys == expected_keys, f"Record at index {i} has incorrect keys. Expected {expected_keys}, got {actual_keys}."

        assert actual_record["destination_id"] == expected_record["destination_id"], \
            f"Record {i}: expected destination_id {expected_record['destination_id']}, got {actual_record['destination_id']}."
        assert actual_record["destination_name"] == expected_record["destination_name"], \
            f"Record {i}: expected destination_name '{expected_record['destination_name']}', got '{actual_record['destination_name']}'."
        assert actual_record["total_transit_time"] == expected_record["total_transit_time"], \
            f"Record {i}: expected total_transit_time {expected_record['total_transit_time']}, got {actual_record['total_transit_time']}."


def derive_expected(locations, links):
    source = next(loc_id for loc_id, name, _ in locations if name == 'Factory_Alpha')
    adjacency = {}
    for start, end, weight, is_open in links:
        if is_open:
            adjacency.setdefault(start, []).append((end, weight))

    distances = {source: 0}
    queue = [(0, source)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        for neighbor, weight in adjacency.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(neighbor, float('inf')):
                distances[neighbor] = candidate
                heapq.heappush(queue, (candidate, neighbor))

    records = [
        {
            'destination_id': loc_id,
            'destination_name': name,
            'total_transit_time': distances[loc_id],
        }
        for loc_id, name, loc_type in locations
        if loc_type == 'Warehouse' and loc_id in distances
    ]
    records.sort(key=lambda record: (record['total_transit_time'], record['destination_id']))
    return records[2:5]


def test_script_computes_results_from_database():
    fd, backup_path = tempfile.mkstemp(prefix='supply_chain_', suffix='.db')
    os.close(fd)
    shutil.copy2(DB_PATH, backup_path)

    rng = random.SystemRandom()
    ids = rng.sample(range(100, 10000), 10)
    source, crossdock = ids[:2]
    warehouses = ids[2:]
    token = uuid.uuid4().hex[:10]
    locations = [
        (source, 'Factory_Alpha', 'Factory'),
        (crossdock, f'CrossDock_{token}', 'CrossDock'),
    ] + [
        (loc_id, f'Warehouse_{token}_{index}', 'Warehouse')
        for index, loc_id in enumerate(warehouses)
    ]

    a = rng.randint(6, 14)
    x = rng.randint(2, 7)
    y = rng.randint(8, 15)
    z = rng.randint(3, 9)
    links = [
        (source, warehouses[0], a, 1),
        (source, warehouses[1], a, 1),
        (source, crossdock, x, 1),
        (crossdock, warehouses[2], y, 1),
        (warehouses[0], warehouses[3], z, 1),
        (warehouses[1], warehouses[4], z, 1),
        (source, warehouses[5], a + z + 25, 1),
        (crossdock, warehouses[5], y + 2, 1),
        (warehouses[2], warehouses[6], 4, 1),
        (source, warehouses[3], a + z + 20, 1),
        (source, warehouses[6], 1, 0),
        (crossdock, warehouses[4], 1, 0),
        # warehouses[7] is deliberately unreachable.
    ]
    expected = derive_expected(locations, links)

    try:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.execute('DELETE FROM links')
            conn.execute('DELETE FROM locations')
            conn.executemany('INSERT INTO locations VALUES (?, ?, ?)', locations)
            conn.executemany('INSERT INTO links VALUES (?, ?, ?, ?)', links)
            conn.commit()
        finally:
            conn.close()

        run_script()
        assert os.path.isfile(RESULTS_PATH), "Script did not create route_results.json."
        with open(RESULTS_PATH, 'r') as f:
            actual = json.load(f)

        assert actual == expected, \
            f"Script did not derive the paginated shortest routes from the modified database. Expected {expected}, got {actual}."
        for record in actual:
            assert set(record) == {"destination_id", "destination_name", "total_transit_time"}
            assert type(record["destination_id"]) is int
            assert type(record["destination_name"]) is str
            assert type(record["total_transit_time"]) is int
    finally:
        shutil.copy2(backup_path, DB_PATH)
        os.remove(backup_path)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
