#!/bin/bash
set -e
mkdir -p /logs/verifier

snapshot_dir=$(mktemp -d)
for path in /home/user/backups.db /home/user/nosql_backups.json /home/user/fixed_sql_report.csv /home/user/chain_result.txt /home/user/nosql_report.csv; do
    name=$(basename "$path")
    if [ -e "$path" ]; then
        cp -p "$path" "$snapshot_dir/$name"
        touch "$snapshot_dir/$name.present"
    fi
done

cleanup() {
    for path in /home/user/backups.db /home/user/nosql_backups.json /home/user/fixed_sql_report.csv /home/user/chain_result.txt /home/user/nosql_report.csv; do
        name=$(basename "$path")
        if [ -e "$snapshot_dir/$name.present" ]; then
            cp -p "$snapshot_dir/$name" "$path" || true
        else
            rm -f "$path" || true
        fi
    done
    rm -rf "$snapshot_dir" || true
}
trap cleanup EXIT

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import json
import csv
import subprocess
import uuid


def run_script(path, *args):
    return subprocess.run(
        [path, *args],
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=10,
        check=True,
    )


def expected_sql_rows():
    conn = sqlite3.connect('/home/user/backups.db')
    try:
        return conn.execute('''
            SELECT s.hostname, SUM(b.size_mb) as total_size_mb
            FROM servers s
            JOIN backup_jobs b ON s.id = b.server_id
            WHERE b.status = 'SUCCESS'
            GROUP BY s.hostname
            ORDER BY total_size_mb DESC;
        ''').fetchall()
    finally:
        conn.close()


