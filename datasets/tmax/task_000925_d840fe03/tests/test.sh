#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
from itertools import combinations

import pytest

DB_PATH = '/home/user/ecommerce.db'
SCRIPT_PATH = '/home/user/etl_graph.py'
JSON_PATH = '/home/user/top_user_pairs.json'


def compute_expected_pairs(db_path):
    assert os.path.exists(db_path), f"Database file {db_path} is missing."
    conn = sqlite3.connect(db_path)
    c = conn.cursor()

    query = """
        SELECT pu.user_id, pu.product_id
        FROM purchases pu
        JOIN products pr ON pu.product_id = pr.product_id
        WHERE pr.category = 'Electronics'
          AND pu.purchase_date >= '2023-01-01'
    """
    c.execute(query)
    rows = c.fetchall()
    conn.close()

    user_products = {}
    for user_id, product_id in rows:
        user_products.setdefault(user_id, set()).add(product_id)

    pairs = []
    users = sorted(user_products.keys())
    for u1, u2 in combinations(users, 2):
        shared = len(user_products[u1].intersection(user_products[u2]))
        if shared > 0:
            user_a, user_b = min(u1, u2), max(u1, u2)
            pairs.append({"user_a": user_a, "user_b": user_b, "weight": shared})

    pairs.sort(key=lambda x: (-x["weight"], x["user_a"], x["user_b"]))
    return pairs[:3]


def check_script_structure():
    assert os.path.exists(SCRIPT_PATH), f"The ETL script {SCRIPT_PATH} was not found."
    assert os.path.isfile(SCRIPT_PATH), f"{SCRIPT_PATH} is not a regular file."

    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()

    try:
        tree = ast.parse(source, filename=SCRIPT_PATH)
    except SyntaxError as exc:
        pytest.fail(f"The ETL script is not valid Python: {exc}")

    networkx_aliases = set()
    imported_nx_factories = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            for alias in node.names:
                if alias.name == 'networkx':
                    networkx_aliases.add(alias.asname or alias.name)
        elif isinstance(node, ast.ImportFrom) and node.module and node.module.startswith('networkx'):
            for alias in node.names:
                imported_nx_factories.add(alias.asname or alias.name)

    assert networkx_aliases or imported_nx_factories, \
        "The ETL script must import and use the networkx library."

    graph_factories = {
        'Graph', 'DiGraph', 'MultiGraph', 'MultiDiGraph', 'from_edgelist',
        'from_pandas_edgelist', 'empty_graph', 'projected_graph',
        'weighted_projected_graph', 'collaboration_weighted_projected_graph'
    }
    uses_networkx_graph = False
    parameterized_execute = False

    for node in ast.walk(tree):
        if not isinstance(node, ast.Call):
            continue

        func = node.func
        if isinstance(func, ast.Name) and func.id in imported_nx_factories and func.id in graph_factories:
            uses_networkx_graph = True
        elif isinstance(func, ast.Attribute) and func.attr in graph_factories:
            root = func.value
            while isinstance(root, ast.Attribute):
                root = root.value
            if isinstance(root, ast.Name) and root.id in networkx_aliases:
                uses_networkx_graph = True

        if isinstance(func, ast.Attribute) and func.attr == 'execute':
            if len(node.args) >= 2 or any(k.arg in {'parameters', 'params'} for k in node.keywords):
                parameterized_execute = True

    assert uses_networkx_graph, \
        "The ETL script must construct or project a graph using networkx."
    assert parameterized_execute, \
        "The extraction query must pass SQL parameters separately to execute()."

    string_literals = [
        node.value for node in ast.walk(tree)
        if isinstance(node, ast.Constant) and isinstance(node.value, str)
    ]
    assert any('Electronics' in value for value in string_literals), \
        "The script must filter for the Electronics category."
    assert any('2023-01-01' in value for value in string_literals), \
        "The script must filter from 2023-01-01 onward."
    assert any(('?' in value or ':category' in value or ':date' in value) for value in string_literals), \
        "The extraction SQL must contain parameter placeholders."


