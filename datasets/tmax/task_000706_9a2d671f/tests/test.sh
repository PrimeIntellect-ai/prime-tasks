#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import secrets
import sqlite3
import time

import pytest
import requests

DB_PATH = '/app/company.db'
EXCLUDE_DEPT_ID = 854
BASE_URL = 'http://127.0.0.1:8080/hierarchy'
MAX_RESPONSE_SECONDS = 0.5


def get_expected_employees(db_path, start_dept_id, exclude_dept_id):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    query = """
    WITH RECURSIVE dept_tree AS (
        SELECT id FROM departments WHERE id = ? AND id != ?
        UNION ALL
        SELECT d.id FROM departments d
        INNER JOIN dept_tree t ON d.parent_id = t.id
        WHERE d.id != ?
    )
    SELECT e.name FROM employees e
    INNER JOIN dept_tree t ON e.dept_id = t.id
    ORDER BY e.name ASC
    """
    cursor.execute(query, (start_dept_id, exclude_dept_id, exclude_dept_id))
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return results


def get_expected_employees_general(db_path, start_dept_id, exclude_dept_id):
    conn = sqlite3.connect(db_path)
    cursor = conn.cursor()
    query = """
    WITH RECURSIVE
    excluded_tree(id) AS (
        SELECT id FROM departments WHERE id = ?
        UNION ALL
        SELECT d.id
        FROM departments d
        INNER JOIN excluded_tree x ON d.parent_id = x.id
    ),
    dept_tree(id) AS (
        SELECT id
        FROM departments
        WHERE id = ? AND id NOT IN (SELECT id FROM excluded_tree)
        UNION ALL
        SELECT d.id
        FROM departments d
        INNER JOIN dept_tree t ON d.parent_id = t.id
        WHERE d.id NOT IN (SELECT id FROM excluded_tree)
    )
    SELECT e.name
    FROM employees e
    INNER JOIN dept_tree t ON e.dept_id = t.id
    ORDER BY e.name ASC
    """
    cursor.execute(query, (exclude_dept_id, start_dept_id))
    results = [row[0] for row in cursor.fetchall()]
    conn.close()
    return results


def indexed_first_columns(conn):
    result = set()
    for _, index_name, *_ in conn.execute("PRAGMA index_list('departments')"):
        columns = [row for row in conn.execute(f"PRAGMA index_info('{index_name}')") if row[2] is not None]
        columns.sort(key=lambda row: row[0])
        if columns:
            result.add(('departments', columns[0][2]))
    for _, index_name, *_ in conn.execute("PRAGMA index_list('employees')"):
        columns = [row for row in conn.execute(f"PRAGMA index_info('{index_name}')") if row[2] is not None]
        columns.sort(key=lambda row: row[0])
        if columns:
            result.add(('employees', columns[0][2]))
    return result


def request_hierarchy(dept_id):
    started = time.perf_counter()
    try:
        response = requests.get(BASE_URL, params={'dept_id': dept_id}, timeout=MAX_RESPONSE_SECONDS)
    except requests.RequestException as e:
        pytest.fail(f"Failed to query dept_id={dept_id} at 127.0.0.1:8080 within 500ms: {e}")
    elapsed = time.perf_counter() - started
    assert elapsed < MAX_RESPONSE_SECONDS, (
        f"Request for dept_id={dept_id} took {elapsed:.3f}s; the API must respond in under 500ms."
    )
    return response


def assert_hierarchy_response(dept_id, expected):
    response = request_hierarchy(dept_id)
    assert response.status_code == 200, (
        f"Expected HTTP 200 OK for dept_id={dept_id}, got {response.status_code}. "
        f"Response: {response.text}"
    )
    try:
        data = response.json()
    except ValueError:
        pytest.fail(f"API response is not valid JSON. Response text: {response.text}")

    assert isinstance(data, list), f"API response must be a JSON array, got {type(data)}"
    assert len(data) == len(expected), (
        f"For dept_id={dept_id}, expected {len(expected)} employees, but got {len(data)}. "
        "Ensure you are excluding the department correctly."
    )
    assert data == expected, (
        f"API returned an incorrect employee hierarchy or incorrect sorting for dept_id={dept_id}."
    )


def test_indexes_created():
    conn = sqlite3.connect(DB_PATH)
    cursor = conn.cursor()
    cursor.execute("SELECT name FROM sqlite_master WHERE type='index' AND name NOT LIKE 'sqlite_%'")
    indexes = cursor.fetchall()
    assert len(indexes) > 0, "No indexes were created to optimize the query. You must create necessary indexes."

    first_columns = indexed_first_columns(conn)
    conn.close()
    assert ('departments', 'parent_id') in first_columns, (
        "A usable index beginning with departments.parent_id is required for recursive child lookups."
    )
    assert ('employees', 'dept_id') in first_columns, (
        "A usable index beginning with employees.dept_id is required for the employee join."
    )


def test_api_hierarchy():
    expected = get_expected_employees(DB_PATH, 1, EXCLUDE_DEPT_ID)
    assert_hierarchy_response(1, expected)


def test_api_hierarchy_for_unpredictable_departments():
    conn = sqlite3.connect(DB_PATH)
    all_ids = [row[0] for row in conn.execute('SELECT id FROM departments ORDER BY id')]
    excluded_descendants = [row[0] for row in conn.execute("""
        WITH RECURSIVE blocked(id) AS (
            SELECT id FROM departments WHERE id = ?
            UNION ALL
            SELECT d.id FROM departments d JOIN blocked b ON d.parent_id = b.id
        )
        SELECT id FROM blocked WHERE id != ?
    """, (EXCLUDE_DEPT_ID, EXCLUDE_DEPT_ID))]
    conn.close()

    candidates = [dept_id for dept_id in all_ids if dept_id != 1]
    sample_count = min(12, len(candidates))
    selected = secrets.SystemRandom().sample(candidates, sample_count)
    selected.append(EXCLUDE_DEPT_ID)
    if excluded_descendants:
        selected.append(secrets.choice(excluded_descendants))

    for dept_id in dict.fromkeys(selected):
        expected = get_expected_employees_general(DB_PATH, dept_id, EXCLUDE_DEPT_ID)
        assert_hierarchy_response(dept_id, expected)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
