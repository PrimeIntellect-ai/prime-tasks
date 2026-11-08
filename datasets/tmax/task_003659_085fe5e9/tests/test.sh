#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import glob
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
import tempfile
import pytest

SCRIPT_PATH = '/home/user/audit_pipeline.sh'
JSON_PATH = '/home/user/violations.json'
DB_PATH = '/home/user/sys_audit.db'


def expected_violations():
    conn = sqlite3.connect(DB_PATH)
    try:
        rows = conn.execute("""
            SELECT
                u.name AS user,
                r.name AS resource,
                d.name AS resource_department
            FROM edges e_acc
            JOIN nodes u ON e_acc.source = u.id AND u.type = 'User'
            JOIN nodes r ON e_acc.target = r.id AND r.type = 'Resource'
            JOIN edges e_bel ON e_bel.source = r.id AND e_bel.relation = 'BELONGS_TO'
            JOIN nodes d ON e_bel.target = d.id AND d.type = 'Department'
            WHERE e_acc.relation = 'ACCESSED'
              AND NOT EXISTS (
                  SELECT 1 FROM edges e_mem
                  WHERE e_mem.source = u.id
                    AND e_mem.target = d.id
                    AND e_mem.relation = 'MEMBER_OF'
              )
            ORDER BY u.name ASC, r.name ASC
        """).fetchall()
    finally:
        conn.close()
    return [
        {'user': row[0], 'resource': row[1], 'resource_department': row[2]}
        for row in rows
    ]


def load_and_check_output(expected):
    assert os.path.exists(JSON_PATH), f'The output file {JSON_PATH} does not exist.'
    assert os.path.isfile(JSON_PATH), f'{JSON_PATH} is not a file.'
    try:
        with open(JSON_PATH, 'r') as f:
            actual = json.load(f)
    except json.JSONDecodeError:
        pytest.fail(f'The file {JSON_PATH} does not contain valid JSON.')

    assert isinstance(actual, list), f'The JSON in {JSON_PATH} must be an array.'
    assert len(actual) == len(expected), f'Expected {len(expected)} violations, found {len(actual)}.'

    expected_keys = {'user', 'resource', 'resource_department'}
    for i, (item, wanted) in enumerate(zip(actual, expected)):
        assert isinstance(item, dict), f'Item at index {i} is not a JSON object.'
        assert set(item.keys()) == expected_keys, (
            f'Item at index {i} has incorrect keys. Expected {expected_keys}, found {set(item.keys())}.'
        )
        assert item['user'] == wanted['user'], (
            f"Item at index {i} has wrong user. Expected '{wanted['user']}', found '{item['user']}'."
        )
        assert item['resource'] == wanted['resource'], (
            f"Item at index {i} has wrong resource. Expected '{wanted['resource']}', found '{item['resource']}'."
        )
        assert item['resource_department'] == wanted['resource_department'], (
            f"Item at index {i} has wrong resource_department. Expected "
            f"'{wanted['resource_department']}', found '{item['resource_department']}'."
        )


