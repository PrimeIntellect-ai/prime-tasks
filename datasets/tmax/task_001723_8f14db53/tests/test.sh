#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import shutil
import sqlite3
import subprocess
import tempfile

import pytest

DB_PATH = '/home/user/graph.db'
INDEXES_SQL_PATH = '/home/user/indexes.sql'
PIPELINE_PY_PATH = '/home/user/etl_pipeline.py'
JSON_OUT_PATH = '/home/user/optimized_chains.json'


def leading_index_columns(conn):
    result = set()
    rows = conn.execute(
        "SELECT name, tbl_name FROM sqlite_master "
        "WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%'"
    ).fetchall()
    for name, table in rows:
        quoted = '"' + name.replace('"', '""') + '"'
        columns = conn.execute(f'PRAGMA index_info({quoted})').fetchall()
        if columns:
            result.add((table, columns[0][2]))
    return result


def test_indexes_sql_exists_and_valid():
    """Verify indexes.sql exists and contains executable, useful CREATE INDEX statements."""
    assert os.path.exists(INDEXES_SQL_PATH), f"{INDEXES_SQL_PATH} does not exist."
    with open(INDEXES_SQL_PATH, 'r') as f:
        original_content = f.read()
    assert "CREATE INDEX" in original_content.upper(), \
        f"{INDEXES_SQL_PATH} must contain CREATE INDEX statements."

    with tempfile.TemporaryDirectory() as tmpdir:
        test_db = os.path.join(tmpdir, 'index_test.db')
        conn = sqlite3.connect(test_db)
        try:
            conn.executescript('''
                CREATE TABLE nodes (id TEXT, label TEXT);
                CREATE TABLE edges (source TEXT, target TEXT, cost REAL);
            ''')
            conn.executescript(original_content)
            leads = leading_index_columns(conn)
        finally:
            conn.close()

    required = {('nodes', 'label'), ('edges', 'source'), ('edges', 'target')}
    assert required <= leads, (
        "indexes.sql must create indexes led by nodes.label, edges.source, "
        "and edges.target for label filtering and directed traversal."
    )


def test_database_has_indexes():
    """Verify that the useful indexes were actually created in the SQLite database."""
    assert os.path.exists(DB_PATH), f"{DB_PATH} does not exist."
    conn = sqlite3.connect(DB_PATH)
    try:
        c = conn.cursor()
        c.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_autoindex%';")
        indexes = c.fetchall()
        leads = leading_index_columns(conn)
    finally:
        conn.close()
    assert len(indexes) > 0, "No custom indexes found in the database. Did you execute the SQL script?"
    required = {('nodes', 'label'), ('edges', 'source'), ('edges', 'target')}
    assert required <= leads, (
        "The database must have indexes led by nodes.label, edges.source, "
        "and edges.target."
    )


def test_pipeline_script_exists():
    """Verify etl_pipeline.py exists and is a regular file."""
    assert os.path.exists(PIPELINE_PY_PATH), f"{PIPELINE_PY_PATH} does not exist."
    assert os.path.isfile(PIPELINE_PY_PATH), f"{PIPELINE_PY_PATH} is not a regular file."


def test_optimized_chains_json():
    """Verify the submitted JSON output matches the original database."""
    assert os.path.exists(JSON_OUT_PATH), f"{JSON_OUT_PATH} does not exist."

    with open(JSON_OUT_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"{JSON_OUT_PATH} is not valid JSON.")

    assert isinstance(data, list), f"JSON root must be an array, got {type(data)}."

    expected_data = [
        {
            "manufacturer": "M1",
            "supplier": "S2",
            "retailer": "R1",
            "total_cost": 7.0
        },
        {
            "manufacturer": "M2",
            "supplier": "S1",
            "retailer": "R2",
            "total_cost": 12.0
        }
    ]

    assert len(data) == len(expected_data), f"Expected {len(expected_data)} items, got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_data)):
        assert isinstance(actual, dict), f"Item at index {i} is not an object."
        assert actual.get("manufacturer") == expected["manufacturer"], f"Mismatch in manufacturer at index {i}."
        assert actual.get("supplier") == expected["supplier"], f"Mismatch in supplier at index {i}."
        assert actual.get("retailer") == expected["retailer"], f"Mismatch in retailer at index {i}."
        assert actual.get("total_cost") == expected["total_cost"], f"Mismatch in total_cost at index {i}."


