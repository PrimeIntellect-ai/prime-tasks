#!/bin/bash
set -e
mkdir -p /logs/verifier
mkdir -p /tmp/verifier_hook

cat << 'HOOK_EOF' > /tmp/verifier_hook/sitecustomize.py
import json
import os
import sqlite3

_original_connect = sqlite3.connect

def _traced_connect(*args, **kwargs):
    conn = _original_connect(*args, **kwargs)
    trace_path = os.environ.get('VERIFIER_SQL_TRACE')
    if trace_path:
        def record(statement):
            try:
                with open(trace_path, 'a', encoding='utf-8') as f:
                    f.write(json.dumps(statement) + '\n')
            except Exception:
                pass
        conn.set_trace_callback(record)
    return conn

sqlite3.connect = _traced_connect
HOOK_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import secrets
import sqlite3
import subprocess

import pytest

DB_PATH = '/home/user/components.db'
JSON_PATH = '/home/user/summary.json'
SCRIPT_PATH = '/home/user/optimize_and_export.py'
TRACE_PATH = '/tmp/optimize_sql_trace.jsonl'


def run_submission():
    assert os.path.exists(SCRIPT_PATH), f"Required script {SCRIPT_PATH} does not exist."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    if os.path.exists(TRACE_PATH):
        os.remove(TRACE_PATH)

    env = os.environ.copy()
    old_pythonpath = env.get('PYTHONPATH')
    env['PYTHONPATH'] = '/tmp/verifier_hook' + (os.pathsep + old_pythonpath if old_pythonpath else '')
    env['VERIFIER_SQL_TRACE'] = TRACE_PATH

    try:
        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            env=env,
            text=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            timeout=20,
        )
    except subprocess.TimeoutExpired:
        pytest.fail(f"{SCRIPT_PATH} did not finish within 20 seconds.")

    assert result.returncode == 0, (
        f"{SCRIPT_PATH} exited with status {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )


def load_summary():
    assert os.path.exists(JSON_PATH), f"Output file {JSON_PATH} does not exist."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."
    with open(JSON_PATH, 'r', encoding='utf-8') as f:
        try:
            return json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_PATH} does not contain valid JSON.")


def traced_statements():
    assert os.path.isfile(TRACE_PATH), "The script did not make a traced SQLite connection."
    statements = []
    with open(TRACE_PATH, 'r', encoding='utf-8') as f:
        for line in f:
            if line.strip():
                statements.append(json.loads(line))
    return statements


def without_sql_comments(sql):
    sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.S)
    sql = re.sub(r'--[^\n\r]*', ' ', sql)
    return sql.strip()


def assert_recursive_aggregate_query_was_executed():
    recursive = []
    for statement in traced_statements():
        cleaned = without_sql_comments(statement)
        if re.match(r'^WITH\s+RECURSIVE\b', cleaned, flags=re.I):
            recursive.append(cleaned)

    assert len(recursive) == 1, (
        "The script must execute exactly one SQL query beginning with WITH RECURSIVE; "
        f"observed {len(recursive)}."
    )
    query = recursive[0]
    required_patterns = {
        'edges table': r'\bedges\b',
        'nodes table': r'\bnodes\b',
        'source traversal column': r'\bsource\b',
        'target traversal column': r'\btarget\b',
        'recursive UNION': r'\bUNION(?:\s+ALL)?\b',
        'SUM aggregation': r'\bSUM\s*\(',
        'COUNT aggregation': r'\bCOUNT\s*\(',
        'GROUP BY aggregation': r'\bGROUP\s+BY\b',
    }
    for description, pattern in required_patterns.items():
        assert re.search(pattern, query, flags=re.I), (
            f"Executed recursive query is missing {description}."
        )
    assert 'ROOT_01' in query, "Executed recursive query does not start from ROOT_01."


def assert_source_index_exact():
    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = conn.execute("PRAGMA index_list('edges')").fetchall()
        covering = []
        for row in indexes:
            name = row[1]
            columns = [r[2].lower() for r in conn.execute(
                f"PRAGMA index_info({json.dumps(name)})"
            ).fetchall()]
            if columns and columns[0] == 'source':
                covering.append((name, columns))
        assert covering, "No index on edges with source as its leading column was created."
    finally:
        conn.close()