@pytest.fixture(scope='session', autouse=True)
def run_etl_on_dynamic_database(tmp_path_factory):
    backup = tmp_path_factory.mktemp('db_backup') / 'ecommerce.db'
    shutil.copy2(DB_PATH, backup)

    try:
        check_script_structure()

        conn = sqlite3.connect(DB_PATH)
        c = conn.cursor()
        existing_users = {row[0] for row in c.execute('SELECT user_id FROM users')}
        existing_products = {row[0] for row in c.execute('SELECT product_id FROM products')}

        def fresh_ids(existing, count):
            result = []
            while len(result) < count:
                value = secrets.randbelow(900000000) + 100000000
                if value not in existing and value not in result:
                    result.append(value)
            return result

        users = sorted(fresh_ids(existing_users, 3))
        products = fresh_ids(existing_products, 7)
        user_a, user_b, user_c = users
        qualifying = products[:5]
        clothing_product = products[5]
        old_product = products[6]

        c.executemany('INSERT INTO users VALUES (?, ?)', [
            (user_a, 'Dynamic A'), (user_b, 'Dynamic B'), (user_c, 'Dynamic C')
        ])
        c.executemany('INSERT INTO products VALUES (?, ?)', [
            *[(p, 'Electronics') for p in qualifying],
            (clothing_product, 'Clothing'),
            (old_product, 'Electronics')
        ])

        purchases = []
        for p in qualifying:
            purchases.extend([
                (user_a, p, '2024-02-01'),
                (user_b, p, '2024-02-02')
            ])
        for p in qualifying[:4]:
            purchases.append((user_c, p, '2024-02-03'))

        # Duplicate, wrong-category, and old purchases must not inflate weights.
        purchases.extend([
            (user_a, qualifying[0], '2024-03-01'),
            (user_b, qualifying[0], '2024-03-02'),
            (user_a, clothing_product, '2024-04-01'),
            (user_b, clothing_product, '2024-04-01'),
            (user_c, clothing_product, '2024-04-01'),
            (user_a, old_product, '2022-12-31'),
            (user_b, old_product, '2022-12-31'),
            (user_c, old_product, '2022-12-31')
        ])
        c.executemany('INSERT INTO purchases VALUES (?, ?, ?)', purchases)
        conn.commit()
        conn.close()

        expected_before_run = compute_expected_pairs(DB_PATH)
        assert expected_before_run[0] == {"user_a": user_a, "user_b": user_b, "weight": 5}

        if os.path.lexists(JSON_PATH):
            os.remove(JSON_PATH)

        try:
            completed = subprocess.run(
                ['python3', SCRIPT_PATH],
                cwd='/home/user',
                text=True,
                capture_output=True,
                timeout=60
            )
        except subprocess.TimeoutExpired:
            pytest.fail("The ETL script did not finish within 60 seconds.")

        assert completed.returncode == 0, (
            f"Running {SCRIPT_PATH} failed with exit code {completed.returncode}.\n"
            f"stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}"
        )
        assert compute_expected_pairs(DB_PATH) == expected_before_run, \
            "The ETL script modified the source data instead of only extracting it."

        yield
    finally:
        shutil.copy2(backup, DB_PATH)


def test_json_file_exists():
    assert os.path.exists(JSON_PATH), f"The output file {JSON_PATH} was not found."
    assert os.path.isfile(JSON_PATH), f"{JSON_PATH} is not a file."


def test_json_file_content():
    expected_pairs = compute_expected_pairs(DB_PATH)

    with open(JSON_PATH, 'r') as f:
        try:
            actual_data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    assert isinstance(actual_data, list), f"The JSON root should be a list, but got {type(actual_data).__name__}."
    assert len(actual_data) == len(expected_pairs), f"Expected {len(expected_pairs)} pairs, but found {len(actual_data)}."

    for i, (actual, expected) in enumerate(zip(actual_data, expected_pairs)):
        assert isinstance(actual, dict), f"Item at index {i} is not a dictionary."
        assert "user_a" in actual, f"Item at index {i} is missing 'user_a'."
        assert "user_b" in actual, f"Item at index {i} is missing 'user_b'."
        assert "weight" in actual, f"Item at index {i} is missing 'weight'."

        assert actual["user_a"] == expected["user_a"], f"Mismatch at index {i} for 'user_a'. Expected {expected['user_a']}, got {actual['user_a']}."
        assert actual["user_b"] == expected["user_b"], f"Mismatch at index {i} for 'user_b'. Expected {expected['user_b']}, got {actual['user_b']}."
        assert actual["weight"] == expected["weight"], f"Mismatch at index {i} for 'weight'. Expected {expected['weight']}, got {actual['weight']}."
        assert actual["user_a"] < actual["user_b"], f"At index {i}, user_a ({actual['user_a']}) is not strictly less than user_b ({actual['user_b']})."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
