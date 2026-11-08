#!/bin/bash
set +e
mkdir -p /logs/verifier
rm -rf /tmp/audit_sqlite_calls /tmp/audit_db.backup /tmp/sqlite3.real /tmp/test_final_state.py /tmp/audit_script_status

cleanup() {
    if [ -e /tmp/sqlite3.real ]; then
        rm -f /usr/bin/sqlite3
        mv /tmp/sqlite3.real /usr/bin/sqlite3
    fi
    if [ -e /tmp/audit_db.backup ]; then
        cp -p /tmp/audit_db.backup /home/user/audit.db
        rm -f /tmp/audit_db.backup
    fi
}
trap cleanup EXIT

prepare_and_run() {
    cp -p /home/user/audit.db /tmp/audit_db.backup || return 1

    python3 - <<'PY' || return 1
import secrets
import sqlite3

p = '/home/user/audit.db'
conn = sqlite3.connect(p)
c = conn.cursor()
base = 1000000 + secrets.randbelow(800000000)
e1, e2, e3 = base, base + 1, base + 2
r1, r2, r3 = base + 100, base + 101, base + 102
tag = secrets.token_hex(8)
c.executemany('INSERT INTO employees(emp_id,name,department) VALUES (?,?,?)', [
    (e1, 'Quinn, "' + tag + '"', 'Dynamic-' + tag),
    (e2, 'Riley-' + tag, 'Dynamic-' + tag),
    (e3, 'NoHigh-' + tag, 'Dynamic-' + tag),
])
c.executemany('INSERT INTO resources(resource_id,name,sensitivity) VALUES (?,?,?)', [
    (r1, 'Vault-' + tag, 'HIGH'),
    (r2, 'Plans-' + tag, 'HIGH'),
    (r3, 'Public-' + tag, 'LOW'),
])
c.executemany('INSERT INTO access_logs(emp_id,resource_id) VALUES (?,?)', [
    (e1, r1), (e1, r1), (e1, r2),
    (e2, r1), (e2, r2),
    (e3, r3),
    (2, r2),
])
conn.commit()
conn.close()
PY

    mkdir -p /tmp/audit_sqlite_calls || return 1
    mv /usr/bin/sqlite3 /tmp/sqlite3.real || return 1
    cat > /usr/bin/sqlite3 <<'WRAPPER' || return 1
#!/bin/bash
call_dir=$(mktemp -d /tmp/audit_sqlite_calls/call.XXXXXX) || exit 125
printf '%s\0' "$@" > "$call_dir/args.bin"
cat > "$call_dir/stdin.sql"
readlink "/proc/$$/fd/1" > "$call_dir/stdout_target" 2>/dev/null || true
/tmp/sqlite3.real "$@" < "$call_dir/stdin.sql" > "$call_dir/output.bin"
status=$?
cat "$call_dir/output.bin"
exit "$status"
WRAPPER
    chmod 755 /usr/bin/sqlite3 || return 1

    rm -f /home/user/audit_report.csv
    /home/user/run_audit.sh
    echo "$?" > /tmp/audit_script_status
    return 0
}

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import glob
import os
import re
import sqlite3
import stat


def get_expected_data(db_path):
    conn = sqlite3.connect(db_path)
    conn.row_factory = sqlite3.Row
    rows = conn.execute("""
        SELECT a.emp_id, e.name, e.department, a.resource_id
        FROM access_logs a
        JOIN resources r ON a.resource_id = r.resource_id
        JOIN employees e ON a.emp_id = e.emp_id
        WHERE r.sensitivity = 'HIGH'
    """).fetchall()

    emp_stats = {}
    emp_resources = {}
    for row in rows:
        emp_id = row['emp_id']
        if emp_id not in emp_stats:
            emp_stats[emp_id] = {
                'name': row['name'],
                'department': row['department'],
                'high_risk_accesses': 0,
            }
            emp_resources[emp_id] = set()
        emp_stats[emp_id]['high_risk_accesses'] += 1
        emp_resources[emp_id].add(row['resource_id'])

    dept_averages = {}
    for stats in emp_stats.values():
        dept_averages.setdefault(stats['department'], []).append(stats['high_risk_accesses'])
    dept_averages = {d: round(sum(v) / len(v), 2) for d, v in dept_averages.items()}

    expected = []
    for emp_id, stats in emp_stats.items():
        degree = sum(
            1 for other_id, resources in emp_resources.items()
            if other_id != emp_id and emp_resources[emp_id].intersection(resources)
        )
        expected.append({
            'emp_id': emp_id,
            'name': stats['name'],
            'department': stats['department'],
            'high_risk_accesses': stats['high_risk_accesses'],
            'dept_avg_accesses': dept_averages[stats['department']],
            'co_access_degree': degree,
        })
    conn.close()
    expected.sort(key=lambda x: (-x['co_access_degree'], -x['high_risk_accesses'], x['emp_id']))
    return expected


