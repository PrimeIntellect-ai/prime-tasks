#!/bin/bash
# --- runtime-defect fix: the verifier's own imports are not in this image ---
# Without this, pytest dies at collection with ModuleNotFoundError and the task
# scores 0 regardless of what the agent did. Pre-existing: the original verifier
# imports the same modules. `|| true` so a network-less run is no worse than before.
for _m in "pymongo:pymongo"; do
  python3 -c "import ${_m%%:*}" >/dev/null 2>&1 && continue
  # Bounded and fully detached from the parent's pipes. Without `timeout` and the
  # </dev/null + >/dev/null redirects this hangs: the harness captures output, so
  # subprocess.run blocks until every writer closes the pipe, and a slow pip then
  # wedges the whole episode past its deadline. Measured: episodes stopped
  # finishing entirely until this was bounded.
  timeout 90 pip install --quiet --disable-pip-version-check --no-input       "${_m##*:}" </dev/null >/dev/null 2>&1 || true
done
# --- end fix ---
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import random
import shutil
import sqlite3
import string
import subprocess
import sys

from pymongo import MongoClient


def test_top_customers_output():
    json_path = '/home/user/top_customers.json'
    assert os.path.isfile(json_path), f"Output file {json_path} does not exist."

    with open(json_path, 'r', encoding='utf-8') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            assert False, f"File {json_path} does not contain valid JSON."

    assert isinstance(data, list), f"Expected JSON array in {json_path}, got {type(data).__name__}."

    expected_data = [
        {"name": "Charlie", "region": "East", "total_spent": 500.0},
        {"name": "Bob", "region": "South", "total_spent": 250.0},
        {"name": "Diana", "region": "West", "total_spent": 250.0}
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items in the array, found {len(data)}."

    for i, expected_item in enumerate(expected_data):
        actual_item = data[i]
        assert isinstance(actual_item, dict), f"Item at index {i} must be a JSON object."

        # Check specific fields
        assert actual_item.get("name") == expected_item["name"], \
            f"Expected name '{expected_item['name']}' at index {i}, got '{actual_item.get('name')}'."
        assert actual_item.get("region") == expected_item["region"], \
            f"Expected region '{expected_item['region']}' at index {i}, got '{actual_item.get('region')}'."

        # Handle float comparison safely
        actual_spent = actual_item.get("total_spent")
        assert actual_spent is not None, f"Missing 'total_spent' at index {i}."
        try:
            actual_spent = float(actual_spent)
        except ValueError:
            assert False, f"'total_spent' at index {i} must be a number."

        assert actual_spent == expected_item["total_spent"], \
            f"Expected total_spent {expected_item['total_spent']} at index {i}, got {actual_spent}."


def _read_expected_hierarchy(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    try:
        customers = conn.execute(
            'SELECT id, name, region FROM customers'
        ).fetchall()
        orders = conn.execute(
            'SELECT id, customer_id, order_date FROM orders'
        ).fetchall()
        items = conn.execute(
            'SELECT order_id, product, price, quantity FROM items'
        ).fetchall()
    finally:
        conn.close()

    result = {}
    for customer in customers:
        result[customer['id']] = {
            'name': customer['name'],
            'region': customer['region'],
            'orders': {}
        }
    for order in orders:
        result[order['customer_id']]['orders'][order['id']] = {
            'order_date': order['order_date'],
            'items': []
        }
    for item in items:
        for customer in result.values():
            if item['order_id'] in customer['orders']:
                customer['orders'][item['order_id']]['items'].append(
                    (item['product'], float(item['price']), item['quantity'])
                )
                break
    return result


def _expected_top_three(db_path):
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute('''
            SELECT c.name, c.region,
                   COALESCE(SUM(i.price * i.quantity), 0) AS total_spent
            FROM customers AS c
            LEFT JOIN orders AS o ON o.customer_id = c.id
            LEFT JOIN items AS i ON i.order_id = o.id
            GROUP BY c.id, c.name, c.region
            ORDER BY total_spent DESC, c.name ASC
            LIMIT 3
        ''').fetchall()
    finally:
        conn.close()
    return [
        {'name': row[0], 'region': row[1], 'total_spent': float(row[2])}
        for row in rows
    ]


def test_migration_script_mongodb_and_dynamic_behavior():
    script_path = '/home/user/migrate.py'
    db_path = '/home/user/sales.db'
    output_path = '/home/user/top_customers.json'

    assert os.path.isfile(script_path), f"Migration script {script_path} does not exist."
    assert not os.path.islink(script_path), f"Migration script {script_path} must be a regular file."
    assert os.path.getsize(script_path) > 0, f"Migration script {script_path} is empty."

    with open(script_path, 'r', encoding='utf-8') as f:
        source = f.read()
    tree = ast.parse(source, filename=script_path)
    imported_roots = set()
    call_names = set()
    for node in ast.walk(tree):
        if isinstance(node, ast.Import):
            imported_roots.update(alias.name.split('.')[0] for alias in node.names)
        elif isinstance(node, ast.ImportFrom) and node.module:
            imported_roots.add(node.module.split('.')[0])
        elif isinstance(node, ast.Call) and isinstance(node.func, ast.Attribute):
            call_names.add(node.func.attr)
    assert 'sqlite3' in imported_roots, 'migrate.py must use sqlite3.'
    assert 'pymongo' in imported_roots, 'migrate.py must use pymongo.'
    assert 'aggregate' in call_names or 'command' in call_names, \
        'migrate.py must invoke a MongoDB aggregation pipeline.'
    compile(source, script_path, 'exec')

    client = MongoClient('mongodb://127.0.0.1:27017', serverSelectionTimeoutMS=3000)
    assert client.admin.command('ping').get('ok') == 1.0, \
        'MongoDB is not running locally on the default port 27017.'

    backup_path = '/tmp/sales.db.verifier-backup'
    shutil.copy2(db_path, backup_path)
    token = ''.join(random.SystemRandom().choices(string.ascii_lowercase, k=10))

    try:
        conn = sqlite3.connect(db_path)
        try:
            next_customer = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM customers').fetchone()[0]
            next_order = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM orders').fetchone()[0]
            next_item = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM items').fetchone()[0]

            additions = [
                (next_customer, 'Zeta_' + token, 'DynamicWest', 10000.0),
                (next_customer + 1, 'Alpha_' + token, 'DynamicNorth', 9000.0),
                (next_customer + 2, 'Beta_' + token, 'DynamicSouth', 9000.0),
            ]
            for offset, (customer_id, name, region, price) in enumerate(additions):
                order_id = next_order + offset
                conn.execute('INSERT INTO customers VALUES (?, ?, ?)', (customer_id, name, region))
                conn.execute(
                    'INSERT INTO orders VALUES (?, ?, ?)',
                    (order_id, customer_id, '2042-06-15')
                )
                conn.execute(
                    'INSERT INTO items VALUES (?, ?, ?, ?, ?)',
                    (next_item + offset, order_id, 'VerifierProduct_' + token, price, 1)
                )
            conn.commit()
        finally:
            conn.close()

        expected_hierarchy = _read_expected_hierarchy(db_path)
        expected_top = _expected_top_three(db_path)

        collection = client['analytics']['customer_orders']
        collection.drop()
        if os.path.exists(output_path):
            os.remove(output_path)

        instrument_dir = '/tmp/migration_instrumentation'
        marker_path = '/tmp/mongodb_aggregate_called.jsonl'
        shutil.rmtree(instrument_dir, ignore_errors=True)
        os.makedirs(instrument_dir)
        if os.path.exists(marker_path):
            os.remove(marker_path)

        with open(os.path.join(instrument_dir, 'sitecustomize.py'), 'w', encoding='utf-8') as f:
            f.write(r'''
import json
import os
from pymongo.collection import Collection
from pymongo.database import Database

_marker = os.environ.get('MIGRATION_AGGREGATE_MARKER')

def _mark(namespace):
    if _marker:
        with open(_marker, 'a', encoding='utf-8') as out:
            out.write(json.dumps({'namespace': namespace}) + '\n')

_original_aggregate = Collection.aggregate
def _aggregate(self, *args, **kwargs):
    _mark(self.full_name)
    return _original_aggregate(self, *args, **kwargs)
Collection.aggregate = _aggregate

_original_command = Database.command
def _command(self, command, *args, **kwargs):
    target = None
    if isinstance(command, dict) and 'aggregate' in command:
        target = command.get('aggregate')
    elif command == 'aggregate' and args:
        target = args[0]
    if target:
        _mark(self.name + '.' + str(target))
    return _original_command(self, command, *args, **kwargs)
Database.command = _command
''')

        env = os.environ.copy()
        env['PYTHONPATH'] = instrument_dir + os.pathsep + env.get('PYTHONPATH', '')
        env['MIGRATION_AGGREGATE_MARKER'] = marker_path
        run = subprocess.run(
            [sys.executable, script_path],
            cwd='/home/user',
            env=env,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=60
        )
        assert run.returncode == 0, \
            f"migrate.py failed when executed. stdout:\n{run.stdout}\nstderr:\n{run.stderr}"

        assert os.path.isfile(marker_path), \
            'migrate.py did not execute a MongoDB aggregation pipeline.'
        with open(marker_path, 'r', encoding='utf-8') as f:
            namespaces = [json.loads(line)['namespace'] for line in f if line.strip()]
        assert 'analytics.customer_orders' in namespaces, \
            'The aggregation pipeline was not executed on analytics.customer_orders.'

        documents = list(collection.find({}))
        assert len(documents) == len(expected_hierarchy), \
            'customer_orders must contain exactly one document per SQLite customer.'
        assert len({doc.get('_id') for doc in documents}) == len(documents), \
            'Customer documents must have unique _id values.'
        assert {doc.get('_id') for doc in documents} == set(expected_hierarchy), \
            'MongoDB customer IDs do not match all customers in SQLite.'

        for doc in documents:
            customer_id = doc['_id']
            expected_customer = expected_hierarchy[customer_id]
            assert doc.get('name') == expected_customer['name']
            assert doc.get('region') == expected_customer['region']
            assert isinstance(doc.get('orders'), list), \
                f"Customer {customer_id} must contain an orders array."

            actual_orders = doc['orders']
            assert len(actual_orders) == len(expected_customer['orders'])
            assert {order.get('order_id') for order in actual_orders} == set(expected_customer['orders'])
            for order in actual_orders:
                expected_order = expected_customer['orders'][order['order_id']]
                assert order.get('order_date') == expected_order['order_date']
                assert isinstance(order.get('items'), list), \
                    f"Order {order['order_id']} must contain an items array."
                actual_items = sorted(
                    (item.get('product'), float(item.get('price')), item.get('quantity'))
                    for item in order['items']
                )
                assert actual_items == sorted(expected_order['items']), \
                    f"Items for order {order['order_id']} do not match SQLite."

        assert os.path.isfile(output_path), 'migrate.py did not generate top_customers.json.'
        with open(output_path, 'r', encoding='utf-8') as f:
            dynamic_output = json.load(f)
        assert isinstance(dynamic_output, list)
        assert len(dynamic_output) == 3
        for item in dynamic_output:
            assert isinstance(item, dict)
            assert set(item) == {'name', 'region', 'total_spent'}
            assert isinstance(item['total_spent'], (int, float)) and not isinstance(item['total_spent'], bool)
        normalized_output = [
            {'name': item['name'], 'region': item['region'], 'total_spent': float(item['total_spent'])}
            for item in dynamic_output
        ]
        assert normalized_output == expected_top, \
            'Dynamic aggregation output is incorrect or not sorted by total_spent and name.'
    finally:
        client.close()
        shutil.copy2(backup_path, db_path)

TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
