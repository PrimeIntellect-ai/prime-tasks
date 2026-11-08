#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
import pytest

SCRIPT_PATH = '/home/user/etl_schema_graph.py'
JSON_PATH = '/home/user/schema_hops.json'
SQL_PATH = '/home/user/optimize.sql'
DB_PATH = '/home/user/ecommerce.db'


def run_schema_script():
    result = subprocess.run(
        ['runuser', '-u', 'user', '--', 'python3', SCRIPT_PATH],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=20,
    )
    assert result.returncode == 0, (
        f'etl_schema_graph.py failed with exit code {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    assert os.path.exists(JSON_PATH), f'Script did not create {JSON_PATH}'


def test_schema_script_dynamically_traverses_database():
    """Execute the required script against a runtime-generated schema."""
    assert os.path.isfile(SCRIPT_PATH), f'Python script missing at {SCRIPT_PATH}'
    assert os.path.exists(DB_PATH), f'Database missing at {DB_PATH}'

    token = secrets.token_hex(5)
    ancestor = f'ancestor_{token}'
    direct = [f'direct_a_{token}', f'direct_b_{token}']
    second = [f'second_a_{token}', f'second_b_{token}']
    third = f'third_{token}'
    unrelated = f'unrelated_{token}'
    backup_path = f'/tmp/ecommerce_backup_{token}.db'
    generated_path = f'/tmp/ecommerce_generated_{token}.db'

    shutil.copy2(DB_PATH, backup_path)
    conn = sqlite3.connect(generated_path)
    try:
        conn.executescript(f'''
            CREATE TABLE "{ancestor}" (id INTEGER PRIMARY KEY);
            CREATE TABLE users (
                id INTEGER PRIMARY KEY,
                parent_id INTEGER,
                FOREIGN KEY(parent_id) REFERENCES "{ancestor}"(id)
            );
            CREATE TABLE "{direct[0]}" (
                id INTEGER PRIMARY KEY,
                user_id INTEGER,
                FOREIGN KEY(user_id) REFERENCES users(id)
            );
            CREATE TABLE "{direct[1]}" (
                id INTEGER PRIMARY KEY,
                user_id INTEGER,
                FOREIGN KEY(user_id) REFERENCES users(id)
            );
            CREATE TABLE "{second[0]}" (
                id INTEGER PRIMARY KEY,
                direct_id INTEGER,
                FOREIGN KEY(direct_id) REFERENCES "{direct[0]}"(id)
            );
            CREATE TABLE "{second[1]}" (
                id INTEGER PRIMARY KEY,
                direct_id INTEGER,
                FOREIGN KEY(direct_id) REFERENCES "{direct[1]}"(id)
            );
            CREATE TABLE "{third}" (
                id INTEGER PRIMARY KEY,
                second_id INTEGER,
                FOREIGN KEY(second_id) REFERENCES "{second[0]}"(id)
            );
            CREATE TABLE "{unrelated}" (id INTEGER PRIMARY KEY);
        ''')
        conn.commit()
    finally:
        conn.close()

    try:
        os.replace(generated_path, DB_PATH)
        if os.path.exists(JSON_PATH):
            os.remove(JSON_PATH)
        run_schema_script()
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
        assert data == {
            '1_hop': sorted(direct),
            '2_hops': sorted(second),
        }, 'Script did not dynamically derive the sorted one-hop and two-hop tables.'
    finally:
        if os.path.exists(generated_path):
            os.remove(generated_path)
        os.replace(backup_path, DB_PATH)

    if os.path.exists(JSON_PATH):
        os.remove(JSON_PATH)
    run_schema_script()


def test_schema_hops_json():
    """Test that schema_hops.json exists and contains the correct data."""
    assert os.path.exists(JSON_PATH), f"File missing at {JSON_PATH}"

    with open(JSON_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"File {JSON_PATH} is not valid JSON.")

    assert "1_hop" in data, "Missing '1_hop' key in JSON"
    assert "2_hops" in data, "Missing '2_hops' key in JSON"

    assert isinstance(data["1_hop"], list), "'1_hop' must be a list"
    assert isinstance(data["2_hops"], list), "'2_hops' must be a list"

    assert sorted(data["1_hop"]) == ["orders", "reviews"], "1_hop list is incorrect"
    assert sorted(data["2_hops"]) == ["order_items"], "2_hops list is incorrect"
    assert data["1_hop"] == sorted(data["1_hop"]), "1_hop list must be sorted alphabetically"
    assert data["2_hops"] == sorted(data["2_hops"]), "2_hops list must be sorted alphabetically"


def test_optimize_sql():
    """Test that optimize.sql exists, contains the correct statement, and creates the correct index."""
    assert os.path.exists(SQL_PATH), f"File missing at {SQL_PATH}"

    with open(SQL_PATH, 'r') as f:
        sql = f.read().strip()

    assert "CREATE INDEX" in sql.upper(), "Missing CREATE INDEX statement"
    assert "idx_orders_etl" in sql, "Index name 'idx_orders_etl' is missing or incorrect"

    assert os.path.exists(DB_PATH), f"Database missing at {DB_PATH}"

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute(sql)
    except sqlite3.Error as e:
        conn.close()
        pytest.fail(f"Executing optimize.sql failed with error: {e}")

    cursor = conn.cursor()
    cursor.execute("PRAGMA index_info(idx_orders_etl)")
    cols = [row[2] for row in cursor.fetchall()]

    assert cols, "Index 'idx_orders_etl' was not created properly or has no columns."
    assert cols[0] == 'status', "Equality filter 'status' should be the first column in the index."
    assert set(cols) == {'status', 'created_at', 'user_id'}, "Index does not cover the correct columns (status, created_at, user_id)."
    assert cols == ['status', 'created_at', 'user_id'], "Index columns must be ordered as status, created_at, user_id."

    cursor.execute("SELECT tbl_name FROM sqlite_master WHERE type='index' AND name='idx_orders_etl'")
    row = cursor.fetchone()
    assert row is not None and row[0] == 'orders', "Index 'idx_orders_etl' must be created on the orders table."

    conn.close()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
