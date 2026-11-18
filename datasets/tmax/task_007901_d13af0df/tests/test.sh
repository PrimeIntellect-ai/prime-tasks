#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import math
import os
import re
import sqlite3
import subprocess
from pathlib import Path

import jsonschema
import pytest

DB_PATH = '/home/user/transactions.db'
SCHEMA_PATH = '/home/user/schema.json'
OUTPUT_PATH = '/home/user/output_graph_metrics.json'

EXPECTED_ROWS = [
    (1, 'Alice', 'Bob', 100.0, '2023-01-10'),
    (2, 'Bob', 'Charlie', 60.0, '2023-01-15'),
    (3, 'Charlie', 'Alice', 20.0, '2023-01-20'),
    (4, 'Alice', 'David', 200.0, '2023-01-25'),
    (5, 'David', 'Eve', 150.0, '2023-01-28'),
    (6, 'Eve', 'Alice', 300.0, '2023-01-30'),
    (7, 'Bob', 'David', 80.0, '2023-02-05'),
    (8, 'Alice', 'Bob', 70.0, '2023-01-12'),
]

EXPECTED_SCHEMA = {
    '$schema': 'http://json-schema.org/draft-07/schema#',
    'type': 'object',
    'properties': {
        'metadata': {
            'type': 'object',
            'properties': {
                'threshold': {'type': 'number'},
                'date_start': {'type': 'string'},
                'date_end': {'type': 'string'},
            },
            'required': ['threshold', 'date_start', 'date_end'],
        },
        'top_nodes': {
            'type': 'array',
            'maxItems': 3,
            'items': {
                'type': 'object',
                'properties': {
                    'account': {'type': 'string'},
                    'pagerank': {'type': 'number'},
                },
                'required': ['account', 'pagerank'],
            },
        },
    },
    'required': ['metadata', 'top_nodes'],
}


def assert_fixture_unchanged():
    assert os.path.isfile(DB_PATH), 'Database file missing.'
    conn = sqlite3.connect(f'file:{DB_PATH}?mode=ro', uri=True)
    try:
        assert conn.execute('PRAGMA integrity_check').fetchone()[0] == 'ok'
        objects = conn.execute(
            "SELECT type, name, tbl_name FROM sqlite_master "
            "WHERE name NOT LIKE 'sqlite_%' ORDER BY type, name"
        ).fetchall()
        assert objects == [('table', 'transactions', 'transactions')], \
            'The transaction database fixture was modified.'
        columns = conn.execute('PRAGMA table_info(transactions)').fetchall()
        assert columns == [
            (0, 'tx_id', 'INTEGER', 0, None, 1),
            (1, 'sender', 'TEXT', 0, None, 0),
            (2, 'receiver', 'TEXT', 0, None, 0),
            (3, 'amount', 'REAL', 0, None, 0),
            (4, 'tx_date', 'TEXT', 0, None, 0),
        ], 'The transactions table definition was modified.'
        rows = conn.execute(
            'SELECT tx_id, sender, receiver, amount, tx_date '
            'FROM transactions ORDER BY tx_id'
        ).fetchall()
        assert rows == EXPECTED_ROWS, 'The transaction database fixture was modified.'
    finally:
        conn.close()

    assert os.path.isfile(SCHEMA_PATH), 'Schema file missing.'
    with open(SCHEMA_PATH, 'r') as f:
        schema = json.load(f)
    assert schema == EXPECTED_SCHEMA, 'The JSON schema fixture was modified.'


def resolve_strings(tree):
    values = {}
    changed = True
    while changed:
        changed = False
        for node in ast.walk(tree):
            if not isinstance(node, (ast.Assign, ast.AnnAssign)):
                continue
            targets = node.targets if isinstance(node, ast.Assign) else [node.target]
            value = node.value
            resolved = None
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                resolved = value.value
            elif isinstance(value, ast.Name) and value.id in values:
                resolved = values[value.id]
            elif isinstance(value, ast.BinOp) and isinstance(value.op, ast.Add):
                left = values.get(value.left.id) if isinstance(value.left, ast.Name) else (
                    value.left.value if isinstance(value.left, ast.Constant) and isinstance(value.left.value, str) else None
                )
                right = values.get(value.right.id) if isinstance(value.right, ast.Name) else (
                    value.right.value if isinstance(value.right, ast.Constant) and isinstance(value.right.value, str) else None
                )
                if left is not None and right is not None:
                    resolved = left + right
            if resolved is not None:
                for target in targets:
                    if isinstance(target, ast.Name) and values.get(target.id) != resolved:
                        values[target.id] = resolved
                        changed = True
    return values


