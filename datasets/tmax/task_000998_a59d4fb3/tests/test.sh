#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import heapq
import itertools
import os
import secrets
import sqlite3
import subprocess
import sys
from collections import Counter

HOME = '/home/user'
STATIONS = os.path.join(HOME, 'stations.csv')
ROUTES = os.path.join(HOME, 'routes.csv')
DB = os.path.join(HOME, 'network.db')
SOLUTION = os.path.join(HOME, 'solution.txt')
SCHEMA = os.path.join(HOME, 'schema.sql')
SETUP = os.path.join(HOME, 'setup_db.py')
SHORTEST = os.path.join(HOME, 'shortest_path.py')


def quote_ident(value):
    return '"' + value.replace('"', '""') + '"'


def read_csv(path):
    with open(path, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames, f'{path} has no header'
        return reader.fieldnames, list(reader)


def run_artifacts():
    assert os.path.isfile(SETUP), f'Expected setup script {SETUP} does not exist.'
    assert os.path.isfile(SHORTEST), f'Expected shortest-path script {SHORTEST} does not exist.'
    if os.path.exists(DB):
        os.remove(DB)
    if os.path.exists(SOLUTION):
        os.remove(SOLUTION)
    subprocess.run([sys.executable, SETUP], cwd=HOME, check=True, timeout=30)
    assert os.path.isfile(DB), f'Expected database file {DB} does not exist.'
    subprocess.run([sys.executable, SHORTEST], cwd=HOME, check=True, timeout=30)
    assert os.path.isfile(SOLUTION), f'Expected solution file {SOLUTION} does not exist.'


def find_loaded_table(conn, csv_path):
    headers, source_rows = read_csv(csv_path)
    expected = Counter(tuple(row[h] for h in headers) for row in source_rows)
    tables = [r[0] for r in conn.execute(
        "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
    )]
    for table in tables:
        info = conn.execute(f'PRAGMA table_info({quote_ident(table)})').fetchall()
        columns = [r[1] for r in info]
        if len(columns) < len(headers):
            continue
        for selected in itertools.permutations(columns, len(headers)):
            query = 'SELECT ' + ','.join(quote_ident(c) for c in selected)
            query += ' FROM ' + quote_ident(table)
            actual = Counter(tuple('' if v is None else str(v) for v in row)
                             for row in conn.execute(query))
            if actual == expected:
                return table, dict(zip(headers, selected))
    raise AssertionError(f'No database table accurately contains all rows and columns from {csv_path}')


def assert_database_matches_csvs():
    try:
        conn = sqlite3.connect(DB)
        tables = conn.execute("SELECT name FROM sqlite_master WHERE type='table';").fetchall()
        assert len(tables) > 0, f'Expected at least one table in the database {DB}.'
        find_loaded_table(conn, STATIONS)
        route_table, route_columns = find_loaded_table(conn, ROUTES)

        src = route_columns['src_node'].lower()
        dst = route_columns['dst_node'].lower()
        status = route_columns['op_status'].lower()
        outgoing = set()
        incoming = set()
        for row in conn.execute(f'PRAGMA index_list({quote_ident(route_table)})'):
            index_name = row[1]
            cols = [r[2].lower() for r in conn.execute(
                f'PRAGMA index_info({quote_ident(index_name)})'
            ) if r[2] is not None]
            sql_row = conn.execute(
                "SELECT sql FROM sqlite_master WHERE type='index' AND name=?", (index_name,)
            ).fetchone()
            sql = (sql_row[0] or '').lower() if sql_row else ''
            partial_active = (' where ' in sql and status in sql and 'active' in sql)

            def optimized_for(node):
                if partial_active and cols and cols[0] == node:
                    return True
                return len(cols) >= 2 and set(cols[:2]) == {node, status}

            if optimized_for(src):
                outgoing.add(index_name)
            if optimized_for(dst):
                incoming.add(index_name)

        assert outgoing, 'Database lacks an actual index optimized for outgoing active routes.'
        assert incoming, 'Database lacks an actual index optimized for incoming active routes.'
        assert any(a != b for a in outgoing for b in incoming), (
            'Expected distinct outgoing-active and incoming-active route indexes.'
        )
    except sqlite3.Error as e:
        raise AssertionError(f'Failed to validate SQLite database at {DB}: {e}')
    finally:
        if 'conn' in locals():
            conn.close()


def expected_shortest_path():
    _, stations = read_csv(STATIONS)
    _, routes = read_csv(ROUTES)
    name_to_id = {row['s_name']: row['s_id'] for row in stations}
    start = name_to_id['Alpha Hub']
    target = name_to_id['Omega Terminus']
    graph = {}
    for row in routes:
        if row['op_status'].strip().upper() != 'ACTIVE':
            continue
        weight = int(row['travel_time'])
        graph.setdefault(row['src_node'], []).append((row['dst_node'], weight))

    distances = {start: 0}
    queue = [(0, start)]
    while queue:
        distance, node = heapq.heappop(queue)
        if distance != distances[node]:
            continue
        for neighbor, weight in graph.get(node, []):
            candidate = distance + weight
            if candidate < distances.get(neighbor, float('inf')):
                distances[neighbor] = candidate
                heapq.heappush(queue, (candidate, neighbor))
    assert target in distances, 'The CSV test network unexpectedly has no active path.'
    return start, target, distances[target], graph


def assert_solution_is_derived():
    with open(SOLUTION) as f:
        raw_lines = f.readlines()
    lines = [line.strip() for line in raw_lines if line.strip()]
    assert len(lines) == 2, f'Expected exactly 2 lines in {SOLUTION}, found {len(lines)}.'
    try:
        reported_time = int(lines[0])
    except ValueError:
        raise AssertionError(f'First solution line is not an integer: {lines[0]!r}')
    path = lines[1].split(',')
    assert path and all(part and part == part.strip() for part in path), 'Invalid station ID path format.'

    start, target, minimum, graph = expected_shortest_path()
    assert path[0] == start, 'Path does not start at Alpha Hub.'
    assert path[-1] == target, 'Path does not end at Omega Terminus.'
    total = 0
    for source, destination in zip(path, path[1:]):
        weights = [weight for neighbor, weight in graph.get(source, []) if neighbor == destination]
        assert weights, f'Path uses missing or inactive route {source}->{destination}.'
        total += min(weights)
    assert reported_time == total, 'Reported transit time does not equal the active routes in the path.'
    assert reported_time == minimum, 'Reported path is not a minimum-transit-time active path.'


def write_random_variant():
    ids = [str(x) for x in secrets.SystemRandom().sample(range(1000, 9000), 5)]
    weights = [secrets.randbelow(18) + 2 for _ in range(6)]
    with open(STATIONS, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['s_id', 's_name', 'zone'])
        writer.writerows([
            [ids[0], 'Alpha Hub', 'North'],
            [ids[1], 'Beta Station', 'North'],
            [ids[2], 'Gamma Relay', 'East'],
            [ids[3], 'Delta Point', 'South'],
            [ids[4], 'Omega Terminus', 'West'],
        ])
    with open(ROUTES, 'w', newline='') as f:
        writer = csv.writer(f)
        writer.writerow(['r_id', 'src_node', 'dst_node', 'travel_time', 'op_status'])
        writer.writerows([
            [901, ids[0], ids[1], weights[0], 'ACTIVE'],
            [902, ids[1], ids[3], weights[1], 'ACTIVE'],
            [903, ids[3], ids[4], weights[2], 'ACTIVE'],
            [904, ids[0], ids[2], weights[3], 'ACTIVE'],
            [905, ids[2], ids[4], weights[4], 'ACTIVE'],
            [906, ids[2], ids[3], weights[5], 'ACTIVE'],
            [907, ids[0], ids[4], 1, 'INACTIVE'],
        ])


def test_complete_task():
    originals = {}
    for path in (STATIONS, ROUTES):
        with open(path, 'rb') as f:
            originals[path] = f.read()
    try:
        run_artifacts()

        # Preserve the original verifier's assertions.
        with open(SOLUTION) as f:
            lines = [line.strip() for line in f.readlines() if line.strip()]
        assert len(lines) == 2, f'Expected exactly 2 lines in {SOLUTION}, found {len(lines)}.'
        assert lines[0] == '30', f"Expected total transit time to be '30', got '{lines[0]}'."
        assert lines[1] == '1,3,4,5', f"Expected path to be '1,3,4,5', got '{lines[1]}'."

        assert os.path.isfile(SCHEMA), f'Expected schema file {SCHEMA} does not exist.'
        with open(SCHEMA) as f:
            schema_content = f.read().upper()
        index_count = schema_content.count('CREATE INDEX')
        assert index_count >= 2, f'Expected at least 2 CREATE INDEX statements in {SCHEMA}, found {index_count}.'
        assert 'CREATE TABLE' in schema_content, f'Expected CREATE TABLE statements in {SCHEMA}.'

        assert_database_matches_csvs()
        assert_solution_is_derived()

        # Exercise both scripts on an unpredictable second network so fixed answers cannot pass.
        write_random_variant()
        run_artifacts()
        assert_database_matches_csvs()
        assert_solution_is_derived()
    finally:
        for path, data in originals.items():
            with open(path, 'wb') as f:
                f.write(data)
        # Restore the requested final artifacts for the original supplied CSV files.
        try:
            run_artifacts()
        except Exception:
            pass
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
