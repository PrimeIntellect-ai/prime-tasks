#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import re
import secrets
import sqlite3
import stat
import subprocess
import sys

import pytest

SCRIPT = '/home/user/etl_graph.py'
RAW = '/home/user/raw_pipeline_data.json'
DB = '/home/user/pipeline.db'
RESULT = '/home/user/result.txt'


def _resolved_strings(tree):
    values = {}

    def resolve(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name):
            return values.get(node.id)
        if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
            left, right = resolve(node.left), resolve(node.right)
            if left is not None and right is not None:
                return left + right
        if isinstance(node, ast.JoinedStr):
            parts = []
            for part in node.values:
                if isinstance(part, ast.Constant) and isinstance(part.value, str):
                    parts.append(part.value)
                else:
                    return None
            return ''.join(parts)
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute) and node.args:
            if node.func.attr in {'strip', 'lstrip', 'rstrip'}:
                return resolve(node.func.value)
        return None

    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = resolve(node.value)
            if value is None:
                continue
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    values[target.id] = value

    return resolve


def _check_script_source():
    assert os.path.exists(SCRIPT), f'Expected Python script at {SCRIPT} does not exist.'
    mode = os.lstat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} must be a regular file.'

    with open(SCRIPT, 'r', encoding='utf-8') as f:
        source = f.read()
    assert source.strip(), f'{SCRIPT} is empty.'

    try:
        tree = ast.parse(source, filename=SCRIPT)
    except SyntaxError as exc:
        pytest.fail(f'{SCRIPT} is not valid Python: {exc}')

    resolve = _resolved_strings(tree)
    sql_calls = []
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in {'execute', 'executemany'} or not node.args:
            continue
        query = resolve(node.args[0])
        if query is not None:
            sql_calls.append((node, query))

    def has_parameter_marker(sql):
        return bool(re.search(r'\?|[:@$][A-Za-z_][A-Za-z0-9_]*', sql))

    def supplies_parameters(call):
        return len(call.args) >= 2 or any(
            kw.arg in {'parameters', 'params'} for kw in call.keywords if kw.arg
        )

    recursive_calls = [
        (call, sql) for call, sql in sql_calls
        if re.search(r'\bWITH\s+RECURSIVE\b', sql, re.IGNORECASE)
    ]
    assert len(recursive_calls) == 1, (
        'The script must execute a single recursive CTE for the downstream graph query.'
    )
    recursive_call, recursive_sql = recursive_calls[0]
    assert has_parameter_marker(recursive_sql) and supplies_parameters(recursive_call), (
        'The recursive CTE must be executed with a SQL parameter for the starting job.'
    )

    for table in ('nodes', 'edges'):
        pattern = re.compile(
            r'\bINSERT\s+(?:OR\s+\w+\s+)?INTO\s+["`\[]?' + table + r'\b',
            re.IGNORECASE,
        )
        matching = [(call, sql) for call, sql in sql_calls if pattern.search(sql)]
        assert matching, f'The script must insert data into {table}.'
        assert any(has_parameter_marker(sql) and supplies_parameters(call)
                   for call, sql in matching), (
            f'Loading into {table} must use parameterized SQL.'
        )


def _run_script(trace_path):
    runner = r'''
import json
import runpy
import sqlite3
import sys

script, trace_path = sys.argv[1], sys.argv[2]
statements = []
original_connect = sqlite3.connect

def traced_connect(*args, **kwargs):
    connection = original_connect(*args, **kwargs)
    connection.set_trace_callback(statements.append)
    return connection

sqlite3.connect = traced_connect
try:
    runpy.run_path(script, run_name='__main__')
finally:
    with open(trace_path, 'w', encoding='utf-8') as f:
        json.dump(statements, f)
'''
    proc = subprocess.run(
        [sys.executable, '-c', runner, SCRIPT, trace_path],
        cwd='/home/user', text=True, capture_output=True, timeout=30,
    )
    assert proc.returncode == 0, (
        f'etl_graph.py failed with exit code {proc.returncode}.\n'
        f'stdout:\n{proc.stdout}\nstderr:\n{proc.stderr}'
    )
    assert os.path.isfile(trace_path), 'Could not collect the script SQL trace.'
    with open(trace_path, 'r', encoding='utf-8') as f:
        statements = json.load(f)
    assert any(re.search(r'\bWITH\s+RECURSIVE\b', sql, re.IGNORECASE)
               for sql in statements), (
        'The script did not actually execute its recursive CTE.'
    )


