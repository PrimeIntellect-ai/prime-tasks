#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/verify_graph_task.py
import ast
import itertools
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import stat
import subprocess
import sys

SCRIPT_PATH = '/home/user/process_graph.py'
DATA_PATH = '/home/user/data/events.jsonl'
DB_PATH = '/home/user/output/analytics.db'


def remove_db():
    if os.path.isdir(DB_PATH) and not os.path.islink(DB_PATH):
        shutil.rmtree(DB_PATH)
    elif os.path.lexists(DB_PATH):
        os.unlink(DB_PATH)


def validate_script():
    assert os.path.exists(SCRIPT_PATH), f'Script not found at {SCRIPT_PATH}'
    assert not os.path.islink(SCRIPT_PATH), 'process_graph.py must be a regular file, not a symlink'
    mode = os.stat(SCRIPT_PATH).st_mode
    assert stat.S_ISREG(mode), 'process_graph.py must be a regular file'

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=SCRIPT_PATH)

    module_aliases = set()
    imported_names = {}
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'networkx' or alias.name.startswith('networkx.'):
                    module_aliases.add(alias.asname or alias.name.split('.')[0])
        elif isinstance(node, ast.ImportFrom) and node.module and (
            node.module == 'networkx' or node.module.startswith('networkx.')
        ):
            for alias in node.names:
                imported_names[alias.asname or alias.name] = alias.name

    uses_degree_centrality = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue
        func = node.func
        if isinstance(func, ast.Name) and imported_names.get(func.id) == 'degree_centrality':
            uses_degree_centrality = True
        elif isinstance(func, ast.Attribute) and func.attr == 'degree_centrality':
            root = func.value
            while isinstance(root, ast.Attribute):
                root = root.value
            if isinstance(root, ast.Name) and root.id in module_aliases:
                uses_degree_centrality = True

    assert uses_degree_centrality, 'The script must use NetworkX degree_centrality to compute the scores'

    string_values = {}
    for node in ast.walk(tree):
        if isinstance(node, (ast.Assign, ast.AnnAssign)):
            value = node.value
            if isinstance(value, ast.Constant) and isinstance(value.value, str):
                targets = node.targets if isinstance(node, ast.Assign) else [node.target]
                for target in targets:
                    if isinstance(target, ast.Name):
                        string_values[target.id] = value.value

    def sql_text(node):
        if isinstance(node, ast.Constant) and isinstance(node.value, str):
            return node.value
        if isinstance(node, ast.Name):
            return string_values.get(node.id)
        return None

    parameterized_insert = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        if node.func.attr not in ('execute', 'executemany') or not node.args:
            continue
        sql = sql_text(node.args[0])
        has_parameters = len(node.args) >= 2 or any(k.arg in ('parameters', 'params') for k in node.keywords)
        if sql and re.search(r'INSERT\s+INTO\s+item_centrality\b', sql, re.I):
            if has_parameters and re.search(r'(\?|[:@$][A-Za-z_])', sql):
                parameterized_insert = True

    assert parameterized_insert, 'Rows must be inserted into item_centrality using a parameterized query'


def expected_from_events(events):
    purchases = {}
    nodes = set()
    for event in events:
        if event.get('event_type') == 'purchase':
            user = event['user_id']
            item = event['item_id']
            nodes.add(item)
            purchases.setdefault(user, set()).add(item)

    edges = set()
    for items in purchases.values():
        for a, b in itertools.combinations(sorted(items), 2):
            if a != b:
                edges.add((a, b))

    degrees = {item: 0 for item in nodes}
    for a, b in edges:
        degrees[a] += 1
        degrees[b] += 1
    denominator = len(nodes) - 1
    centrality = {
        item: (degrees[item] / denominator if denominator > 0 else 0.0)
        for item in nodes
    }
    return sorted(centrality.items(), key=lambda row: (-row[1], row[0]))[:3]