def read_sql_report():
    csv_path = '/home/user/fixed_sql_report.csv'
    assert os.path.exists(csv_path), f'File {csv_path} is missing.'
    with open(csv_path, newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, f'{csv_path} is empty.'
    assert rows[0] == ['hostname', 'total_size_mb'], (
        f'Headers in {csv_path} are incorrect. Expected '
        f"['hostname', 'total_size_mb'], got {rows[0]}"
    )
    assert all(len(row) == 2 for row in rows[1:]), f'Malformed row in {csv_path}: {rows}'
    actual_data = [(row[0], int(row[1])) for row in rows[1:] if len(row) == 2]
    return actual_data


def test_task1_fixed_sql_report():
    script_path = '/home/user/sql_report.sh'
    csv_path = '/home/user/fixed_sql_report.csv'
    assert os.path.isfile(script_path), f'Script {script_path} is missing.'
    assert os.access(script_path, os.X_OK), f'Script {script_path} is not executable.'

    os.remove(csv_path) if os.path.exists(csv_path) else None
    run_script(script_path)

    expected_rows = expected_sql_rows()
    actual_data = read_sql_report()
    assert actual_data == expected_rows, (
        f'Data in {csv_path} does not match expected derived data. '
        f'Expected {expected_rows}, got {actual_data}'
    )


def test_task1_reacts_to_database_changes():
    token = uuid.uuid4().hex
    hostname = f'dynamic-{token}'
    conn = sqlite3.connect('/home/user/backups.db')
    try:
        server_id = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM servers').fetchone()[0]
        conn.execute('INSERT INTO servers(id, hostname) VALUES (?, ?)', (server_id, hostname))
        conn.execute(
            'INSERT INTO backup_jobs(id, server_id, type, status, size_mb) VALUES (?, ?, ?, ?, ?)',
            (f'dyn-success-{token}', server_id, 'FULL', 'SUCCESS', 987654),
        )
        conn.execute(
            'INSERT INTO backup_jobs(id, server_id, type, status, size_mb) VALUES (?, ?, ?, ?, ?)',
            (f'dyn-failed-{token}', server_id, 'INCR', 'FAILED', 777777),
        )
        conn.commit()
    finally:
        conn.close()

    os.remove('/home/user/fixed_sql_report.csv')
    run_script('/home/user/sql_report.sh')
    assert read_sql_report() == expected_sql_rows()


def derive_chain(job_id):
    conn = sqlite3.connect('/home/user/backups.db')
    try:
        current_id = job_id
        chain = [current_id]
        while True:
            row = conn.execute(
                'SELECT parent_id FROM backup_lineage WHERE child_id = ?',
                (current_id,),
            ).fetchone()
            if row and row[0]:
                current_id = row[0]
                chain.append(current_id)
            else:
                break
        return '->'.join(chain)
    finally:
        conn.close()


def assert_single_chain_line(output, expected):
    assert output.strip() == expected, f"Expected '{expected}', got '{output.strip()}'"
    assert output.splitlines() == [expected], f'Chain output must be exactly one line: {output!r}'


def test_task2_get_chain_script_and_result():
    script_path = '/home/user/get_chain.sh'
    result_path = '/home/user/chain_result.txt'
    assert os.path.exists(script_path), f'Script {script_path} is missing.'
    assert os.path.isfile(script_path), f'{script_path} is not a regular file.'
    assert os.access(script_path, os.X_OK), f'Script {script_path} is not executable.'
    assert os.path.exists(result_path), f'Result file {result_path} is missing.'

    expected_chain_str = derive_chain('incr_999')
    with open(result_path) as f:
        actual_chain_str = f.read().strip()
    assert actual_chain_str == expected_chain_str, (
        f"Chain result in {result_path} is incorrect. Expected "
        f"'{expected_chain_str}', got '{actual_chain_str}'"
    )

    with open(script_path) as f:
        source = f.read()
    assert re.search(r'\bWITH\s+RECURSIVE\b', source, re.IGNORECASE), (
        'get_chain.sh must use a Recursive CTE.'
    )
    assert re.search(r'\bsqlite3\b', source), 'get_chain.sh must execute sqlite3.'

    completed = run_script(script_path, 'incr_999')
    assert_single_chain_line(completed.stdout, expected_chain_str)


def test_task2_reacts_to_new_lineage():
    token = uuid.uuid4().hex
    leaf, middle, root = f'leaf-{token}', f'middle-{token}', f'root-{token}'
    conn = sqlite3.connect('/home/user/backups.db')
    try:
        conn.execute('INSERT INTO backup_lineage(child_id, parent_id) VALUES (?, ?)', (leaf, middle))
        conn.execute('INSERT INTO backup_lineage(child_id, parent_id) VALUES (?, ?)', (middle, root))
        conn.commit()
    finally:
        conn.close()

    expected = derive_chain(leaf)
    completed = run_script('/home/user/get_chain.sh', leaf)
    assert_single_chain_line(completed.stdout, expected)


def expected_nosql_rows():
    with open('/home/user/nosql_backups.json') as f:
        data = json.load(f)
    clusters = {}
    for job in data:
        if job.get('status') == 'SUCCESS':
            cid = job['cluster_id']
            ts = job['timestamp']
            if cid not in clusters or ts > clusters[cid]['timestamp']:
                clusters[cid] = job
    return sorted((cid, clusters[cid]['size_gb']) for cid in clusters)


def read_nosql_report():
    csv_path = '/home/user/nosql_report.csv'
    assert os.path.exists(csv_path), f'File {csv_path} is missing.'
    with open(csv_path, newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, f'{csv_path} is empty.'
    assert rows[0] == ['cluster_id', 'latest_size_gb'], (
        f'Headers in {csv_path} are incorrect. Expected '
        f"['cluster_id', 'latest_size_gb'], got {rows[0]}"
    )
    assert all(len(row) == 2 for row in rows[1:]), f'Malformed row in {csv_path}: {rows}'
    return [(row[0], int(row[1])) for row in rows[1:] if len(row) == 2]


def test_task3_nosql_summary_script_and_report():
    script_path = '/home/user/nosql_summary.sh'
    csv_path = '/home/user/nosql_report.csv'
    assert os.path.exists(script_path), f'Script {script_path} is missing.'
    assert os.path.isfile(script_path), f'{script_path} is not a regular file.'
    assert os.access(script_path, os.X_OK), f'Script {script_path} is not executable.'
    assert os.path.exists(csv_path), f'File {csv_path} is missing.'

    with open(script_path) as f:
        source = f.read()
    assert re.search(r'\bjq\b', source), 'nosql_summary.sh must use jq.'

    os.remove(csv_path)
    run_script(script_path)
    expected_rows = expected_nosql_rows()
    actual_data = read_nosql_report()
    assert actual_data == expected_rows, (
        f'Data in {csv_path} does not match expected derived data. '
        f'Expected {expected_rows}, got {actual_data}'
    )


def test_task3_reacts_to_json_changes():
    token = uuid.uuid4().hex
    data = [
        {'cluster_id': f'zeta-{token}', 'job_id': 'z1', 'status': 'SUCCESS', 'timestamp': 10, 'size_gb': 41},
        {'cluster_id': f'zeta-{token}', 'job_id': 'z2', 'status': 'FAILED', 'timestamp': 30, 'size_gb': 999},
        {'cluster_id': f'zeta-{token}', 'job_id': 'z3', 'status': 'SUCCESS', 'timestamp': 20, 'size_gb': 42},
        {'cluster_id': f'alpha-{token}', 'job_id': 'a1', 'status': 'SUCCESS', 'timestamp': 50, 'size_gb': 73},
        {'cluster_id': f'alpha-{token}', 'job_id': 'a2', 'status': 'SUCCESS', 'timestamp': 40, 'size_gb': 72},
    ]
    with open('/home/user/nosql_backups.json', 'w') as f:
        json.dump(data, f)

    os.remove('/home/user/nosql_report.csv')
    run_script('/home/user/nosql_summary.sh')
    assert read_nosql_report() == expected_nosql_rows()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