def call_name(node):
    if isinstance(node, ast.Name):
        return node.id
    if isinstance(node, ast.Attribute):
        prefix = call_name(node.value)
        return f'{prefix}.{node.attr}' if prefix else node.attr
    return ''


def script_meets_requirements(path):
    try:
        source = path.read_text(encoding='utf-8')
        tree = ast.parse(source, filename=str(path))
    except (OSError, UnicodeDecodeError, SyntaxError):
        return False

    strings = resolve_strings(tree)
    imported_networkx = False
    imported_jsonschema = False
    nx_names = set()
    pagerank_names = set()
    digraph_names = set()
    validate_names = set()

    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'networkx':
                    imported_networkx = True
                    nx_names.add(alias.asname or 'networkx')
                if alias.name == 'jsonschema':
                    imported_jsonschema = True
        elif isinstance(node, ast.ImportFrom):
            if node.module == 'networkx':
                imported_networkx = True
                for alias in node.names:
                    if alias.name == 'pagerank':
                        pagerank_names.add(alias.asname or alias.name)
                    if alias.name == 'DiGraph':
                        digraph_names.add(alias.asname or alias.name)
            if node.module and node.module.startswith('jsonschema'):
                imported_jsonschema = True
                for alias in node.names:
                    if alias.name == 'validate':
                        validate_names.add(alias.asname or alias.name)

    parameterized_query = False
    uses_digraph = False
    uses_pagerank = False
    uses_validation = False
    writes_indented_json = False
    placeholder = r'(?:\?|:[A-Za-z_]\w*|@[A-Za-z_]\w*|\$[A-Za-z_]\w*)'

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        name = call_name(node.func)

        if name.endswith('.execute') and len(node.args) >= 2:
            sql_node = node.args[0]
            sql = None
            if isinstance(sql_node, ast.Constant) and isinstance(sql_node.value, str):
                sql = sql_node.value
            elif isinstance(sql_node, ast.Name):
                sql = strings.get(sql_node.id)
            if sql:
                normalized = ' '.join(sql.split())
                amount_pattern = rf'(?:\w+\.)?["`\[]?amount["`\]]?\s*>\s*{placeholder}'
                date_pattern = rf'(?:\w+\.)?["`\[]?tx_date["`\]]?\s+BETWEEN\s+{placeholder}\s+AND\s+{placeholder}'
                if (re.search(r'\bSELECT\b', normalized, re.I)
                        and re.search(r'\bFROM\s+["`\[]?transactions["`\]]?', normalized, re.I)
                        and re.search(amount_pattern, normalized, re.I)
                        and re.search(date_pattern, normalized, re.I)):
                    parameterized_query = True

        if name in digraph_names or any(name == f'{nx}.DiGraph' for nx in nx_names):
            uses_digraph = True

        if name in pagerank_names or any(name == f'{nx}.pagerank' for nx in nx_names):
            keywords = {kw.arg: kw.value for kw in node.keywords if kw.arg}
            alpha = keywords.get('alpha')
            weight = keywords.get('weight')
            if (isinstance(alpha, ast.Constant) and alpha.value == 0.85
                    and isinstance(weight, ast.Constant) and weight.value == 'weight'):
                uses_pagerank = True

        if name in validate_names or name == 'jsonschema.validate' or name.endswith('.validate'):
            if imported_jsonschema:
                uses_validation = True

        if name in ('json.dump', 'json.dumps') or name.endswith('.dump') or name.endswith('.dumps'):
            for kw in node.keywords:
                if kw.arg == 'indent' and isinstance(kw.value, ast.Constant) and kw.value.value == 2:
                    writes_indented_json = True

    return all([
        imported_networkx,
        imported_jsonschema,
        parameterized_query,
        uses_digraph,
        uses_pagerank,
        uses_validation,
        writes_indented_json,
    ])


