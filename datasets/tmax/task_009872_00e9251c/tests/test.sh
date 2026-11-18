#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import os
import shutil
import sqlite3
import subprocess
import tempfile
from pathlib import Path

import pytest
from packaging.version import parse

APP = Path('/home/user/app')
DB = APP / 'db.sqlite3'
READER = APP / 'src/data_reader.py'
MIGRATE = APP / 'src/migrate.py'
USER_TEST = APP / 'tests/test_migrate.py'
VENV_PYTHON = Path('/home/user/venv/bin/python')


def test_report_content():
    report_path = '/home/user/report.txt'
    assert os.path.exists(report_path), f'Report file {report_path} does not exist.'
    with open(report_path, 'r') as f:
        content = f.read().strip()
    assert content == '3', f"Expected report.txt to contain '3', but got '{content}'."


def test_database_state():
    db_path = '/home/user/app/db.sqlite3'
    assert os.path.exists(db_path), f'Database file {db_path} does not exist.'

    conn = sqlite3.connect(db_path)
    c = conn.cursor()
    try:
        c.execute('SELECT COUNT(*) FROM users')
        user_count = c.fetchone()[0]
        assert user_count == 3, f'Expected 3 users remaining in the database, found {user_count}.'

        c.execute("SELECT name FROM sqlite_master WHERE type='table' AND name='schema_info'")
        assert c.fetchone() is not None, "Table 'schema_info' does not exist."

        c.execute('SELECT version FROM schema_info')
        version_row = c.fetchone()
        assert version_row is not None, "Table 'schema_info' is empty."
        assert version_row[0] == 2, f'Expected schema version 2, got {version_row[0]}.'
    finally:
        conn.close()


def test_test_migrate_file():
    test_file_path = '/home/user/app/tests/test_migrate.py'
    assert os.path.exists(test_file_path), f'Test file {test_file_path} does not exist.'
    with open(test_file_path, 'r') as f:
        content = f.read()
    assert 'patch' in content or 'Mock' in content, 'The test file does not appear to use mocking (patch/Mock not found).'


def test_requirements_file():
    req_path = '/home/user/app/requirements.txt'
    assert os.path.exists(req_path), f'Requirements file {req_path} does not exist.'
    with open(req_path, 'r') as f:
        content = f.read()
    assert 'pytest' in content, 'pytest is missing from requirements.txt.'
    assert 'packaging' in content, 'packaging is missing from requirements.txt.'


def test_project_structure():
    assert os.path.isdir('/home/user/app/src'), 'Directory /home/user/app/src does not exist.'
    assert os.path.isdir('/home/user/app/tests'), 'Directory /home/user/app/tests does not exist.'
    assert os.path.isfile('/home/user/app/src/data_reader.py'), 'File /home/user/app/src/data_reader.py does not exist.'
    assert os.path.isfile('/home/user/app/src/migrate.py'), 'File /home/user/app/src/migrate.py does not exist.'


def test_virtualenv_dependencies():
    assert VENV_PYTHON.is_file(), 'The required virtual environment Python executable is missing.'
    result = subprocess.run(
        [str(VENV_PYTHON), '-c', 'import pytest, packaging'],
        text=True,
        capture_output=True,
        timeout=30,
    )
    assert result.returncode == 0, result.stdout + result.stderr