def derive_expected(db_path):
    conn = sqlite3.connect(db_path)
    try:
        rows = conn.execute('''
            SELECT m.id, s.id, r.id, e1.cost + e2.cost
            FROM nodes AS s
            JOIN edges AS e1 ON e1.source = s.id
            JOIN nodes AS m ON m.id = e1.target
            JOIN edges AS e2 ON e2.source = m.id
            JOIN nodes AS r ON r.id = e2.target
            WHERE s.label = 'Supplier'
              AND m.label = 'Manufacturer'
              AND r.label = 'Retailer'
        ''').fetchall()
    finally:
        conn.close()

    cheapest = {}
    for manufacturer, supplier, retailer, total_cost in rows:
        candidate = {
            'manufacturer': manufacturer,
            'supplier': supplier,
            'retailer': retailer,
            'total_cost': float(total_cost),
        }
        if manufacturer not in cheapest or total_cost < cheapest[manufacturer]['total_cost']:
            cheapest[manufacturer] = candidate
    return sorted(cheapest.values(), key=lambda item: item['total_cost'])


def test_pipeline_executes_and_handles_new_graph():
    """Execute the submitted pipeline on a different graph and verify derived results."""
    nodes = [
        ('SA', 'Supplier'), ('SB', 'Supplier'), ('SC', 'Supplier'),
        ('MA', 'Manufacturer'), ('MB', 'Manufacturer'), ('MC', 'Manufacturer'),
        ('MD', 'Manufacturer'), ('RX', 'Retailer'), ('RY', 'Retailer'),
        ('D1', 'Distributor'), ('FAKE', 'Supplier')
    ]
    edges = [
        ('SA', 'MA', 8.0), ('SB', 'MA', 1.25),
        ('MA', 'RX', 1.5), ('MA', 'RY', 6.0),
        ('SA', 'MB', 3.0), ('MB', 'RY', 4.5),
        ('SC', 'MC', -1.0), ('MC', 'RY', 2.0),
        ('SC', 'MD', 0.1), ('MD', 'D1', 0.1),
        ('RX', 'MA', -100.0), ('FAKE', 'D1', -50.0),
        ('D1', 'RY', -50.0), ('SA', 'RX', 0.01)
    ]

    with tempfile.TemporaryDirectory() as backup_dir:
        db_backup = os.path.join(backup_dir, 'graph.db')
        output_backup = os.path.join(backup_dir, 'optimized_chains.json')
        shutil.copy2(DB_PATH, db_backup)
        output_existed = os.path.exists(JSON_OUT_PATH)
        if output_existed:
            shutil.copy2(JSON_OUT_PATH, output_backup)

        try:
            for suffix in ('', '-wal', '-shm'):
                path = DB_PATH + suffix
                if os.path.exists(path):
                    os.remove(path)

            conn = sqlite3.connect(DB_PATH)
            try:
                conn.execute('CREATE TABLE nodes (id TEXT, label TEXT)')
                conn.execute('CREATE TABLE edges (source TEXT, target TEXT, cost REAL)')
                conn.executemany('INSERT INTO nodes VALUES (?, ?)', nodes)
                conn.executemany('INSERT INTO edges VALUES (?, ?, ?)', edges)
                conn.commit()
            finally:
                conn.close()

            expected = derive_expected(DB_PATH)
            if os.path.exists(JSON_OUT_PATH):
                os.remove(JSON_OUT_PATH)

            completed = subprocess.run(
                ['python3', PIPELINE_PY_PATH],
                cwd='/home/user',
                text=True,
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                timeout=30,
            )
            assert completed.returncode == 0, (
                f"etl_pipeline.py failed with exit code {completed.returncode}. "
                f"stderr: {completed.stderr}"
            )
            assert os.path.isfile(JSON_OUT_PATH), \
                "etl_pipeline.py did not generate optimized_chains.json."

            with open(JSON_OUT_PATH, 'r') as f:
                try:
                    actual = json.load(f)
                except json.JSONDecodeError as exc:
                    pytest.fail(f"Pipeline output is not valid JSON: {exc}")

            assert isinstance(actual, list), "Pipeline output root must be an array."
            assert actual == expected, \
                f"Pipeline output for the verification graph was {actual!r}, expected {expected!r}."
            for i, item in enumerate(actual):
                assert set(item) == {'manufacturer', 'supplier', 'retailer', 'total_cost'}, \
                    f"Item {i} does not have exactly the required fields."
                assert isinstance(item['total_cost'], (int, float)) and not isinstance(item['total_cost'], bool), \
                    f"Item {i} total_cost must be numeric."
            assert all(actual[i]['total_cost'] < actual[i + 1]['total_cost']
                       for i in range(len(actual) - 1)), \
                "Results are not sorted in strictly ascending total_cost order."
        finally:
            for suffix in ('', '-wal', '-shm'):
                path = DB_PATH + suffix
                if os.path.exists(path):
                    os.remove(path)
            shutil.copy2(db_backup, DB_PATH)
            if output_existed:
                shutil.copy2(output_backup, JSON_OUT_PATH)
            elif os.path.exists(JSON_OUT_PATH):
                os.remove(JSON_OUT_PATH)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
