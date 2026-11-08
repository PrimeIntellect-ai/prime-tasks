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

SCRIPT_PATH = '/home/user/export_lineage.py'
DB_PATH = '/home/user/backups.db'
JSON_PATH = '/home/user/lineage_1.json'


def validate_rows(data, expected):
    assert isinstance(data, list), "JSON output must be an array of objects."
    assert len(data) == len(expected), "JSON output contains missing or duplicate rows."

    for row in data:
        assert isinstance(row, dict), "Every JSON array entry must be an object."
        assert set(row) == {'id', 'parent_id', 'type', 'size'}, \
            f"Unexpected fields in row: {row}"
        assert type(row['id']) is int
        assert row['parent_id'] is None or type(row['parent_id']) is int
        assert type(row['type']) is str
        assert type(row['size']) is int

    actual_by_id = {row['id']: row for row in data}
    assert len(actual_by_id) == len(data), "JSON output contains duplicate backup IDs."
    expected_by_id = {row['id']: row for row in expected}
    assert actual_by_id == expected_by_id, \
        f"Expected exact rows {expected_by_id}, but got {actual_by_id}."


def index_columns(db_path):
    with sqlite3.connect(db_path) as conn:
        row = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_parent';"
        ).fetchone()
        if row is None:
            return None
        return [r[2] for r in conn.execute("PRAGMA index_info('idx_parent')")]


def run_script(backup_id, instrument=False):
    env = os.environ.copy()
    if instrument:
        env['PYTHONPATH'] = '/tmp/sqlite_instrument' + (
            os.pathsep + env['PYTHONPATH'] if env.get('PYTHONPATH') else ''
        )
    return subprocess.run(
        ['python3', SCRIPT_PATH, str(backup_id)],
        text=True,
        capture_output=True,
        timeout=15,
        env=env,
    )


def test_json_output():
    assert os.path.exists(JSON_PATH), \
        f"Output file {JSON_PATH} does not exist. Did you run the script and redirect the output?"
    assert os.path.isfile(JSON_PATH), f"Path {JSON_PATH} is not a regular file."

    try:
        with open(JSON_PATH, 'r') as f:
            data = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f"File {JSON_PATH} does not contain valid JSON.")

    # Retain the original ID-set assertion and additionally verify every value,
    # field, type, and row count.
    ids = {row.get('id') for row in data if isinstance(row, dict)}
    expected_ids = {1, 2, 3, 4}
    assert ids == expected_ids, \
        f"Expected the JSON output to contain backup IDs {expected_ids}, but got {ids}."

    expected = [
        {'id': 1, 'parent_id': None, 'type': 'full', 'size': 1000},
        {'id': 2, 'parent_id': 1, 'type': 'incremental', 'size': 100},
        {'id': 3, 'parent_id': 2, 'type': 'incremental', 'size': 50},
        {'id': 4, 'parent_id': 1, 'type': 'incremental', 'size': 120},
    ]
    validate_rows(data, expected)


def test_database_index():
    assert os.path.exists(DB_PATH), f"Database file {DB_PATH} is missing."

    # Retain the original named-index assertion and verify its indexed column.
    with sqlite3.connect(DB_PATH) as conn:
        index = conn.execute(
            "SELECT name FROM sqlite_master WHERE type='index' AND name='idx_parent';"
        ).fetchone()
    assert index is not None, \
        "Index 'idx_parent' was not found in the database. Did you add the CREATE INDEX command to the Python script?"
    assert index_columns(DB_PATH) == ['parent_id'], \
        "Index 'idx_parent' must index exactly the parent_id column."


