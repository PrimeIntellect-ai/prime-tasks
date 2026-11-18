#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import shutil
import sqlite3
import subprocess
import tempfile
import uuid

import pytest

CSV_PATH = "/home/user/audit_results.csv"
DB_PATH = "/home/user/audit.db"

EXPECTED_ROWS = [
    ["employee", "access_time", "top_manager"],
    ["Alice CEO", "2023-01-01 00:00:00", "Alice CEO"],
    ["Charlie Director", "2023-10-05 14:00:00", "Alice CEO"],
    ["Eve Employee", "2023-10-01 10:00:00", "Alice CEO"],
    ["Grace Contractor", "2023-09-15 08:30:00", "Alice CEO"]
]


def read_csv():
    with open(CSV_PATH, 'r', newline='', encoding='utf-8') as f:
        rows = list(csv.reader(f))
    return [[cell.strip() for cell in row] for row in rows if row]


def test_audit_results_exists():
    """Test that the audit results CSV file exists."""
    assert os.path.isfile(CSV_PATH), f"Expected result file not found at {CSV_PATH}"


def test_audit_results_content():
    """Test that the audit results CSV contains the correct data."""
    actual_rows_cleaned = read_csv()

    assert len(actual_rows_cleaned) == len(EXPECTED_ROWS), \
        f"Expected {len(EXPECTED_ROWS)} rows in the CSV, but found {len(actual_rows_cleaned)}."

    for i, (actual, expected) in enumerate(zip(actual_rows_cleaned, EXPECTED_ROWS)):
        assert actual == expected, \
            f"Row {i+1} mismatch. Expected: {expected}, Actual: {actual}"


def find_query_artifacts():
    artifacts = []
    for root, dirs, files in os.walk('/home/user'):
        dirs[:] = [d for d in dirs if not d.startswith('.')]
        for filename in files:
            path = os.path.join(root, filename)
            if path in (CSV_PATH, DB_PATH) or os.path.islink(path):
                continue
            try:
                if os.path.getsize(path) > 1024 * 1024:
                    continue
                with open(path, 'r', encoding='utf-8') as f:
                    text = f.read()
            except (OSError, UnicodeDecodeError):
                continue
            if re.search(r'\bWITH\s+RECURSIVE\b', text, re.IGNORECASE):
                is_shell = filename.endswith(('.sh', '.bash')) or text.startswith('#!')
                if not is_shell or re.search(r'(^|[^A-Za-z0-9_])sqlite3([^A-Za-z0-9_]|$)', text):
                    artifacts.append((path, text, is_shell))
    return artifacts


def derive_expected():
    con = sqlite3.connect(DB_PATH)
    try:
        names = dict(con.execute('SELECT id, name FROM users'))
        managers = dict(con.execute('SELECT subordinate_id, manager_id FROM reporting'))
        accesses = con.execute(
            "SELECT user_id, MIN(access_time) FROM access_events "
            "WHERE resource_name = 'SECRET_VAULT' GROUP BY user_id"
        ).fetchall()
    finally:
        con.close()

    rows = []
    for user_id, access_time in accesses:
        current = user_id
        seen = set()
        while current in managers:
            assert current not in seen, 'Unexpected cycle in reporting hierarchy'
            seen.add(current)
            current = managers[current]
        rows.append([names[user_id], access_time, names[current]])
    rows.sort(key=lambda row: row[0])
    return [["employee", "access_time", "top_manager"]] + rows


def mutate_database():
    token = uuid.uuid4().hex[:12]
    con = sqlite3.connect(DB_PATH)
    try:
        max_user = con.execute('SELECT COALESCE(MAX(id), 0) FROM users').fetchone()[0]
        max_event = con.execute('SELECT COALESCE(MAX(event_id), 0) FROM access_events').fetchone()[0]
        root_id = max_user + 1
        employee_id = max_user + 2
        root_name = 'Root ' + token
        employee_name = 'Dynamic ' + token
        con.execute('INSERT INTO users(id, name) VALUES (?, ?)', (root_id, root_name))
        con.execute('INSERT INTO users(id, name) VALUES (?, ?)', (employee_id, employee_name))
        con.execute('INSERT INTO reporting(subordinate_id, manager_id) VALUES (1, ?)', (root_id,))
        con.execute('INSERT INTO reporting(subordinate_id, manager_id) VALUES (?, 4)', (employee_id,))
        con.execute(
            "INSERT INTO access_events(event_id, user_id, resource_name, access_time) "
            "VALUES (?, ?, 'SECRET_VAULT', '2022-02-03 04:05:06')",
            (max_event + 1, employee_id)
        )
        con.execute(
            "INSERT INTO access_events(event_id, user_id, resource_name, access_time) "
            "VALUES (?, ?, 'SECRET_VAULT', '2024-05-06 07:08:09')",
            (max_event + 2, employee_id)
        )
        con.execute(
            "INSERT INTO access_events(event_id, user_id, resource_name, access_time) "
            "VALUES (?, 6, 'SECRET_VAULT', '2021-01-02 03:04:05')",
            (max_event + 3,)
        )
        con.commit()
    finally:
        con.close()


