#!/bin/bash
mkdir -p /logs/verifier /tmp/backup_instrument

cat << 'PY_EOF' > /tmp/backup_instrument/sitecustomize.py
import json
import os
import sqlite3

SQL_LOG = os.environ.get('BACKUP_SQL_LOG')
SCHEMA_LOG = os.environ.get('BACKUP_SCHEMA_LOG')

_original_connect = sqlite3.connect

def _connect(*args, **kwargs):
    conn = _original_connect(*args, **kwargs)
    if SQL_LOG:
        def trace(statement):
            try:
                with open(SQL_LOG, 'a', encoding='utf-8') as f:
                    f.write(statement.replace('\n', ' ') + '\n')
            except Exception:
                pass
        conn.set_trace_callback(trace)
    return conn

sqlite3.connect = _connect

def _record_schema(schema):
    if not SCHEMA_LOG:
        return
    try:
        with open(SCHEMA_LOG, 'a', encoding='utf-8') as f:
            f.write(json.dumps(schema, sort_keys=True) + '\n')
    except Exception:
        pass

try:
    import jsonschema

    _original_validate = jsonschema.validate
    def _validate(*args, **kwargs):
        schema = args[1] if len(args) > 1 else kwargs.get('schema')
        _record_schema(schema)
        return _original_validate(*args, **kwargs)
    jsonschema.validate = _validate

    _original_iter_errors = jsonschema.Draft7Validator.iter_errors
    def _iter_errors(self, *args, **kwargs):
        _record_schema(self.schema)
        return _original_iter_errors(self, *args, **kwargs)
    jsonschema.Draft7Validator.iter_errors = _iter_errors
except Exception:
    pass
PY_EOF

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import json
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import pytest

DB_PATH = '/home/user/backups.db'
PLAN_PATH = '/home/user/restoration_plan.json'
SCRIPT_PATH = '/home/user/analyze_backups.py'
INSTRUMENT_PATH = '/tmp/backup_instrument'

EXPECTED_SCHEMA = {
    "$schema": "http://json-schema.org/draft-07/schema#",
    "type": "array",
    "items": {
        "type": "object",
        "properties": {
            "backup_id": {"type": "integer"},
            "backup_type": {"type": "string"},
            "size_bytes": {"type": "integer"},
            "cumulative_size_bytes": {"type": "integer"}
        },
        "required": ["backup_id", "backup_type", "size_bytes", "cumulative_size_bytes"]
    }
}

def run_script(tag):
    sql_log = f'/tmp/{tag}_sql.log'
    schema_log = f'/tmp/{tag}_schema.log'
    for path in (sql_log, schema_log):
        try:
            os.remove(path)
        except FileNotFoundError:
            pass

    env = os.environ.copy()
    env['PYTHONPATH'] = INSTRUMENT_PATH + (os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else '')
    env['BACKUP_SQL_LOG'] = sql_log
    env['BACKUP_SCHEMA_LOG'] = schema_log
    result = subprocess.run(
        ['python3', SCRIPT_PATH], cwd='/home/user', env=env,
        text=True, capture_output=True, timeout=30
    )
    assert result.returncode == 0, (
        f'{SCRIPT_PATH} failed with exit code {result.returncode}. '
        f'stdout: {result.stdout}\nstderr: {result.stderr}'
    )
    return sql_log, schema_log

def read_json_lines(path):
    if not os.path.isfile(path):
        return []
    values = []
    with open(path, encoding='utf-8') as f:
        for line in f:
            try:
                values.append(json.loads(line))
            except json.JSONDecodeError:
                pass
    return values

def get_expected_chain():
    conn = sqlite3.connect(DB_PATH)
    conn.row_factory = sqlite3.Row
    cursor = conn.cursor()

    # Find the most recent FULL backup for prod_payments
    cursor.execute("""
        SELECT id, backup_type, size_bytes
        FROM backup_catalog
        WHERE db_name = 'prod_payments' AND backup_type = 'FULL'
        ORDER BY timestamp DESC
        LIMIT 1
    """)
    full_backup = cursor.fetchone()
    if not full_backup:
        conn.close()
        return []

    chain = []
    current_id = full_backup['id']
    cumulative_size = 0

    # Add FULL backup
    cumulative_size += full_backup['size_bytes']
    chain.append({
        "backup_id": full_backup['id'],
        "backup_type": full_backup['backup_type'],
        "size_bytes": full_backup['size_bytes'],
        "cumulative_size_bytes": cumulative_size
    })

    # Find descendants
    while True:
        cursor.execute("""
            SELECT id, backup_type, size_bytes
            FROM backup_catalog
            WHERE parent_id = ? AND db_name = 'prod_payments'
            ORDER BY timestamp ASC
        """, (current_id,))
        children = cursor.fetchall()
        if not children:
            break

        # Assume linear chain for simplicity based on the problem description
        child = children[0]
        cumulative_size += child['size_bytes']
        chain.append({
            "backup_id": child['id'],
            "backup_type": child['backup_type'],
            "size_bytes": child['size_bytes'],
            "cumulative_size_bytes": cumulative_size
        })
        current_id = child['id']

    conn.close()
    return chain