def test_01_script_executes_on_original_database():
    run_submission()


def test_02_summary_json_exists_and_correct():
    data = load_summary()

    assert "total_downstream_nodes" in data, "Missing 'total_downstream_nodes' in JSON."
    assert data["total_downstream_nodes"] == 5, f"Expected 5 total downstream nodes, got {data['total_downstream_nodes']}."

    assert "cost_by_type" in data, "Missing 'cost_by_type' in JSON."
    cost_by_type = data["cost_by_type"]

    assert "library" in cost_by_type, "Missing 'library' type in cost_by_type."
    assert "service" in cost_by_type, "Missing 'service' type in cost_by_type."

    assert cost_by_type["library"] == 25.5, f"Expected library cost 25.5, got {cost_by_type['library']}."
    assert cost_by_type["service"] == 105.0, f"Expected service cost 105.0, got {cost_by_type['service']}."


def test_03_index_created_on_edges():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} does not exist."

    conn = sqlite3.connect(DB_PATH)
    c = conn.cursor()
    c.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='edges'")
    indexes = c.fetchall()

    valid_index_found = False
    for name, sql in indexes:
        if sql and 'source' in sql.lower():
            valid_index_found = True
            break

    conn.close()
    assert valid_index_found, "No optimal index found on the 'edges' table covering the 'source' column."
    assert_source_index_exact()


def test_04_single_recursive_aggregate_query_executed():
    assert_recursive_aggregate_query_was_executed()


def test_05_script_handles_fresh_unpredictable_graph():
    token = secrets.token_hex(5)
    ids = {name: f"{name}_{token}" for name in ['A', 'B', 'C', 'D', 'E', 'ORPHAN']}
    type_one = f"library_{secrets.token_hex(3)}"
    type_two = f"service_{secrets.token_hex(3)}"
    costs = [float(secrets.randbelow(700) + 1) / 10.0 for _ in range(5)]

    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE nodes(id TEXT PRIMARY KEY, type TEXT, cost REAL)')
        conn.execute('CREATE TABLE edges(source TEXT, target TEXT)')
        nodes = [
            ('ROOT_01', f'root_{token}', 98765.0),
            (ids['A'], type_one, costs[0]),
            (ids['B'], type_two, costs[1]),
            (ids['C'], type_one, costs[2]),
            (ids['D'], type_two, costs[3]),
            (ids['E'], type_two, costs[4]),
            (ids['ORPHAN'], type_one, 54321.0),
        ]
        edges = [
            ('ROOT_01', ids['A']),
            ('ROOT_01', ids['B']),
            (ids['A'], ids['C']),
            (ids['B'], ids['C']),
            (ids['C'], ids['D']),
            (ids['B'], ids['E']),
        ]
        conn.executemany('INSERT INTO nodes VALUES (?,?,?)', nodes)
        conn.executemany('INSERT INTO edges VALUES (?,?)', edges)
        conn.commit()

        adjacency = {}
        for source, target in conn.execute('SELECT source, target FROM edges'):
            adjacency.setdefault(source, []).append(target)
        discovered = set()
        pending = list(adjacency.get('ROOT_01', []))
        while pending:
            node = pending.pop()
            if node in discovered or node == 'ROOT_01':
                continue
            discovered.add(node)
            pending.extend(adjacency.get(node, []))

        expected_costs = {}
        placeholders = ','.join('?' for _ in discovered)
        for node_type, cost in conn.execute(
            f'SELECT type, cost FROM nodes WHERE id IN ({placeholders})', tuple(discovered)
        ):
            expected_costs[node_type] = expected_costs.get(node_type, 0.0) + cost
    finally:
        conn.close()

    run_submission()
    data = load_summary()
    assert set(data.keys()) == {'total_downstream_nodes', 'cost_by_type'}, "JSON does not have the required exact top-level structure."
    assert data['total_downstream_nodes'] == len(discovered)
    assert set(data['cost_by_type']) == set(expected_costs)
    for node_type, expected_cost in expected_costs.items():
        assert data['cost_by_type'][node_type] == pytest.approx(expected_cost)

    assert_source_index_exact()
    assert_recursive_aggregate_query_was_executed()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
