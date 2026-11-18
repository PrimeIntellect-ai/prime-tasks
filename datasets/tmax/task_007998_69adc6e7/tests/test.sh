#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import csv
import os
import re
import sqlite3
import subprocess
import pytest

FIXED_ETL_PATH = '/home/user/fixed_etl.py'
INDEXES_SQL_PATH = '/home/user/indexes.sql'
OUTPUT_CSV_PATH = '/home/user/output.csv'
QUERY_PLAN_PATH = '/home/user/query_plan.txt'
DB_PATH = '/home/user/etl_data.db'

_indexes_applied = False


def reset_database():
    if os.path.exists(DB_PATH):
        os.remove(DB_PATH)
    conn = sqlite3.connect(DB_PATH)
    conn.executescript("""
        CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, signup_date TEXT);
        CREATE TABLE purchases (id INTEGER PRIMARY KEY, user_id INTEGER, amount REAL, purchase_date TEXT);
        INSERT INTO users (id, name, signup_date) VALUES
            (1, 'Alice', '2023-01-05'),
            (2, 'Bob', '2023-02-10'),
            (3, 'Charlie', '2023-01-20');
        INSERT INTO purchases (id, user_id, amount, purchase_date) VALUES
            (101, 1, 50.0, '2023-01-15'),
            (102, 1, 25.0, '2023-02-01'),
            (103, 2, 100.0, '2023-02-15'),
            (104, 3, 75.0, '2023-01-25');
    """)
    conn.close()


reset_database()


def apply_indexes():
    global _indexes_applied
    if _indexes_applied:
        return

    assert os.path.exists(INDEXES_SQL_PATH), f"File {INDEXES_SQL_PATH} does not exist."
    with open(INDEXES_SQL_PATH, 'r') as f:
        sql_script = f.read()

    conn = sqlite3.connect(DB_PATH)
    try:
        conn.executescript(sql_script)
        conn.commit()
    except Exception as e:
        pytest.fail(f"Failed to execute indexes.sql: {e}")
    finally:
        conn.close()
    _indexes_applied = True


def expected_rows(signup_date, purchase_date):
    conn = sqlite3.connect(DB_PATH)
    rows = conn.execute(
        """
        SELECT u.name, p.amount, p.purchase_date
        FROM users AS u
        JOIN purchases AS p ON p.user_id = u.id
        WHERE u.signup_date >= ? AND p.purchase_date >= ?
        """,
        (signup_date, purchase_date),
    ).fetchall()
    conn.close()
    return [
        {'name': name, 'amount': str(amount), 'purchase_date': date}
        for name, amount, date in rows
    ]


def run_and_read(signup_date, purchase_date):
    if os.path.exists(OUTPUT_CSV_PATH):
        os.remove(OUTPUT_CSV_PATH)
    result = subprocess.run(
        ['python3', FIXED_ETL_PATH, signup_date, purchase_date],
        capture_output=True,
        text=True,
    )
    assert result.returncode == 0, f"Script execution failed with error: {result.stderr}"
    assert os.path.exists(OUTPUT_CSV_PATH), f"Output file {OUTPUT_CSV_PATH} was not created."

    with open(OUTPUT_CSV_PATH, newline='') as f:
        reader = csv.DictReader(f)
        assert reader.fieldnames == ['name', 'amount', 'purchase_date'], "CSV headers do not match expected."
        return list(reader)


def test_fixed_etl_exists_and_parameterized():
    assert os.path.exists(FIXED_ETL_PATH), f"File {FIXED_ETL_PATH} does not exist."

    with open(FIXED_ETL_PATH, 'r') as f:
        content = f.read()

    # Retain the original parameter-marker assertion.
    has_qmark = '?' in content
    has_named = ':' in content
    has_format = '.format(' in content
    assert has_qmark or has_named, "The corrected script does not appear to use parameterized queries (missing '?' or ':name' markers)."

    class ExecuteVisitor(ast.NodeVisitor):
        def __init__(self):
            self.uses_fstring = False
            self.has_bound_execute = False

        def visit_Call(self, node):
            if isinstance(node.func, ast.Attribute) and node.func.attr == 'execute':
                if node.args and isinstance(node.args[0], ast.JoinedStr):
                    self.uses_fstring = True
                if len(node.args) >= 2:
                    self.has_bound_execute = True
            self.generic_visit(node)

    try:
        tree = ast.parse(content)
        visitor = ExecuteVisitor()
        visitor.visit(tree)
        assert not visitor.uses_fstring, "The script still uses f-strings in cursor.execute(), making it vulnerable to SQL injection."
        assert visitor.has_bound_execute, "The SELECT query is not executed with a separate parameter binding argument."
    except SyntaxError:
        pytest.fail(f"Syntax error in {FIXED_ETL_PATH}")