def test_recursive_query_artifact_executes_via_sqlite3():
    artifacts = find_query_artifacts()
    assert artifacts, 'No SQL query or bash script containing a recursive CTE was found under /home/user'

    with tempfile.TemporaryDirectory() as tmp:
        db_backup = os.path.join(tmp, 'audit.db.backup')
        csv_backup = os.path.join(tmp, 'audit_results.csv.backup')
        shutil.copy2(DB_PATH, db_backup)
        shutil.copy2(CSV_PATH, csv_backup)

        wrapper_dir = os.path.join(tmp, 'bin')
        os.mkdir(wrapper_dir)
        trace_path = os.path.join(tmp, 'sqlite3.trace')
        wrapper = os.path.join(wrapper_dir, 'sqlite3')
        with open(wrapper, 'w', encoding='utf-8') as f:
            f.write('''#!/bin/bash
set -e
printf 'ARGS:' >> "$SQLITE_TRACE"
printf ' %q' "$@" >> "$SQLITE_TRACE"
printf '\nSTDIN:\n' >> "$SQLITE_TRACE"
tmpin=$(mktemp)
cat > "$tmpin"
cat "$tmpin" >> "$SQLITE_TRACE"
printf '\nEND_CALL\n' >> "$SQLITE_TRACE"
/usr/bin/sqlite3 "$@" < "$tmpin"
status=$?
rm -f "$tmpin"
exit $status
''')
        os.chmod(wrapper, 0o755)

        env = os.environ.copy()
        env['PATH'] = wrapper_dir + os.pathsep + env.get('PATH', '')
        env['SQLITE_TRACE'] = trace_path
        errors = []
        passed = False

        try:
            for path, text, is_shell in artifacts:
                shutil.copy2(db_backup, DB_PATH)
                mutate_database()
                expected = derive_expected()
                if os.path.exists(CSV_PATH):
                    os.remove(CSV_PATH)
                if os.path.exists(trace_path):
                    os.remove(trace_path)

                try:
                    if is_shell:
                        result = subprocess.run(
                            ['/bin/bash', path], env=env, stdin=subprocess.DEVNULL,
                            stdout=subprocess.PIPE, stderr=subprocess.PIPE,
                            text=True, timeout=20
                        )
                    else:
                        with open(path, 'rb') as query, open(CSV_PATH, 'wb') as output:
                            result = subprocess.run(
                                ['sqlite3', '-header', '-csv', DB_PATH], env=env,
                                stdin=query, stdout=output, stderr=subprocess.PIPE,
                                timeout=20
                            )
                    assert result.returncode == 0, f'artifact exited with status {result.returncode}'
                    assert os.path.isfile(trace_path), 'artifact did not invoke the sqlite3 command-line tool'
                    with open(trace_path, 'r', encoding='utf-8', errors='replace') as f:
                        trace = f.read()
                    assert 'audit.db' in trace, 'sqlite3 was not invoked on the audit database'
                    assert re.search(r'\bWITH\s+RECURSIVE\b', text, re.IGNORECASE), \
                        'executed artifact does not contain a recursive CTE'
                    assert os.path.isfile(CSV_PATH), 'executed artifact did not create audit_results.csv'
                    actual = read_csv()
                    assert actual == expected, \
                        f'executed artifact produced incorrect results for changed database: {actual!r}'
                    passed = True
                    break
                except Exception as exc:
                    errors.append(f'{path}: {exc}')

            assert passed, 'No recursive query artifact passed execution checks. ' + ' | '.join(errors)
        finally:
            shutil.copy2(db_backup, DB_PATH)
            shutil.copy2(csv_backup, CSV_PATH)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