def _assert_schema_and_index(conn):
    nodes_info = conn.execute('PRAGMA table_info(nodes)').fetchall()
    edges_info = conn.execute('PRAGMA table_info(edges)').fetchall()

    assert [(r[1], r[2].upper(), r[5]) for r in nodes_info] == [
        ('id', 'TEXT', 1), ('name', 'TEXT', 0), ('compute_cost', 'INTEGER', 0)
    ], f'Unexpected nodes schema: {nodes_info}'
    assert [(r[1], r[2].upper(), r[5]) for r in edges_info] == [
        ('source', 'TEXT', 0), ('target', 'TEXT', 0)
    ], f'Unexpected edges schema: {edges_info}'

    indexes = conn.execute("PRAGMA index_list('edges')").fetchall()
    assert indexes, "Expected at least one index on the 'edges' table."
    indexed_columns = []
    for index_row in indexes:
        columns = [r[2] for r in conn.execute(
            'PRAGMA index_info("' + index_row[1].replace('"', '""') + '")'
        ).fetchall()]
        indexed_columns.append(columns)
    assert any(columns and columns[0] == 'source' for columns in indexed_columns), (
        "Expected an edges index whose leading column is 'source'."
    )


def _dynamic_behavior_check():
    token = secrets.token_hex(5).upper()
    a, b, c, d, e = [f'{prefix}_{token}' for prefix in ('A', 'B', 'C', 'D', 'E')]
    x, y = f'X_{token}', f'Y_{token}'
    costs = {job: secrets.randbelow(700) + 11 for job in
             ('JOB_001', a, b, c, d, e, x, y)}
    documents = [
        {'id': 'JOB_001', 'name': f'root-{token}', 'compute_cost': costs['JOB_001'], 'depends_on': []},
        {'id': a, 'name': f'a-{token}', 'compute_cost': costs[a], 'depends_on': ['JOB_001']},
        {'id': b, 'name': f'b-{token}', 'compute_cost': costs[b], 'depends_on': ['JOB_001']},
        {'id': c, 'name': f'c-{token}', 'compute_cost': costs[c], 'depends_on': [a]},
        {'id': d, 'name': f'd-{token}', 'compute_cost': costs[d], 'depends_on': [a, b]},
        {'id': e, 'name': f'e-{token}', 'compute_cost': costs[e], 'depends_on': [c, d]},
        {'id': x, 'name': f'x-{token}', 'compute_cost': costs[x], 'depends_on': []},
        {'id': y, 'name': f'y-{token}', 'compute_cost': costs[y], 'depends_on': [x]},
    ]
    random.SystemRandom().shuffle(documents)

    with open(RAW, 'w', encoding='utf-8') as f:
        json.dump(documents, f)
    for path in (DB, RESULT):
        if os.path.lexists(path):
            os.remove(path)

    _run_script('/tmp/etl_dynamic_trace.json')

    assert os.path.isfile(DB), 'The script did not create pipeline.db.'
    assert os.path.isfile(RESULT), 'The script did not create result.txt.'
    expected_total = sum(costs[job] for job in ('JOB_001', a, b, c, d, e))
    with open(RESULT, 'r', encoding='utf-8') as f:
        assert f.read().strip() == str(expected_total), (
            'The result was not derived correctly from the verification input.'
        )

    expected_nodes = {
        (doc['id'], doc['name'], doc['compute_cost']) for doc in documents
    }
    expected_edges = {
        (dependency, doc['id'])
        for doc in documents for dependency in doc['depends_on']
    }
    conn = sqlite3.connect(DB)
    try:
        _assert_schema_and_index(conn)
        actual_nodes = conn.execute('SELECT id, name, compute_cost FROM nodes').fetchall()
        actual_edges = conn.execute('SELECT source, target FROM edges').fetchall()
        assert len(actual_nodes) == len(expected_nodes)
        assert set(actual_nodes) == expected_nodes, 'nodes was not loaded from the JSON input.'
        assert len(actual_edges) == len(expected_edges)
        assert set(actual_edges) == expected_edges, 'edges was not projected from depends_on.'
    finally:
        conn.close()