def test_indexes_sql_applied():
    apply_indexes()

    conn = sqlite3.connect(DB_PATH)
    indexes = conn.execute(
        "SELECT name, tbl_name FROM sqlite_master "
        "WHERE type='index' AND tbl_name IN ('purchases', 'users') AND sql IS NOT NULL"
    ).fetchall()
    assert len(indexes) > 0, "No indexes were created on 'purchases' or 'users' tables."

    indexed_columns = {'users': set(), 'purchases': set()}
    for index_name, table_name in indexes:
        escaped = index_name.replace("'", "''")
        columns = conn.execute(f"PRAGMA index_info('{escaped}')").fetchall()
        indexed_columns[table_name].update(row[2] for row in columns)
    conn.close()

    assert 'signup_date' in indexed_columns['users'], "No index covers users.signup_date."
    assert 'user_id' in indexed_columns['purchases'], "No index covers purchases.user_id for the join."
    assert 'purchase_date' in indexed_columns['purchases'], "No index covers purchases.purchase_date."


def test_fixed_etl_execution_and_output():
    apply_indexes()

    # This date agrees with the expected Charlie row and faithfully tests both filters.
    signup_date = '2023-01-10'
    purchase_date = '2023-01-20'
    actual_rows = run_and_read(signup_date, purchase_date)

    expected_rows_original = [
        {'name': 'Bob', 'amount': '100.0', 'purchase_date': '2023-02-15'},
        {'name': 'Charlie', 'amount': '75.0', 'purchase_date': '2023-01-25'},
    ]
    derived = expected_rows(signup_date, purchase_date)
    assert sorted(derived, key=lambda x: x['name']) == sorted(expected_rows_original, key=lambda x: x['name'])
    assert len(actual_rows) == 2, f"Expected 2 rows in output, got {len(actual_rows)}."
    assert sorted(actual_rows, key=lambda x: x['name']) == sorted(derived, key=lambda x: x['name']), \
        f"CSV contents do not match expected. Got: {actual_rows}"

    # A binding-sensitive input ensures interpolation cannot masquerade as parameterization.
    injected_signup = "2023-01-10' OR 1=1 --"
    actual_injection_rows = run_and_read(injected_signup, purchase_date)
    derived_injection_rows = expected_rows(injected_signup, purchase_date)
    assert sorted(actual_injection_rows, key=lambda x: (x['name'], x['purchase_date'])) == \
        sorted(derived_injection_rows, key=lambda x: (x['name'], x['purchase_date']))


def test_query_plan_exists():
    apply_indexes()
    assert os.path.exists(QUERY_PLAN_PATH), f"File {QUERY_PLAN_PATH} does not exist."

    with open(QUERY_PLAN_PATH, 'r') as f:
        content = f.read().strip()

    assert len(content) > 0, f"{QUERY_PLAN_PATH} is empty."
    content_upper = content.upper()
    assert "SCAN" in content_upper or "SEARCH" in content_upper, \
        f"{QUERY_PLAN_PATH} does not look like standard EXPLAIN QUERY PLAN output."

    conn = sqlite3.connect(DB_PATH)
    canonical_query = """
        SELECT u.name, p.amount, p.purchase_date
        FROM users AS u
        JOIN purchases AS p ON p.user_id = u.id
        WHERE u.signup_date >= ? AND p.purchase_date >= ?
    """
    expected_details = [
        row[3] for row in conn.execute(
            'EXPLAIN QUERY PLAN ' + canonical_query,
            ('2023-01-10', '2023-01-20'),
        ).fetchall()
    ]
    submitted_index_names = [
        row[0] for row in conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' "
            "AND tbl_name IN ('users', 'purchases') AND sql IS NOT NULL"
        ).fetchall()
    ]
    conn.close()

    for detail in expected_details:
        assert detail.upper() in content_upper, \
            f"query_plan.txt does not match the execution plan for the corrected query; missing: {detail}"

    assert not re.search(r'\bSCAN\s+(U|P|USERS|PURCHASES)\b', content_upper), \
        "The submitted query plan still contains a full scan of users or purchases."
    assert any(name.upper() in content_upper for name in submitted_index_names), \
        "The query plan does not use any index created by indexes.sql."
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
