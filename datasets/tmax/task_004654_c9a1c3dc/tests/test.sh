#!/bin/bash
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import heapq
import importlib.util
import inspect
import json
import os
import random
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

SCRIPT_PATH = '/home/user/route_solver.py'
JSON_PATH = '/home/user/shortest_path.json'
DB_PATH = '/home/user/logistics.db'


def run_solver():
    assert os.path.isfile(SCRIPT_PATH), f"Solver script {SCRIPT_PATH} is missing."
    result = subprocess.run(
        ['python3', SCRIPT_PATH],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
    )
    assert result.returncode == 0, (
        f"route_solver.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_output():
    assert os.path.isfile(JSON_PATH), f"JSON output file {JSON_PATH} is missing."
    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {JSON_PATH} is not a valid JSON.")

    assert isinstance(data, dict), f"JSON root must be a dictionary, got {type(data)}."
    assert "path" in data, "JSON must contain the key 'path'."
    assert "total_distance" in data, "JSON must contain the key 'total_distance'."
    return data


def install_database(locations, connections):
    for suffix in ('', '-wal', '-shm'):
        try:
            os.remove(DB_PATH + suffix)
        except FileNotFoundError:
            pass

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE locations (id INTEGER PRIMARY KEY, name TEXT)')
        conn.execute('CREATE TABLE connections (id INTEGER PRIMARY KEY, loc1_id INTEGER, loc2_id INTEGER, distance_km INTEGER, active INTEGER)')
        conn.executemany('INSERT INTO locations VALUES (?, ?)', locations)
        conn.executemany('INSERT INTO connections VALUES (?, ?, ?, ?, ?)', connections)
        conn.commit()
    finally:
        conn.close()


def expected_routes(locations, connections):
    names = {loc_id: name for loc_id, name in locations}
    return [
        (names[loc1], names[loc2], distance)
        for _, loc1, loc2, distance, active in connections
        if active == 1
    ]


def shortest_path(locations, connections):
    names = {loc_id: name for loc_id, name in locations}
    graph = {}
    for _, loc1, loc2, distance, active in connections:
        if active == 1:
            graph.setdefault(names[loc1], []).append((names[loc2], distance))

    queue = [(0, ['Alpha'], 'Alpha')]
    best = {'Alpha': 0}
    while queue:
        distance, path, node = heapq.heappop(queue)
        if distance != best.get(node):
            continue
        if node == 'Omega':
            return path, distance
        for neighbor, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < best.get(neighbor, float('inf')):
                best[neighbor] = candidate
                heapq.heappush(queue, (candidate, path + [neighbor], neighbor))
    raise AssertionError('Generated verification graph has no Alpha-to-Omega path.')


def load_solver_module():
    module_name = 'submitted_route_solver_' + uuid.uuid4().hex
    spec = importlib.util.spec_from_file_location(module_name, SCRIPT_PATH)
    assert spec is not None and spec.loader is not None, 'Unable to import route_solver.py.'
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    assert callable(getattr(module, 'get_routes', None)), 'route_solver.py must define get_routes(db_path).'
    return module


def test_final_state():
    assert os.path.isfile(DB_PATH), f"Database {DB_PATH} is missing."
    assert os.path.isfile(SCRIPT_PATH), f"Solver script {SCRIPT_PATH} is missing."

    with tempfile.TemporaryDirectory() as backup_dir:
        db_backup = os.path.join(backup_dir, 'logistics.db')
        json_backup = os.path.join(backup_dir, 'shortest_path.json')
        shutil.copy2(DB_PATH, db_backup)
        had_json = os.path.isfile(JSON_PATH)
        if had_json:
            shutil.copy2(JSON_PATH, json_backup)

        baseline_output = None
        try:
            # The required output must be produced by executing the submitted artifact.
            try:
                os.remove(JSON_PATH)
            except FileNotFoundError:
                pass
            run_solver()
            data = load_output()

            # Preserve the original verifier's assertions.
            expected_path = ["Alpha", "Delta", "Omega"]
            expected_distance = 55
            assert data["path"] == expected_path, f"Expected path {expected_path}, but got {data['path']}."
            assert data["total_distance"] == expected_distance, f"Expected total_distance {expected_distance}, but got {data['total_distance']}."
            with open(JSON_PATH, 'rb') as f:
                baseline_output = f.read()

            # Restore the original DB in case execution changed it, then inspect and
            # exercise get_routes itself to verify the SQL join behavior.
            shutil.copy2(db_backup, DB_PATH)
            solver = load_solver_module()
            source = inspect.getsource(solver.get_routes)
            assert len(re.findall(r'\bJOIN\b', source, flags=re.IGNORECASE)) >= 2, (
                'get_routes must use explicit JOINs to map both source and destination locations.'
            )

            original_locations = [
                (1, 'Alpha'), (2, 'Beta'), (3, 'Gamma'),
                (4, 'Delta'), (5, 'Omega')
            ]
            original_connections = [
                (1, 1, 2, 10, 1), (2, 2, 3, 20, 1),
                (3, 3, 5, 30, 1), (4, 1, 4, 50, 1),
                (5, 4, 5, 5, 1), (6, 1, 5, 100, 1),
                (7, 2, 4, 5, 0)
            ]
            assert sorted(solver.get_routes(DB_PATH)) == sorted(expected_routes(original_locations, original_connections)), (
                'get_routes returned rows that do not match the active directed connections.'
            )

            # Exercise traversal and export on fresh graphs whose answers are
            # independently derived by the verifier.
            rng = random.Random(os.urandom(32))
            for _ in range(2):
                tag = uuid.uuid4().hex[:10]
                x_name = 'X_' + tag
                y_name = 'Y_' + tag
                locations = [
                    (1, 'Alpha'), (2, x_name), (3, y_name), (4, 'Omega')
                ]
                w1 = rng.randint(4, 20)
                w2 = rng.randint(4, 20)
                target = w1 + w2
                connections = [
                    (1, 1, 2, w1, 1),
                    (2, 2, 4, w2, 1),
                    (3, 1, 3, target + 10, 1),
                    (4, 3, 4, 3, 1),
                    (5, 1, 4, target + 30, 1),
                    (6, 1, 4, 1, 0),       # Inactive shortcut must be ignored.
                    (7, 4, 1, 1, 1),       # Reverse edge must not be traversed forward.
                    (8, 1, 2, w1 + 20, 1), # Parallel but more expensive edge.
                ]
                install_database(locations, connections)

                actual_routes = solver.get_routes(DB_PATH)
                assert sorted(actual_routes) == sorted(expected_routes(locations, connections)), (
                    'get_routes must return exactly the active, correctly joined directed connections.'
                )

                try:
                    os.remove(JSON_PATH)
                except FileNotFoundError:
                    pass
                run_solver()
                dynamic_data = load_output()
                expected_dynamic_path, expected_dynamic_distance = shortest_path(locations, connections)
                assert dynamic_data['path'] == expected_dynamic_path, (
                    f"Expected path {expected_dynamic_path}, but got {dynamic_data['path']}."
                )
                assert dynamic_data['total_distance'] == expected_dynamic_distance, (
                    f"Expected total_distance {expected_dynamic_distance}, but got {dynamic_data['total_distance']}."
                )
        finally:
            for suffix in ('', '-wal', '-shm'):
                try:
                    os.remove(DB_PATH + suffix)
                except FileNotFoundError:
                    pass
            shutil.copy2(db_backup, DB_PATH)
            if baseline_output is not None:
                with open(JSON_PATH, 'wb') as f:
                    f.write(baseline_output)
            elif had_json:
                shutil.copy2(json_backup, JSON_PATH)
            else:
                try:
                    os.remove(JSON_PATH)
                except FileNotFoundError:
                    pass
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
