#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import sqlite3
import subprocess
import tempfile
import pwd
import pytest

DB = '/app/warehouse.db'
SOURCE = '/home/user/etl_query.c'
BINARY = '/home/user/etl_query'
RESULTS = '/home/user/results.csv'


def expected_output(status, min_priority, limit, offset):
    conn = sqlite3.connect(DB)
    try:
        rows = conn.execute(
            '''SELECT id, name, status, priority, created_at
               FROM users NOT INDEXED
               WHERE status = ? AND priority > ?
               ORDER BY created_at DESC, id ASC
               LIMIT ? OFFSET ?''',
            (status, min_priority, limit, offset),
        ).fetchall()
    finally:
        conn.close()
    return ''.join(','.join(str(value) for value in row) + '\n' for row in rows).encode('utf-8')


def run_as_user(argv):
    account = pwd.getpwnam('user')

    def demote():
        os.initgroups(account.pw_name, account.pw_gid)
        os.setgid(account.pw_gid)
        os.setuid(account.pw_uid)

    return subprocess.run(
        argv,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        env={**os.environ, 'HOME': account.pw_dir},
        preexec_fn=demote,
    )


@pytest.fixture(scope='session')
def compiled_source_binary():
    account = pwd.getpwnam('user')
    build_dir = tempfile.mkdtemp(prefix='etl-source-build-')
    os.chown(build_dir, account.pw_uid, account.pw_gid)
    output = os.path.join(build_dir, 'etl_query_from_source')
    result = run_as_user([
        'gcc', '-std=c11', '-O2', SOURCE, '-o', output, '-lsqlite3'
    ])
    assert result.returncode == 0, (
        'etl_query.c does not compile successfully:\n' +
        result.stderr.decode('utf-8', errors='replace')
    )
    assert os.path.isfile(output) and os.access(output, os.X_OK)
    return output


def test_database_index_is_repaired():
    conn = sqlite3.connect(DB)
    try:
        index_row = conn.execute(
            "SELECT type, tbl_name, sql FROM sqlite_master WHERE name = 'idx_status'"
        ).fetchone()
        assert index_row is not None, 'idx_status is missing.'
        assert index_row[0] == 'index' and index_row[1] == 'users'
        assert index_row[2] is not None

        integrity = [row[0] for row in conn.execute('PRAGMA integrity_check').fetchall()]
        assert integrity == ['ok'], 'SQLite integrity_check reports: ' + '; '.join(integrity)

        for status in ('ACTIVE', 'INACTIVE'):
            indexed = conn.execute(
                '''SELECT id, name, status, priority, created_at
                   FROM users INDEXED BY idx_status
                   WHERE status = ?
                   ORDER BY created_at DESC, id ASC''',
                (status,),
            ).fetchall()
            table_scan = conn.execute(
                '''SELECT id, name, status, priority, created_at
                   FROM users NOT INDEXED
                   WHERE status = ?
                   ORDER BY created_at DESC, id ASC''',
                (status,),
            ).fetchall()
            assert indexed == table_scan, f'idx_status returns incorrect rows for {status}.'
    finally:
        conn.close()


def test_c_program_exists_and_uses_parameterized_sql():
    assert os.path.isfile(SOURCE), 'C source file /home/user/etl_query.c is missing.'
    assert os.path.getsize(SOURCE) > 0, 'C source file is empty.'
    assert os.path.isfile(BINARY), 'Compiled binary /home/user/etl_query is missing.'
    assert os.access(BINARY, os.X_OK), '/home/user/etl_query is not executable.'
    with open(BINARY, 'rb') as f:
        assert f.read(4) == b'\x7fELF', '/home/user/etl_query is not an ELF executable.'

    source = open(SOURCE, 'r', encoding='utf-8', errors='replace').read()
    without_comments = re.sub(r'/\*.*?\*/|//[^\n]*', '', source, flags=re.S)
    assert re.search(r'\bsqlite3_prepare_v2\s*\(', without_comments), 'sqlite3_prepare_v2 is required.'
    assert re.search(r'\bsqlite3_bind_text\s*\(', without_comments), 'The status must be bound with sqlite3_bind_text.'
    integer_binds = re.findall(r'\bsqlite3_bind_(?:int|int64)\s*\(', without_comments)
    assert len(integer_binds) >= 3, 'Priority, LIMIT, and OFFSET must be bound as integers.'
    assert without_comments.count('?') >= 4, 'The prepared query must contain parameter placeholders.'
    assert not re.search(r'\bsqlite3_exec\s*\(', without_comments), 'The query tool must use the prepared-statement API, not sqlite3_exec.'
    assert not re.search(r'\b(?:system|popen)\s*\(', without_comments), 'The query tool must query through SQLite, not invoke another command.'


def test_results_csv_is_exact_and_was_produced_by_tool(compiled_source_binary):
    assert os.path.exists(RESULTS), f'Results CSV file is missing at {RESULTS}.'
    with open(RESULTS, 'rb') as f:
        actual = f.read()
    expected = expected_output('ACTIVE', 50, 500, 0)
    assert actual == expected, 'results.csv is not the exact ordered five-column CSV required.'

    submitted = run_as_user([BINARY, 'ACTIVE', '50', '500', '0'])
    assert submitted.returncode == 0, submitted.stderr.decode('utf-8', errors='replace')
    assert submitted.stdout == expected, 'The submitted executable does not reproduce results.csv correctly.'


def test_binaries_accept_exactly_four_arguments(compiled_source_binary):
    for executable in (BINARY, compiled_source_binary):
        assert run_as_user([executable]).returncode != 0, 'Tool accepted zero arguments.'
        assert run_as_user([executable, 'ACTIVE', '50', '10']).returncode != 0, 'Tool accepted too few arguments.'
        assert run_as_user([executable, 'ACTIVE', '50', '10', '0', 'extra']).returncode != 0, 'Tool accepted too many arguments.'


def test_parameterized_query_behavior(compiled_source_binary):
    rng = secrets.SystemRandom()
    cases = [
        ('ACTIVE', 50, 500, 0),
        ('INACTIVE', 73, 31, 7),
        ("ACTIVE' OR 1=1 --", 0, 25, 0),
        ('DOES_NOT_EXIST', 20, 10, 0),
        ('ACTIVE', rng.randint(1, 99), rng.randint(1, 45), rng.randint(0, 40)),
        ('INACTIVE', rng.randint(1, 99), rng.randint(1, 45), rng.randint(0, 40)),
    ]
    for executable in (BINARY, compiled_source_binary):
        for status, minimum, limit, offset in cases:
            result = run_as_user([
                executable, status, str(minimum), str(limit), str(offset)
            ])
            assert result.returncode == 0, (
                f'{executable} failed for valid arguments: ' +
                result.stderr.decode('utf-8', errors='replace')
            )
            assert result.stdout == expected_output(status, minimum, limit, offset), (
                f'{executable} returned incorrect, malformed, or misordered CSV for '
                f'{status!r}, {minimum}, {limit}, {offset}.'
            )
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