def test_mock_test_structure_and_execution():
    source = USER_TEST.read_text()
    tree = ast.parse(source, filename=str(USER_TEST))
    funcs = [n for n in tree.body if isinstance(n, (ast.FunctionDef, ast.AsyncFunctionDef)) and n.name == 'test_migration_process']
    assert funcs, 'test_migration_process is not defined.'
    fn = funcs[0]
    fn_source = ast.get_source_segment(source, fn) or ''
    assert 'migrate' in fn_source, 'test_migration_process does not import or run the migration.'

    patch_calls = []
    for node in ast.walk(fn):
        if not isinstance(node, ast.Call):
            continue
        called = node.func
        is_patch = isinstance(called, ast.Name) and called.id == 'patch'
        is_patch = is_patch or (isinstance(called, ast.Attribute) and called.attr in {'patch', 'object'})
        if is_patch:
            patch_calls.append(node)
    assert patch_calls, 'test_migration_process does not use unittest.mock.patch.'

    constants = [n.value for n in ast.walk(fn) if isinstance(n, ast.Constant)]
    patches_reader = any(isinstance(v, str) and v.endswith('data_reader.get_latest_data') for v in constants)
    patches_reader = patches_reader or ('get_latest_data' in constants and 'data_reader' in fn_source)
    assert patches_reader, 'The test does not patch data_reader.get_latest_data.'
    assert 'status' in constants and 'mocked' in constants, 'The patch is not configured with {"status": "mocked"}.'

    exact_once = any(
        isinstance(n, ast.Call)
        and isinstance(n.func, ast.Attribute)
        and n.func.attr in {'assert_called_once', 'assert_called_once_with'}
        for n in ast.walk(fn)
    )
    if not exact_once:
        exact_once = any(
            isinstance(n, ast.Compare)
            and any(isinstance(x, ast.Attribute) and x.attr == 'call_count' for x in ast.walk(n))
            and any(isinstance(x, ast.Constant) and x.value == 1 for x in ast.walk(n))
            for n in ast.walk(fn)
        )
    assert exact_once, 'The test does not assert that the mocked reader was called exactly once.'

    with tempfile.TemporaryDirectory() as td:
        backup = Path(td) / 'db.sqlite3'
        shutil.copy2(DB, backup)
        try:
            env = os.environ.copy()
            env['PYTEST_DISABLE_PLUGIN_AUTOLOAD'] = '1'
            result = subprocess.run(
                ['python3', '-m', 'pytest', '-q', '-c', '/dev/null', f'{USER_TEST}::test_migration_process'],
                cwd=str(APP),
                env=env,
                text=True,
                capture_output=True,
                timeout=60,
            )
            assert result.returncode == 0, result.stdout + result.stderr
        finally:
            for suffix in ('', '-wal', '-shm'):
                path = Path(str(DB) + suffix)
                if path.exists():
                    path.unlink()
            shutil.copy2(backup, DB)


def test_migration_behavior_on_independent_data():
    users = [
        (11, 'old-basic', '2.0.99'),
        (12, 'threshold', '2.1.0'),
        (13, 'prerelease-below', '2.1.0rc1'),
        (14, 'new-prerelease', '2.2.0rc1'),
        (15, 'major-new', '10.0.0'),
        (16, 'development-below', '2.1.0.dev1'),
        (17, 'post-release', '2.1.0.post1'),
        (18, 'very-old', '0.9.0'),
    ]
    expected = {(row[0], row[1], row[2]) for row in users if parse(row[2]) >= parse('2.1.0')}

    with tempfile.TemporaryDirectory() as td:
        td = Path(td)
        db_backup = td / 'db.sqlite3'
        reader_backup = td / 'data_reader.py'
        shutil.copy2(DB, db_backup)
        shutil.copy2(READER, reader_backup)
        marker = td / 'reader_calls.txt'
        try:
            for suffix in ('-wal', '-shm'):
                path = Path(str(DB) + suffix)
                if path.exists():
                    path.unlink()
            DB.unlink()
            conn = sqlite3.connect(DB)
            conn.execute('CREATE TABLE users (id INTEGER PRIMARY KEY, name TEXT, app_version TEXT)')
            conn.executemany('INSERT INTO users VALUES (?, ?, ?)', users)
            conn.commit()
            conn.close()

            READER.write_text(
                'def get_latest_data():\n'
                f'    with open({str(marker)!r}, "a") as f:\n'
                '        f.write("called\\n")\n'
                '    return {"status": "mocked"}\n'
            )

            result = subprocess.run(
                [str(VENV_PYTHON), str(MIGRATE)],
                cwd=str(APP / 'src'),
                text=True,
                capture_output=True,
                timeout=30,
            )
            assert result.returncode == 0, result.stdout + result.stderr
            assert marker.exists(), 'migrate.py did not call data_reader.get_latest_data().'
            assert marker.read_text().splitlines() == ['called'], 'data_reader.get_latest_data() was not called exactly once.'

            conn = sqlite3.connect(DB)
            try:
                actual = set(conn.execute('SELECT id, name, app_version FROM users'))
                assert actual == expected, f'Incorrect users after semantic-version migration: {actual!r}'

                columns = conn.execute('PRAGMA table_info(schema_info)').fetchall()
                assert len(columns) == 1, 'schema_info must have a single column.'
                assert columns[0][1] == 'version', 'schema_info column must be named version.'
                assert columns[0][2].upper() == 'INTEGER', 'schema_info.version must be an integer column.'
                assert conn.execute('SELECT version FROM schema_info').fetchall() == [(2,)]
            finally:
                conn.close()
        finally:
            for suffix in ('', '-wal', '-shm'):
                path = Path(str(DB) + suffix)
                if path.exists():
                    path.unlink()
            shutil.copy2(db_backup, DB)
            shutil.copy2(reader_backup, READER)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo '1' > /logs/verifier/reward.txt
else
    echo '0' > /logs/verifier/reward.txt
fi