def test_audit_pipeline_script_exists_and_executable():
    assert os.path.exists(SCRIPT_PATH), f'The script {SCRIPT_PATH} does not exist.'
    assert os.path.isfile(SCRIPT_PATH), f'{SCRIPT_PATH} is not a file.'
    st = os.stat(SCRIPT_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f'The script {SCRIPT_PATH} is not executable by the user.'


def test_violations_json_exists():
    assert os.path.exists(JSON_PATH), f'The output file {JSON_PATH} does not exist.'
    assert os.path.isfile(JSON_PATH), f'{JSON_PATH} is not a file.'


def test_violations_json_content():
    load_and_check_output(expected_violations())


def install_command_wrapper(command, trace_dir):
    path = shutil.which(command)
    assert path, f'{command} is not installed.'
    path = os.path.realpath(path)
    real_path = path + '.verifier-real'
    assert not os.path.exists(real_path)
    os.rename(path, real_path)
    wrapper = f'''#!/bin/bash
set -o pipefail
trace={trace_dir!r}
id="{command}.$$.$RANDOM"
printf '%s\\n' "$@" > "$trace/$id.args"
cat > "$trace/$id.stdin"
exec {real_path!r} "$@" < "$trace/$id.stdin"
'''
    with open(path, 'w') as f:
        f.write(wrapper)
    os.chmod(path, 0o755)
    return path, real_path


def restore_command_wrapper(installed):
    path, real_path = installed
    try:
        if os.path.exists(path):
            os.unlink(path)
    finally:
        if os.path.exists(real_path):
            os.rename(real_path, path)


def invocation_records(trace_dir, command):
    records = []
    for args_path in glob.glob(os.path.join(trace_dir, command + '.*.args')):
        base = args_path[:-5]
        with open(args_path, 'rb') as f:
            args = f.read()
        with open(base + '.stdin', 'rb') as f:
            stdin = f.read()
        records.append((args, stdin))
    return records


def test_script_executes_reindex_sql_and_jq_pipeline_on_fresh_data():
    # Add cases unknown to the submitted script so a precomputed JSON file cannot pass.
    conn = sqlite3.connect(DB_PATH)
    try:
        base = conn.execute('SELECT COALESCE(MAX(id), 0) FROM nodes').fetchone()[0] + 100
        department = base
        user_violation = base + 1
        user_member = base + 2
        resource_one = base + 3
        resource_two = base + 4
        conn.executemany('INSERT INTO nodes(id, type, name) VALUES (?, ?, ?)', [
            (department, 'Department', 'Zeta Dynamic Department'),
            (user_violation, 'User', 'Aaron Dynamic'),
            (user_member, 'User', 'Zoe "Dynamic"'),
            (resource_one, 'Resource', 'Ampersand & File'),
            (resource_two, 'Resource', 'Quoted "File"'),
        ])
        conn.executemany('INSERT INTO edges(source, target, relation) VALUES (?, ?, ?)', [
            (resource_one, department, 'BELONGS_TO'),
            (resource_two, department, 'BELONGS_TO'),
            (user_violation, resource_one, 'ACCESSED'),
            (user_violation, resource_two, 'ACCESSED'),
            (user_member, department, 'MEMBER_OF'),
            (user_member, resource_two, 'ACCESSED'),
        ])
        conn.commit()
    finally:
        conn.close()

    expected = expected_violations()
    if os.path.exists(JSON_PATH):
        os.unlink(JSON_PATH)

    trace_dir = tempfile.mkdtemp(prefix='audit-trace-')
    installed = []
    try:
        installed.append(install_command_wrapper('sqlite3', trace_dir))
        installed.append(install_command_wrapper('jq', trace_dir))
        result = subprocess.run(
            [SCRIPT_PATH],
            cwd='/home/user',
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=30,
        )
    finally:
        for item in reversed(installed):
            restore_command_wrapper(item)

    assert result.returncode == 0, (
        f'audit_pipeline.sh failed with exit code {result.returncode}. '
        f'stdout: {result.stdout!r}; stderr: {result.stderr!r}'
    )
    load_and_check_output(expected)

    sqlite_calls = invocation_records(trace_dir, 'sqlite3')
    jq_calls = invocation_records(trace_dir, 'jq')
    assert sqlite_calls, 'The script did not execute the sqlite3 command.'
    assert jq_calls, 'The script did not execute the jq command.'

    def text_of(call):
        return (call[0] + b'\n' + call[1]).decode('utf-8', errors='replace')

    db_calls = [call for call in sqlite_calls if 'sys_audit.db' in text_of(call)]
    assert db_calls, 'sqlite3 was not invoked on sys_audit.db.'
    assert any(re.search(r'(?i)\bREINDEX\b\s*;', text_of(call)) for call in db_calls), (
        'The script did not execute REINDEX; on sys_audit.db.'
    )
    assert any(
        re.search(r'(?i)\bSELECT\b', text_of(call))
        and all(term in text_of(call).upper() for term in ('ACCESSED', 'BELONGS_TO', 'MEMBER_OF'))
        for call in db_calls
    ), 'The script did not submit the required graph-pattern SQL query to sqlite3.'

    jq_input = b'\n'.join(stdin for _, stdin in jq_calls)
    assert jq_input.strip(), 'jq was not used as a pipeline consuming query output.'
    assert b'Aaron Dynamic' in jq_input and b'Ampersand & File' in jq_input, (
        'The dynamically queried SQLite rows were not piped through jq.'
    )
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