def test_script_generates_output_and_handles_fresh_data():
    assert os.path.isfile(SCRIPT_PATH), f"Script {SCRIPT_PATH} is missing or is not a regular file."

    # The submitted script itself must reproduce the required saved artifact.
    result = run_script(1)
    assert result.returncode == 0, result.stderr
    try:
        generated = json.loads(result.stdout)
        with open(JSON_PATH) as f:
            saved = json.load(f)
    except json.JSONDecodeError as exc:
        pytest.fail(f"The script did not emit valid JSON: {exc}")
    validate_rows(generated, saved)

    # Exercise the script against a fresh, previously unseen hierarchy. The
    # instrumentation refuses to run the recursive SELECT unless idx_parent
    # already exists with the correct definition, proving creation happened
    # before that SELECT rather than being manually left in the original DB.
    backup_path = tempfile.mktemp(prefix='backups-original-', suffix='.db')
    shutil.copy2(DB_PATH, backup_path)
    try:
        os.unlink(DB_PATH)
        seed = 100000 + int.from_bytes(os.urandom(3), 'big')
        rows = [
            (seed, None, 'full', 811),
            (seed + 1, seed, 'incremental', 91),
            (seed + 2, seed, 'incremental', 82),
            (seed + 3, seed + 1, 'incremental', 73),
            (seed + 4, seed + 3, 'incremental', 64),
            (seed + 20, None, 'full', 999),
            (seed + 21, seed + 20, 'incremental', 55),
            (seed + 22, seed + 21, 'incremental', 44),
        ]
        with sqlite3.connect(DB_PATH) as conn:
            conn.execute(
                'CREATE TABLE backup_lineage '
                '(id INTEGER PRIMARY KEY, parent_id INTEGER, type TEXT, size INTEGER)'
            )
            conn.executemany('INSERT INTO backup_lineage VALUES (?, ?, ?, ?)', rows)

        assert index_columns(DB_PATH) is None, "Fresh test DB unexpectedly already has idx_parent."

        result = run_script(seed, instrument=True)
        assert result.returncode == 0, \
            f"Script failed on a fresh hierarchy or selected before creating the index:\n{result.stderr}"
        try:
            data = json.loads(result.stdout)
        except json.JSONDecodeError as exc:
            pytest.fail(f"Script output for the fresh hierarchy was not valid JSON: {exc}")

        by_parent = {}
        by_id = {}
        for row in rows:
            obj = {'id': row[0], 'parent_id': row[1], 'type': row[2], 'size': row[3]}
            by_id[row[0]] = obj
            by_parent.setdefault(row[1], []).append(row[0])
        expected_ids = []
        pending = [seed]
        while pending:
            current = pending.pop(0)
            expected_ids.append(current)
            pending.extend(by_parent.get(current, []))
        expected = [by_id[row_id] for row_id in expected_ids]

        validate_rows(data, expected)
        assert index_columns(DB_PATH) == ['parent_id'], \
            "Running the script on a fresh DB did not create idx_parent on parent_id."
    finally:
        if os.path.exists(DB_PATH):
            os.unlink(DB_PATH)
        shutil.move(backup_path, DB_PATH)
TEST_EOF

mkdir -p /tmp/sqlite_instrument
cat << 'PY_EOF' > /tmp/sqlite_instrument/sitecustomize.py
import sqlite3 as _sqlite3

_real_connect = _sqlite3.connect


class CheckedCursor:
    def __init__(self, cursor, connection):
        self._cursor = cursor
        self._connection = connection

    def execute(self, sql, *args, **kwargs):
        normalized = ' '.join(str(sql).lower().split())
        if 'with recursive' in normalized and 'backup_lineage' in normalized:
            probe = self._connection._inner.cursor()
            found = probe.execute(
                "SELECT 1 FROM sqlite_master WHERE type='index' AND name='idx_parent'"
            ).fetchone()
            columns = [r[2] for r in probe.execute("PRAGMA index_info('idx_parent')")]
            if found is None or columns != ['parent_id']:
                raise _sqlite3.OperationalError(
                    "recursive SELECT executed before idx_parent was created on parent_id"
                )
        self._cursor.execute(sql, *args, **kwargs)
        return self

    def executemany(self, sql, *args, **kwargs):
        self._cursor.executemany(sql, *args, **kwargs)
        return self

    def executescript(self, sql):
        self._cursor.executescript(sql)
        return self

    def __iter__(self):
        return iter(self._cursor)

    def __getattr__(self, name):
        return getattr(self._cursor, name)


class CheckedConnection:
    def __init__(self, inner):
        object.__setattr__(self, '_inner', inner)

    def cursor(self, *args, **kwargs):
        return CheckedCursor(self._inner.cursor(*args, **kwargs), self)

    def execute(self, sql, *args, **kwargs):
        return self.cursor().execute(sql, *args, **kwargs)

    def executemany(self, sql, *args, **kwargs):
        return self.cursor().executemany(sql, *args, **kwargs)

    def executescript(self, sql):
        return self.cursor().executescript(sql)

    def __enter__(self):
        self._inner.__enter__()
        return self

    def __exit__(self, *args):
        return self._inner.__exit__(*args)

    def __getattr__(self, name):
        return getattr(self._inner, name)

    def __setattr__(self, name, value):
        if name == '_inner':
            object.__setattr__(self, name, value)
        else:
            setattr(self._inner, name, value)


def checked_connect(*args, **kwargs):
    return CheckedConnection(_real_connect(*args, **kwargs))


_sqlite3.connect = checked_connect
PY_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
