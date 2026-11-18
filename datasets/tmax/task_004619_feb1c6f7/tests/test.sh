#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import sqlite3
import subprocess
import sys

SCRIPT_PATH = '/home/user/analyze_graph.py'
DB_PATH = '/home/user/graph.db'
JSON_PATH = '/home/user/cycles.json'


def resolve_string(node, assignments):
    if isinstance(node, ast.Constant) and isinstance(node.value, str):
        return node.value
    if isinstance(node, ast.Name) and node.id in assignments:
        return resolve_string(assignments[node.id], assignments)
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        left = resolve_string(node.left, assignments)
        right = resolve_string(node.right, assignments)
        if left is not None and right is not None:
            return left + right
    if isinstance(node, ast.Call) and node.args:
        # Permit harmless wrappers such as textwrap.dedent(...) and sql.strip().
        if isinstance(node.func, ast.Attribute) and node.func.attr in {'strip', 'lstrip', 'rstrip'}:
            return resolve_string(node.func.value, assignments)
        if isinstance(node.func, ast.Attribute) and node.func.attr == 'dedent':
            return resolve_string(node.args[0], assignments)
        if isinstance(node.func, ast.Name) and node.func.id == 'dedent':
            return resolve_string(node.args[0], assignments)
    return None


def inspect_script():
    assert os.path.isfile(SCRIPT_PATH), f'Script missing at {SCRIPT_PATH}'
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        content = f.read()

    # Preserve the original parameterization-sign assertion.
    assert '?' in content or '%s' in content or ':' in content, \
        'Script does not appear to use parameterized SQL queries.'

    try:
        tree = ast.parse(content, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        raise AssertionError(f'analyze_graph.py is not valid Python: {exc}')

    assignments = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            for target in targets:
                if isinstance(target, ast.Name):
                    assignments[target.id] = value

    execute_calls = []
    forbidden_calls = []
    for node in ast.walk(tree):
        if isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            if node.func.attr == 'execute':
                execute_calls.append(node)
            elif node.func.attr in {'executemany', 'executescript'}:
                forbidden_calls.append(node.func.attr)

    assert not forbidden_calls, 'Database work must use one parameterized execute() query.'
    assert len(execute_calls) == 1, \
        f'Expected exactly one SQL execute() call, found {len(execute_calls)}.'

    call = execute_calls[0]
    assert len(call.args) >= 2, \
        'The SQL execute() call must pass the relation type separately as parameters.'

    sql = resolve_string(call.args[0], assignments)
    assert sql is not None, 'The SQL supplied to execute() must be statically identifiable.'
    normalized = re.sub(r'\s+', ' ', sql).strip()

    assert re.search(r'(^|[^?])\?([^?]|$)', sql) or re.search(r'[:@$][A-Za-z_]\w*', sql), \
        'The executed SQL query must contain a SQLite parameter placeholder.'
    assert re.search(r'\bSELECT\b', normalized, re.I), 'The single query must be a SELECT query.'
    assert re.search(r'\bEdges\b', normalized, re.I), 'The query must read Edges.'
    assert re.search(r'\bNodes\b', normalized, re.I), 'The query must join Nodes for service names.'
    assert len(re.findall(r'\bJOIN\b', normalized, re.I)) >= 5, \
        'The query must perform the edge and node joins needed for a triangle.'
    assert normalized.count('<') >= 2, \
        'The SQL query must enforce both strict A.id < B.id and A.id < C.id constraints.'


def install_db(nodes, edges):
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('CREATE TABLE Nodes (id INTEGER PRIMARY KEY, name TEXT)')
        conn.execute('CREATE TABLE Edges (source_id INTEGER, target_id INTEGER, relation_type TEXT)')
        conn.executemany('INSERT INTO Nodes VALUES (?, ?)', nodes)
        conn.executemany('INSERT INTO Edges VALUES (?, ?, ?)', edges)
        conn.commit()
    finally:
        conn.close()


def run_script(relation_type):
    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    proc = subprocess.run(
        [sys.executable, SCRIPT_PATH, relation_type],
        cwd='/home/user', text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=15
    )
    assert proc.returncode == 0, \
        f'Script failed for {relation_type!r}: stdout={proc.stdout!r}, stderr={proc.stderr!r}'
    assert os.path.isfile(JSON_PATH), f'Output JSON missing at {JSON_PATH}'
    try:
        with open(JSON_PATH, 'r', encoding='utf-8') as f:
            data = json.load(f)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'cycles.json is not valid JSON: {exc}')
    assert isinstance(data, list), 'Output should be a JSON array of lists.'
    assert all(isinstance(row, list) and len(row) == 3 and
               all(isinstance(value, str) for value in row) for row in data), \
        'Each cycle must be a list containing three node names.'
    return data