def run_script():
    result = subprocess.run(
        [sys.executable, SCRIPT_PATH],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert result.returncode == 0, (
        f'process_graph.py exited with status {result.returncode}\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


def check_database(expected):
    assert os.path.exists(DB_PATH), f'Database not found at {DB_PATH}. Ensure your script creates the database at the exact specified path.'
    assert os.path.isfile(DB_PATH), f'{DB_PATH} is not a regular database file'

    conn = sqlite3.connect(DB_PATH)
    try:
        cursor = conn.cursor()
        cursor.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='item_centrality'")
        table = cursor.fetchone()
        assert table is not None, "Table 'item_centrality' does not exist in the database."

        cursor.execute("PRAGMA table_info(item_centrality)")
        columns = cursor.fetchall()
        assert [(c[1], c[2].upper()) for c in columns] == [
            ('item_id', 'TEXT'), ('centrality', 'REAL')
        ], "item_centrality must have exactly item_id TEXT and centrality REAL columns"

        cursor.execute("SELECT item_id, centrality FROM item_centrality ORDER BY centrality DESC, item_id ASC")
        rows = cursor.fetchall()
    finally:
        conn.close()

    assert len(rows) == 3, f"Expected exactly 3 rows in 'item_centrality' representing the top 3 items, but found {len(rows)}."
    for i, (row, wanted) in enumerate(zip(rows, expected)):
        assert row[0] == wanted[0], f"Rank {i+1} item_id mismatch: expected '{wanted[0]}', got '{row[0]}'. Make sure ties are sorted alphabetically ascending."
        assert isinstance(row[1], (int, float)), f'Centrality for {row[0]} should be a number, got {type(row[1])}.'
        assert abs(row[1] - wanted[1]) < 0.001, f'Rank {i+1} centrality mismatch for {row[0]}: expected {wanted[1]}, got {row[1]}.'


def main():
    validate_script()
    with open(DATA_PATH, 'rb') as f:
        original_data = f.read()

    suffix = secrets.token_hex(8)
    item = {letter: f'Hidden_{letter}_{suffix}' for letter in 'ABCDEFG'}
    groups = {
        'u1': ['A', 'B', 'C'],
        'u2': ['A', 'D'],
        'u3': ['A', 'E'],
        'u4': ['B', 'C', 'D'],
        'u5': ['B', 'F'],
        'u6': ['G'],
    }
    hidden_events = []
    timestamp = 2000
    for user, letters in groups.items():
        for letter in letters:
            hidden_events.append({
                'user_id': f'{user}_{suffix}',
                'item_id': item[letter],
                'event_type': 'purchase',
                'timestamp': str(timestamp),
            })
            timestamp += 1
    hidden_events.append(dict(hidden_events[0]))
    hidden_events.extend([
        {'user_id': f'view_{suffix}', 'item_id': item['G'], 'event_type': 'view', 'timestamp': '9001'},
        {'user_id': f'view_{suffix}', 'item_id': item['A'], 'event_type': 'view', 'timestamp': '9002'},
    ])
    random.SystemRandom().shuffle(hidden_events)

    try:
        with open(DATA_PATH, 'w', encoding='utf-8') as f:
            for event in hidden_events:
                f.write(json.dumps(event) + '\n')
        remove_db()
        run_script()
        check_database(expected_from_events(hidden_events))
    finally:
        with open(DATA_PATH, 'wb') as f:
            f.write(original_data)

    # Re-run against the required input so the final artifact is the requested database.
    original_events = [json.loads(line) for line in original_data.decode('utf-8').splitlines() if line.strip()]
    remove_db()
    run_script()
    check_database(expected_from_events(original_events))

    # Preserve the original verifier's exact expected-result assertions.
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute(
            'SELECT item_id, centrality FROM item_centrality ORDER BY centrality DESC, item_id ASC'
        ).fetchall()
    finally:
        conn.close()
    expected_rows = [('Item_A', 0.8), ('Item_B', 0.8), ('Item_C', 0.8)]
    assert len(rows) == 3
    for row, expected in zip(rows, expected_rows):
        assert row[0] == expected[0]
        assert isinstance(row[1], (int, float))
        assert abs(row[1] - expected[1]) < 0.001


if __name__ == '__main__':
    main()
PY_EOF

if python3 /tmp/verify_graph_task.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