def find_pipeline_script():
    candidates = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if d not in {'.cache', '.local', '__pycache__', 'venv', '.venv'}]
        for filename in files:
            if filename.endswith('.py'):
                candidates.append(Path(root) / filename)
    matching = [path for path in sorted(candidates) if script_meets_requirements(path)]
    assert matching, (
        'No Python pipeline script was found that uses a parameterized transaction query, '
        'NetworkX DiGraph/PageRank, jsonschema validation, and two-space JSON indentation.'
    )
    return matching[0]


@pytest.fixture(scope='session', autouse=True)
def execute_pipeline_script():
    assert_fixture_unchanged()
    script = find_pipeline_script()
    if os.path.lexists(OUTPUT_PATH):
        os.remove(OUTPUT_PATH)
    result = subprocess.run(
        ['python3', str(script)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'Pipeline script failed with exit code {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert_fixture_unchanged()
    yield


def test_output_file_exists():
    assert os.path.isfile(OUTPUT_PATH), f'Output file not found at {OUTPUT_PATH}'


def test_output_json_structure_and_values():
    assert os.path.isfile(OUTPUT_PATH), 'Output file missing.'

    with open(OUTPUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail('Output file is not valid JSON.')

    with open(SCHEMA_PATH, 'r') as f:
        schema = json.load(f)
    jsonschema.validate(instance=data, schema=schema)

    assert 'metadata' in data, "Missing 'metadata' in output JSON."
    assert 'top_nodes' in data, "Missing 'top_nodes' in output JSON."

    metadata = data['metadata']
    assert metadata.get('threshold') == 50.0, 'Incorrect threshold in metadata.'
    assert metadata.get('date_start') == '2023-01-01', 'Incorrect date_start in metadata.'
    assert metadata.get('date_end') == '2023-01-31', 'Incorrect date_end in metadata.'

    assert os.path.isfile(DB_PATH), 'Database file missing.'
    conn = sqlite3.connect(f'file:{DB_PATH}?mode=ro', uri=True)
    cursor = conn.cursor()
    cursor.execute('''
        SELECT sender, receiver, amount
        FROM transactions
        WHERE amount > 50.0 AND tx_date BETWEEN '2023-01-01' AND '2023-01-31'
    ''')
    rows = cursor.fetchall()
    conn.close()

    edges = {}
    nodes = set()
    for sender, receiver, amount in rows:
        nodes.add(sender)
        nodes.add(receiver)
        if sender not in edges:
            edges[sender] = {}
        edges[sender][receiver] = edges[sender].get(receiver, 0.0) + amount

    N = len(nodes)
    assert N >= 3, 'Filtered fixture must contain at least three graph nodes.'
    pr = {n: 1.0 / N for n in nodes}
    alpha = 0.85

    for _ in range(100):
        new_pr = {n: 0.0 for n in nodes}
        dangling_sum = sum(pr[n] for n in nodes if n not in edges or not edges[n])

        for n in nodes:
            new_pr[n] += (1.0 - alpha) / N + alpha * dangling_sum / N

        for n in nodes:
            if n in edges and edges[n]:
                total_weight = sum(edges[n].values())
                for out_n, weight in edges[n].items():
                    new_pr[out_n] += alpha * pr[n] * (weight / total_weight)
        pr = new_pr

    sorted_pr = sorted(pr.items(), key=lambda x: x[1], reverse=True)
    expected_top_3 = sorted_pr[:3]

    top_nodes = data['top_nodes']
    assert isinstance(top_nodes, list), "'top_nodes' should be a list."
    assert len(top_nodes) == 3, f'Expected 3 top nodes, found {len(top_nodes)}.'
    assert len(expected_top_3) == 3, 'Expected fixture did not produce three ranked nodes.'

    for i, expected in enumerate(expected_top_3):
        exp_acc, exp_score = expected
        act_acc = top_nodes[i].get('account')
        act_score = top_nodes[i].get('pagerank')

        assert act_acc == exp_acc, f'Rank {i+1} account mismatch: expected {exp_acc}, got {act_acc}.'
        assert act_score is not None, f"Rank {i+1} missing 'pagerank'."
        assert math.isclose(act_score, exp_score, rel_tol=1e-3, abs_tol=1e-3), \
            f'Rank {i+1} pagerank mismatch for {exp_acc}: expected ~{exp_score:.4f}, got {act_score}.'
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
