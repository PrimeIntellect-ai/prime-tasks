#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import ast
import hashlib
import hmac
import json
import os
import secrets
import sqlite3
import subprocess

import pytest

MIGRATE = '/home/user/migrate.py'
AUTH_TEST = '/home/user/test_api_auth.py'
DB = '/home/user/api_db.sqlite'
LEGACY = '/home/user/legacy_keys.json'
SECRET = '/home/user/hmac_secret.txt'
TIMESTAMP = '2024-01-01T00:00:00Z'


def run_script(path):
    return subprocess.run(
        ['python3', path],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )


def expected_rows(data, secret):
    return sorted([
        (
            entry['user_id'],
            hmac.new(
                secret.encode('utf-8'),
                entry['legacy_key'].encode('utf-8'),
                hashlib.sha256,
            ).hexdigest(),
            TIMESTAMP,
        )
        for entry in data
    ])


def read_rows():
    with sqlite3.connect(DB) as conn:
        return conn.execute(
            'SELECT user_id, hmac_hash, migrated_at '
            'FROM api_credentials ORDER BY user_id ASC'
        ).fetchall()


def execute_migration():
    if os.path.exists(DB):
        os.remove(DB)
    result = run_script(MIGRATE)
    assert result.returncode == 0, (
        f'Executing {MIGRATE} failed with exit code {result.returncode}.\n'
        f'STDOUT:\n{result.stdout}\nSTDERR:\n{result.stderr}'
    )
    assert os.path.isfile(DB), f'{MIGRATE} did not create {DB}'


def test_scripts_exist_and_parse():
    assert os.path.isfile(MIGRATE), f'The migration script {MIGRATE} is missing.'
    assert os.path.isfile(AUTH_TEST), f'The test script {AUTH_TEST} is missing.'
    ast.parse(open(MIGRATE, encoding='utf-8').read(), filename=MIGRATE)
    ast.parse(open(AUTH_TEST, encoding='utf-8').read(), filename=AUTH_TEST)


def test_migrate_script_execution_and_transformation():
    original_legacy = open(LEGACY, 'rb').read()
    original_secret = open(SECRET, 'rb').read()
    fixture_secret = 'verification_' + secrets.token_hex(24)
    fixture_data = [
        {'user_id': 1, 'legacy_key': 'alpha123'},
        {'user_id': 19, 'legacy_key': 'key_' + secrets.token_hex(15)},
        {'user_id': 207, 'legacy_key': 'unicode-key-ß-' + secrets.token_hex(8)},
    ]

    try:
        with open(LEGACY, 'w', encoding='utf-8') as f:
            json.dump(fixture_data, f)
        with open(SECRET, 'w', encoding='utf-8') as f:
            f.write(fixture_secret + '\n')

        execute_migration()
        assert read_rows() == expected_rows(fixture_data, fixture_secret)
    finally:
        with open(LEGACY, 'wb') as f:
            f.write(original_legacy)
        with open(SECRET, 'wb') as f:
            f.write(original_secret)
        execute_migration()


def test_api_db_sqlite_state():
    assert os.path.isfile(DB), f'The database file {DB} does not exist.'
    assert os.path.isfile(LEGACY), f'Missing {LEGACY}'
    assert os.path.isfile(SECRET), f'Missing {SECRET}'

    with open(LEGACY, encoding='utf-8') as f:
        legacy_data = json.load(f)
    with open(SECRET, encoding='utf-8') as f:
        secret = f.read().strip()

    try:
        with sqlite3.connect(DB) as conn:
            columns = {row[1] for row in conn.execute('PRAGMA table_info(api_credentials)')}
            assert {'user_id', 'hmac_hash', 'migrated_at'}.issubset(columns), (
                'The api_credentials table is missing required columns.'
            )
            rows = conn.execute(
                'SELECT user_id, hmac_hash, migrated_at '
                'FROM api_credentials ORDER BY user_id ASC'
            ).fetchall()
    except sqlite3.Error as exc:
        pytest.fail(f'SQLite error when accessing {DB}: {exc}')

    expected = expected_rows(legacy_data, secret)
    assert len(rows) == len(expected), (
        f'Expected {len(expected)} rows in api_credentials, but found {len(rows)}.'
    )
    for index, row in enumerate(rows):
        assert row == expected[index], (
            f'Row {index} mismatch. Expected {expected[index]}, got {row}.'
        )


def test_test_api_auth_structure_and_behavior():
    source = open(AUTH_TEST, encoding='utf-8').read()
    tree = ast.parse(source, filename=AUTH_TEST)

    test_methods = [
        node
        for cls in tree.body
        if isinstance(cls, ast.ClassDef)
        for node in cls.body
        if isinstance(node, (ast.FunctionDef, ast.AsyncFunctionDef))
        and node.name.startswith('test')
    ]
    assert test_methods, 'The unittest file must contain at least one test method.'

    has_hmac_new = any(
        isinstance(node, ast.Call)
        and ((isinstance(node.func, ast.Attribute) and node.func.attr == 'new')
             or (isinstance(node.func, ast.Name) and node.func.id == 'new'))
        for node in ast.walk(tree)
    )
    has_sha256 = any(
        (isinstance(node, ast.Attribute) and node.attr == 'sha256')
        or (isinstance(node, ast.Name) and node.id == 'sha256')
        for node in ast.walk(tree)
    )
    assert has_hmac_new and has_sha256, (
        'The unittest must dynamically compute an HMAC-SHA256 value.'
    )

    has_main_guard = False
    for node in tree.body:
        if not isinstance(node, ast.If):
            continue
        comparison = node.test
        if not (
            isinstance(comparison, ast.Compare)
            and isinstance(comparison.left, ast.Name)
            and comparison.left.id == '__name__'
            and len(comparison.ops) == 1
            and isinstance(comparison.ops[0], ast.Eq)
            and len(comparison.comparators) == 1
            and isinstance(comparison.comparators[0], ast.Constant)
            and comparison.comparators[0].value == '__main__'
        ):
            continue
        if any(
            isinstance(child, ast.Call)
            and isinstance(child.func, ast.Attribute)
            and isinstance(child.func.value, ast.Name)
            and child.func.value.id == 'unittest'
            and child.func.attr == 'main'
            for child in ast.walk(node)
        ):
            has_main_guard = True
            break
    assert has_main_guard, (
        "The test file must include an if __name__ == '__main__': unittest.main() block."
    )

    original_secret = open(SECRET, 'rb').read()
    dynamic_secret = 'auth_test_' + secrets.token_hex(24)
    try:
        with open(SECRET, 'w', encoding='utf-8') as f:
            f.write(dynamic_secret + '\n')
        execute_migration()

        good = run_script(AUTH_TEST)
        assert good.returncode == 0, (
            f'Executing {AUTH_TEST} against a valid dynamically generated database failed.\n'
            f'STDOUT:\n{good.stdout}\nSTDERR:\n{good.stderr}'
        )

        with sqlite3.connect(DB) as conn:
            conn.execute(
                "UPDATE api_credentials SET hmac_hash = ? WHERE user_id = 1",
                ('0' * 64,),
            )
            conn.commit()

        bad = run_script(AUTH_TEST)
        assert bad.returncode != 0, (
            'The authentication unittest still succeeded after the HMAC hash for '
            'user_id = 1 was deliberately corrupted.'
        )
    finally:
        with open(SECRET, 'wb') as f:
            f.write(original_secret)
        execute_migration()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