def test_script_exists_and_executable():
    script_path = '/home/user/run_audit.sh'
    assert os.path.exists(script_path), f'Script {script_path} does not exist.'
    assert os.path.isfile(script_path), f'{script_path} is not a file.'
    st = os.stat(script_path)
    assert bool(st.st_mode & stat.S_IXUSR), f'Script {script_path} is not executable.'


def test_script_was_executed_as_required():
    with open('/tmp/audit_script_status') as f:
        assert int(f.read().strip()) == 0, 'run_audit.sh exited unsuccessfully.'

    calls = glob.glob('/tmp/audit_sqlite_calls/call.*')
    assert len(calls) == 1, f'Expected exactly one sqlite3 invocation, got {len(calls)}.'
    call = calls[0]

    raw_args = open(os.path.join(call, 'args.bin'), 'rb').read().split(b'\0')
    args = [x.decode('utf-8', 'replace') for x in raw_args if x]
    stdin_sql = open(os.path.join(call, 'stdin.sql'), encoding='utf-8', errors='replace').read()
    sql_parts = [a for a in args if re.search(r'\b(?:WITH|SELECT)\b', a, re.I)]
    sql_parts.append('\n'.join(line for line in stdin_sql.splitlines() if not line.lstrip().startswith('.')))
    sql = '\n'.join(sql_parts)

    assert re.search(r'\bOVER\s*\(', sql, re.I), 'The executed SQLite query does not use a window function.'

    statements = []
    pending = ''
    for ch in sql:
        pending += ch
        if sqlite3.complete_statement(pending):
            if re.search(r'\b(?:WITH|SELECT)\b', pending, re.I):
                statements.append(pending)
            pending = ''
    if re.search(r'\b(?:WITH|SELECT)\b', pending, re.I):
        statements.append(pending)
    assert len(statements) == 1, f'Expected one SQLite query, found {len(statements)}.'

    target = open(os.path.join(call, 'stdout_target'), encoding='utf-8').read().strip()
    assert target == '/home/user/audit_report.csv', \
        f'sqlite3 output was not redirected directly to audit_report.csv (target was {target!r}).'
    with open(os.path.join(call, 'output.bin'), 'rb') as f:
        sqlite_output = f.read()
    with open('/home/user/audit_report.csv', 'rb') as f:
        report_output = f.read()
    assert report_output == sqlite_output, 'audit_report.csv is not the direct output produced by sqlite3.'


def test_csv_output():
    csv_path = '/home/user/audit_report.csv'
    db_path = '/home/user/audit.db'
    assert os.path.exists(csv_path), f'Output file {csv_path} does not exist. Did the script run successfully?'
    assert os.path.exists(db_path), f'Database file {db_path} is missing.'

    expected_data = get_expected_data(db_path)
    with open(csv_path, 'r', encoding='utf-8', newline='') as f:
        reader = list(csv.reader(f))

    assert len(reader) > 0, 'CSV file is empty.'
    expected_header = ['emp_id', 'name', 'department', 'high_risk_accesses', 'dept_avg_accesses', 'co_access_degree']
    assert reader[0] == expected_header, f'CSV header mismatch. Expected {expected_header}, got {reader[0]}.'
    assert len(reader) - 1 == len(expected_data), f'Expected {len(expected_data)} rows, got {len(reader) - 1}.'

    for i, (actual_row, expected_row) in enumerate(zip(reader[1:], expected_data)):
        assert len(actual_row) == 6, f'Row {i+1}: expected 6 columns.'
        assert int(actual_row[0]) == expected_row['emp_id'], f'Row {i+1}: emp_id mismatch.'
        assert actual_row[1] == expected_row['name'], f'Row {i+1}: name mismatch.'
        assert actual_row[2] == expected_row['department'], f'Row {i+1}: department mismatch.'
        assert int(actual_row[3]) == expected_row['high_risk_accesses'], f'Row {i+1}: high_risk_accesses mismatch.'
        assert abs(float(actual_row[4]) - expected_row['dept_avg_accesses']) <= 0.01, f'Row {i+1}: dept_avg_accesses mismatch.'
        assert int(actual_row[5]) == expected_row['co_access_degree'], f'Row {i+1}: co_access_degree mismatch.'
TEST_EOF

prepare_and_run
prep_status=$?
if [ "$prep_status" -eq 0 ]; then
    python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1
    test_status=$?
else
    test_status=$prep_status
fi

if [ "$test_status" -eq 0 ]; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi

cleanup
trap - EXIT
exit 0
