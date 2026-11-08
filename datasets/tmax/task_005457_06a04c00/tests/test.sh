#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import json
import os
import re
import sqlite3
import subprocess
import uuid

import pytest

DB_PATH = '/home/user/backups.db'
JSON_PATH = '/home/user/affected_backups.json'
SCRIPT_PATH = '/home/user/process_lineage.py'


def expected_from_database():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
        WITH RECURSIVE lineage AS (
            SELECT id, file_path, 0 AS depth
            FROM backup_lineage
            WHERE id = 'bkp_0001'

            UNION ALL

            SELECT b.id, b.file_path, l.depth + 1
            FROM backup_lineage b
            JOIN lineage l ON b.parent_id = l.id
        )
        SELECT id, file_path, depth
        FROM lineage
        ORDER BY depth ASC, id ASC;
        """).fetchall()
    finally:
        conn.close()

    return [
        {'id': row[0], 'file_path': row[1], 'depth': row[2]}
        for row in rows
    ]


def load_and_compare_json(expected_data):
    assert os.path.exists(JSON_PATH), f"The output JSON file {JSON_PATH} is missing."
    try:
        with open(JSON_PATH, 'r') as f:
            student_data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"The file {JSON_PATH} does not contain valid JSON.")

    assert isinstance(student_data, list), "The JSON output must be a list of objects."
    assert len(student_data) == len(expected_data), (
        f"Expected {len(expected_data)} records in the JSON output, "
        f"but found {len(student_data)}."
    )

    for i, (expected, student) in enumerate(zip(expected_data, student_data)):
        assert isinstance(student, dict), f"Record at index {i} must be a JSON object."
        assert student.get('id') == expected['id'], (
            f"Mismatch at index {i}: expected id '{expected['id']}', "
            f"got '{student.get('id')}'."
        )
        assert student.get('file_path') == expected['file_path'], (
            f"Mismatch at index {i}: expected file_path '{expected['file_path']}', "
            f"got '{student.get('file_path')}'."
        )
        assert student.get('depth') == expected['depth'], (
            f"Mismatch at index {i}: expected depth {expected['depth']}, "
            f"got {student.get('depth')}."
        )


def test_index_created():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    conn = sqlite3.connect(DB_PATH)
    try:
        index_row = conn.execute(
            "SELECT name, tbl_name FROM sqlite_master "
            "WHERE type='index' AND name='idx_parent_id';"
        ).fetchone()
        columns = conn.execute("PRAGMA index_info('idx_parent_id');").fetchall()
    finally:
        conn.close()

    assert index_row is not None, "The index 'idx_parent_id' was not created in the database."
    assert index_row[0] == 'idx_parent_id', "The index name does not match 'idx_parent_id'."
    assert index_row[1] == 'backup_lineage', (
        "The index 'idx_parent_id' must belong to the backup_lineage table."
    )
    assert columns and columns[0][2] == 'parent_id', (
        "The index 'idx_parent_id' must index parent_id as its leading column."
    )


def test_script_exists():
    assert os.path.exists(SCRIPT_PATH), f"The script {SCRIPT_PATH} was not created."
    assert os.path.isfile(SCRIPT_PATH), f"The path {SCRIPT_PATH} is not a regular file."


def test_script_executes_recursive_cte_and_generates_output():
    token = uuid.uuid4().hex
    child_id = f'verifier_child_{token}'
    grandchild_id = f'verifier_grandchild_{token}'
    unrelated_id = f'verifier_unrelated_{token}'
    child_path = f'/tmp/{child_id}.tar.gz'
    grandchild_path = f'/tmp/{grandchild_id}.tar.gz'
    unrelated_path = f'/tmp/{unrelated_id}.tar.gz'
    trace_path = f'/tmp/sql_trace_{token}.jsonl'
    instrument_dir = f'/tmp/sql_instrument_{token}'

    original_json = None
    if os.path.exists(JSON_PATH):
        with open(JSON_PATH, 'rb') as f:
            original_json = f.read()

    conn = sqlite3.connect(DB_PATH)
    try:
        index_row = conn.execute(
            "SELECT sql FROM sqlite_master "
            "WHERE type='index' AND name='idx_parent_id'"
        ).fetchone()
        assert index_row is not None, "The index 'idx_parent_id' is missing."
        original_index_sql = index_row[0]

        conn.executemany(
            "INSERT INTO backup_lineage "
            "(id, parent_id, backup_type, file_path, timestamp) "
            "VALUES (?, ?, ?, ?, ?)",
            [
                (child_id, 'bkp_0003', 'inc', child_path, '2099-01-01 00:00:00'),
                (grandchild_id, child_id, 'inc', grandchild_path, '2099-01-02 00:00:00'),
                (unrelated_id, None, 'full', unrelated_path, '2099-01-03 00:00:00'),
            ],
        )
        conn.execute('DROP INDEX idx_parent_id')
        conn.commit()
    finally:
        conn.close()

    os.makedirs(instrument_dir)
    with open(os.path.join(instrument_dir, 'sitecustomize.py'), 'w') as f:
        f.write(r'''import json
import os
import sqlite3

_real_connect = sqlite3.connect

def _traced_connect(*args, **kwargs):
    conn = _real_connect(*args, **kwargs)
    trace_path = os.environ.get('LINEAGE_SQL_TRACE')
    if trace_path:
        def record(statement):
            with open(trace_path, 'a') as trace_file:
                trace_file.write(json.dumps(statement) + '\n')
        conn.set_trace_callback(record)
    return conn

sqlite3.connect = _traced_connect
''')

    try:
        if os.path.exists(JSON_PATH):
            os.unlink(JSON_PATH)

        env = os.environ.copy()
        env['PYTHONPATH'] = instrument_dir + (
            os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else ''
        )
        env['LINEAGE_SQL_TRACE'] = trace_path

        result = subprocess.run(
            ['python3', SCRIPT_PATH],
            cwd='/home/user',
            env=env,
            capture_output=True,
            text=True,
            timeout=20,
        )
        assert result.returncode == 0, (
            f"Executing {SCRIPT_PATH} failed with exit code {result.returncode}.\n"
            f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
        )
        assert os.path.exists(JSON_PATH), (
            f"Executing {SCRIPT_PATH} did not create {JSON_PATH}."
        )

        expected_data = expected_from_database()
        assert any(row['id'] == child_id for row in expected_data)
        assert any(row['id'] == grandchild_id for row in expected_data)
        assert all(row['id'] != unrelated_id for row in expected_data)
        load_and_compare_json(expected_data)

        statements = []
        if os.path.exists(trace_path):
            with open(trace_path, 'r') as f:
                statements = [json.loads(line) for line in f if line.strip()]

        def remove_comments(sql):
            sql = re.sub(r'/\*.*?\*/', ' ', sql, flags=re.DOTALL)
            sql = re.sub(r'--[^\n]*', ' ', sql)
            return sql

        used_recursive_cte = any(
            re.search(r'^\s*WITH\s+RECURSIVE\b', remove_comments(statement), re.I)
            for statement in statements
        )
        assert used_recursive_cte, (
            "The executed script did not issue a SQL statement using WITH RECURSIVE."
        )
    finally:
        conn = sqlite3.connect(DB_PATH)
        try:
            conn.executemany(
                'DELETE FROM backup_lineage WHERE id = ?',
                [(grandchild_id,), (child_id,), (unrelated_id,)],
            )
            conn.execute('DROP INDEX IF EXISTS idx_parent_id')
            conn.execute(original_index_sql)
            conn.commit()
        finally:
            conn.close()

        if original_json is None:
            if os.path.exists(JSON_PATH):
                os.unlink(JSON_PATH)
        else:
            with open(JSON_PATH, 'wb') as f:
                f.write(original_json)


def test_json_output_correctness():
    expected_data = expected_from_database()
    assert len(expected_data) > 0, "Expected data is empty; check the database contents."
    load_and_compare_json(expected_data)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