@pytest.fixture(scope='session', autouse=True)
def validate_executable_pipeline():
    _check_script_source()
    with open(RAW, 'rb') as f:
        original_raw = f.read()
    try:
        _dynamic_behavior_check()
    finally:
        with open(RAW, 'wb') as f:
            f.write(original_raw)

    for path in (DB, RESULT):
        if os.path.lexists(path):
            os.remove(path)
    _run_script('/tmp/etl_original_trace.json')
    yield


def test_result_file():
    result_path = '/home/user/result.txt'
    assert os.path.exists(result_path), f"Expected result file at {result_path} does not exist."
    assert os.path.isfile(result_path), f"{result_path} is not a file."

    with open(result_path, 'r') as f:
        content = f.read().strip()

    assert content == '810', f"Expected result.txt to contain '810', but got '{content}'."


def test_database_and_tables():
    db_path = '/home/user/pipeline.db'
    assert os.path.exists(db_path), f"Expected database file at {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name FROM sqlite_master WHERE type='table'")
    tables = {row[0] for row in cursor.fetchall()}
    assert 'nodes' in tables, "Table 'nodes' is missing from the database."
    assert 'edges' in tables, "Table 'edges' is missing from the database."

    _assert_schema_and_index(conn)

    cursor.execute("SELECT id, name, compute_cost FROM nodes ORDER BY id")
    nodes = cursor.fetchall()
    assert len(nodes) == 8, f"Expected 8 rows in 'nodes' table, found {len(nodes)}."
    expected_nodes = [
        ('JOB_001', 'Extract', 100),
        ('JOB_002', 'Transform A', 250),
        ('JOB_003', 'Transform B', 150),
        ('JOB_004', 'Load A', 50),
        ('JOB_005', 'Load B', 60),
        ('JOB_006', 'Report', 200),
        ('JOB_007', 'Independent Task', 500),
        ('JOB_008', 'Independent Task Followup', 100),
    ]
    assert nodes == expected_nodes, f'Unexpected nodes data: {nodes}'

    cursor.execute("SELECT source, target FROM edges")
    edges = cursor.fetchall()
    expected_edges = {
        ("JOB_001", "JOB_002"),
        ("JOB_001", "JOB_003"),
        ("JOB_002", "JOB_004"),
        ("JOB_003", "JOB_005"),
        ("JOB_004", "JOB_006"),
        ("JOB_005", "JOB_006"),
        ("JOB_007", "JOB_008")
    }
    actual_edges = set(edges)
    assert actual_edges == expected_edges, f"Expected edges {expected_edges}, but got {actual_edges}."
    assert len(edges) == len(expected_edges), "The edges table contains duplicate rows."

    conn.close()


def test_edges_index():
    db_path = '/home/user/pipeline.db'
    assert os.path.exists(db_path), f"Expected database file at {db_path} does not exist."

    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()

    cursor.execute("SELECT name, sql FROM sqlite_master WHERE type='index' AND tbl_name='edges'")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "Expected at least one index on the 'edges' table."

    has_source_index = False
    for name, idx_sql in indexes:
        if idx_sql and 'source' in idx_sql.lower():
            has_source_index = True
            break

    assert has_source_index, "Expected an index on the 'edges' table to optimize 'source' lookups."

    actual_source_index = False
    for name, _ in indexes:
        escaped = name.replace('"', '""')
        columns = [row[2] for row in cursor.execute(
            f'PRAGMA index_info("{escaped}")'
        ).fetchall()]
        if columns and columns[0] == 'source':
            actual_source_index = True
            break
    assert actual_source_index, "Expected a real index led by the edges.source column."

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