def canonical_db():
    nodes = [
        (1, 'AuthService'), (2, 'UserService'), (3, 'EmailService'),
        (4, 'PaymentService'), (5, 'LedgerService'), (6, 'AuditService'),
        (7, 'NotificationService'), (8, 'ReportService'), (9, 'DataService')
    ]
    edges = [
        (1, 2, 'DEPENDS_ON'), (2, 3, 'DEPENDS_ON'), (3, 1, 'DEPENDS_ON'),
        (4, 5, 'DEPENDS_ON'), (5, 6, 'DEPENDS_ON'), (6, 4, 'DEPENDS_ON'),
        (7, 8, 'REQUIRES'), (8, 9, 'REQUIRES'), (9, 7, 'REQUIRES'),
        (1, 4, 'DEPENDS_ON'), (4, 7, 'DEPENDS_ON')
    ]
    return nodes, edges


def test_script_and_original_result():
    inspect_script()
    nodes, edges = canonical_db()
    install_db(nodes, edges)
    expected = [
        ['AuthService', 'UserService', 'EmailService'],
        ['PaymentService', 'LedgerService', 'AuditService']
    ]
    data = run_script('DEPENDS_ON')
    assert len(data) == 2, f'Expected 2 cycles, found {len(data)}.'
    assert data == expected, f'Output JSON data does not match expected sorted output. Got: {data}'


def test_runtime_derived_graph_and_relation_filtering():
    token = secrets.token_hex(6)
    ids = secrets.SystemRandom().sample(range(20, 900), 15)
    names = [f'{token}_{i}_{secrets.token_hex(3)}' for i in range(15)]
    nodes = list(zip(ids, names))

    def ordered_cycle(indices):
        a_index = min(indices, key=lambda i: ids[i])
        others = [i for i in indices if i != a_index]
        # Deliberately do not order names alphabetically; SQL orientation is by edges/IDs.
        b_index, c_index = others[1], others[0]
        return a_index, b_index, c_index

    r1 = 'REL_' + secrets.token_hex(5)
    r2 = 'ALT_' + secrets.token_hex(5)
    c1 = ordered_cycle([0, 1, 2])
    c2 = ordered_cycle([3, 4, 5])
    c3 = ordered_cycle([6, 7, 8])

    edges = []
    for cycle, relation in ((c1, r1), (c2, r1), (c3, r2)):
        a, b, c = cycle
        edges.extend([(ids[a], ids[b], relation),
                      (ids[b], ids[c], relation),
                      (ids[c], ids[a], relation)])

    # Duplicate an edge: the same logical cycle must still be reported only once.
    a, b, _ = c1
    edges.append((ids[a], ids[b], r1))

    # A mixed-relation triangle must not match either requested relation.
    m0, m1, m2 = 9, 10, 11
    edges.extend([(ids[m0], ids[m1], r1),
                  (ids[m1], ids[m2], r1),
                  (ids[m2], ids[m0], r2)])

    # Noise and an incomplete path.
    edges.extend([(ids[12], ids[13], r1),
                  (ids[13], ids[14], r1),
                  (ids[14], ids[12], 'NOISE_' + token)])

    install_db(nodes, edges)
    expected_r1 = sorted([[names[a], names[b], names[c]] for a, b, c in (c1, c2)])
    expected_r2 = sorted([[names[c3[0]], names[c3[1]], names[c3[2]]]])

    assert run_script(r1) == expected_r1
    assert run_script(r2) == expected_r2
    assert run_script(r1 + "' OR 1=1 --") == [], \
        'SQL-injection-shaped input must be treated as a literal parameter value.'

    # Leave the originally requested output and database in their expected final state.
    original_nodes, original_edges = canonical_db()
    install_db(original_nodes, original_edges)
    assert run_script('DEPENDS_ON') == [
        ['AuthService', 'UserService', 'EmailService'],
        ['PaymentService', 'LedgerService', 'AuditService']
    ]
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