def assert_plan_matches_expected():
    with open(PLAN_PATH, 'r') as f:
        data = json.load(f)
    expected_chain = get_expected_chain()
    assert len(data) == len(expected_chain)
    for actual, expected in zip(data, expected_chain):
        assert actual == expected

def test_script_exists_executes_and_uses_required_features():
    assert os.path.exists(SCRIPT_PATH), f'The file {SCRIPT_PATH} was not created.'
    assert os.path.isfile(SCRIPT_PATH), f'The path {SCRIPT_PATH} is not a file.'
    with open(SCRIPT_PATH, 'r', encoding='utf-8') as f:
        source = f.read()
    ast.parse(source, filename=SCRIPT_PATH)

    sql_log, schema_log = run_script('original')
    with open(sql_log, 'r', encoding='utf-8') as f:
        statements = f.read()
    assert re.search(r'\bWITH\s+RECURSIVE\b', statements, re.IGNORECASE), \
        'The executed SQL did not use a recursive CTE.'
    assert re.search(r'\bOVER\s*\(', statements, re.IGNORECASE), \
        'The executed SQL did not use a window function.'

    schemas = read_json_lines(schema_log)
    assert EXPECTED_SCHEMA in schemas, \
        'The restoration plan was not validated with the exact required Draft-07 JSON schema.'

def test_restoration_plan_exists():
    assert os.path.exists(PLAN_PATH), f"The file {PLAN_PATH} was not created."
    assert os.path.isfile(PLAN_PATH), f"The path {PLAN_PATH} is not a file."

def test_restoration_plan_content():
    assert os.path.exists(PLAN_PATH), "Cannot test content because file is missing."

    with open(PLAN_PATH, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f"The file {PLAN_PATH} does not contain valid JSON.")

    assert isinstance(data, list), "The JSON output must be a list of objects."

    expected_chain = get_expected_chain()

    assert len(data) == len(expected_chain), f"Expected {len(expected_chain)} items in the restoration plan, but got {len(data)}."

    for i, (actual, expected) in enumerate(zip(data, expected_chain)):
        assert isinstance(actual, dict), f"Item at index {i} is not a JSON object."

        required_keys = {"backup_id", "backup_type", "size_bytes", "cumulative_size_bytes"}
        missing_keys = required_keys - actual.keys()
        assert not missing_keys, f"Item at index {i} is missing required keys: {missing_keys}"

        assert actual["backup_id"] == expected["backup_id"], f"Item {i} backup_id mismatch: expected {expected['backup_id']}, got {actual['backup_id']}"
        assert actual["backup_type"] == expected["backup_type"], f"Item {i} backup_type mismatch: expected {expected['backup_type']}, got {actual['backup_type']}"
        assert actual["size_bytes"] == expected["size_bytes"], f"Item {i} size_bytes mismatch: expected {expected['size_bytes']}, got {actual['size_bytes']}"
        assert actual["cumulative_size_bytes"] == expected["cumulative_size_bytes"], f"Item {i} cumulative_size_bytes mismatch: expected {expected['cumulative_size_bytes']}, got {actual['cumulative_size_bytes']}"

def test_script_recomputes_plan_for_changed_database():
    saved_db = '/tmp/backups_original.db'
    shutil.copy2(DB_PATH, saved_db)
    base = 10000 + secrets.randbelow(1000000)
    sizes = [
        4000 + secrets.randbelow(1000),
        101 + secrets.randbelow(100),
        201 + secrets.randbelow(100),
        301 + secrets.randbelow(100)
    ]
    try:
        conn = sqlite3.connect(DB_PATH)
        conn.execute('DELETE FROM backup_catalog')
        rows = [
            (base - 10, 'prod_payments', 'FULL', None, 999, '2024-01-01 00:00:00'),
            (base, 'prod_payments', 'FULL', None, sizes[0], '2026-02-10 00:00:00'),
            (base + 1, 'prod_payments', 'INC', base, sizes[1], '2026-02-11 00:00:00'),
            (base + 2, 'prod_payments', 'INC', base + 1, sizes[2], '2026-02-12 00:00:00'),
            (base + 3, 'prod_payments', 'INC', base + 2, sizes[3], '2026-02-13 00:00:00'),
            (base + 4, 'prod_payments', 'INC', 987654321, 777, '2026-02-14 00:00:00'),
            (base + 5, 'prod_users', 'FULL', None, 888, '2026-03-01 00:00:00')
        ]
        conn.executemany('INSERT INTO backup_catalog VALUES (?, ?, ?, ?, ?, ?)', rows)
        conn.commit()
        conn.close()

        run_script('changed')
        assert_plan_matches_expected()
    finally:
        shutil.copy2(saved_db, DB_PATH)
        subprocess.run(['python3', SCRIPT_PATH], cwd='/home/user', timeout=30,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
