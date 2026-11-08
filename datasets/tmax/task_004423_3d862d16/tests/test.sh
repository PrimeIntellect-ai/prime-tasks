#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import secrets
import sqlite3
import stat
import subprocess

DB_PATH = '/home/user/corp_data.db'
CPP_SOURCE_PATH = '/home/user/audit_tool.cpp'
BINARY_PATH = '/home/user/audit_tool'
REPORT_PATH = '/home/user/audit_report.csv'
COMPILED_SOURCE_PATH = '/tmp/audit_tool_from_source'
EXPECTED_HEADER = ['EmployeeID', 'Name', 'Department', 'InDegree', 'OutDegree', 'BrokerScore']


def drop_indexes_and_report():
    conn = sqlite3.connect(DB_PATH)
    try:
        conn.execute('DROP INDEX IF EXISTS idx_comm_filter')
        conn.execute('DROP INDEX IF EXISTS idx_comm_edges')
        conn.commit()
    finally:
        conn.close()
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)


def assert_indexes():
    assert os.path.exists(DB_PATH), f'Database missing at {DB_PATH}'
    conn = sqlite3.connect(DB_PATH)
    try:
        indexes = {
            row[0]: row[1]
            for row in conn.execute(
                "SELECT name, tbl_name FROM sqlite_master WHERE type='index'"
            )
        }
        assert 'idx_comm_filter' in indexes, "Index 'idx_comm_filter' was not created on the database"
        assert 'idx_comm_edges' in indexes, "Index 'idx_comm_edges' was not created on the database"
        assert indexes['idx_comm_filter'] == 'communications'
        assert indexes['idx_comm_edges'] == 'communications'

        filter_columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_comm_filter')")]
        edge_columns = [row[2] for row in conn.execute("PRAGMA index_info('idx_comm_edges')")]
        assert filter_columns == ['sensitivity_level', 'timestamp'], \
            f'idx_comm_filter has wrong columns/order: {filter_columns}'
        assert edge_columns == ['sender_id', 'receiver_id'], \
            f'idx_comm_edges has wrong columns/order: {edge_columns}'
    finally:
        conn.close()


def read_report():
    assert os.path.exists(REPORT_PATH), f'Audit report missing at {REPORT_PATH}'
    with open(REPORT_PATH, 'r', newline='') as f:
        rows = list(csv.reader(f))
    assert len(rows) > 0, 'Audit report is empty'
    assert rows[0] == EXPECTED_HEADER, f'Expected header {EXPECTED_HEADER}, but got {rows[0]}'
    return rows[1:]


def expected_rows(min_sensitivity, limit):
    conn = sqlite3.connect(DB_PATH)
    try:
        edges = conn.execute(
            """SELECT sender_id, receiver_id
               FROM communications
               WHERE sensitivity_level >= ?
                 AND timestamp BETWEEN '2023-01-01 00:00:00'
                                   AND '2023-12-31 23:59:59'""",
            (min_sensitivity,),
        ).fetchall()
        indegree = {}
        outdegree = {}
        involved = set()
        for sender, receiver in edges:
            involved.add(sender)
            involved.add(receiver)
            outdegree[sender] = outdegree.get(sender, 0) + 1
            indegree[receiver] = indegree.get(receiver, 0) + 1

        result = []
        for employee_id in involved:
            employee = conn.execute(
                'SELECT name, department FROM employees WHERE id = ?',
                (employee_id,),
            ).fetchone()
            if employee is None:
                continue
            name, department = employee
            incoming = indegree.get(employee_id, 0)
            outgoing = outdegree.get(employee_id, 0)
            result.append((employee_id, name, department, incoming, outgoing, incoming * outgoing))

        result.sort(key=lambda row: (-row[5], row[1]))
        return [[str(value) for value in row] for row in result[:limit]]
    finally:
        conn.close()


def run_and_check(executable, min_sensitivity, limit, expected=None):
    if os.path.exists(REPORT_PATH):
        os.remove(REPORT_PATH)
    completed = subprocess.run(
        [executable, str(min_sensitivity), str(limit)],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=20,
    )
    assert completed.returncode == 0, (
        f'{executable} failed for arguments {min_sensitivity} {limit}: '
        f'{completed.stderr}'
    )
    actual = read_report()
    wanted = expected if expected is not None else expected_rows(min_sensitivity, limit)
    assert actual == wanted, f'Expected report rows {wanted}, but got {actual}'
    assert_indexes()


def add_unpredictable_data():
    rng = secrets.SystemRandom()
    token = secrets.token_hex(6)
    conn = sqlite3.connect(DB_PATH)
    try:
        next_employee = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM employees').fetchone()[0]
        employee_ids = []
        for offset in range(6):
            employee_id = next_employee + offset
            employee_ids.append(employee_id)
            conn.execute(
                'INSERT INTO employees(id, name, department) VALUES (?, ?, ?)',
                (employee_id, f'Generated_{token}_{offset}', f'Dept_{offset % 3}'),
            )

        all_ids = [row[0] for row in conn.execute('SELECT id FROM employees')]
        next_comm = conn.execute('SELECT COALESCE(MAX(id), 0) + 1 FROM communications').fetchone()[0]
        threshold = rng.randint(1, 5)

        communications = []
        for i in range(45):
            sender = rng.choice(all_ids)
            receiver = rng.choice(all_ids)
            while receiver == sender:
                receiver = rng.choice(all_ids)
            if i < 12:
                sender = employee_ids[i % 3]
                receiver = employee_ids[3 + (i % 3)]
                sensitivity = threshold
                timestamp = f'2023-09-{(i % 20) + 1:02d} 12:34:56'
            else:
                sensitivity = rng.randint(1, 5)
                year = rng.choice([2022, 2023, 2023, 2024])
                timestamp = f'{year}-{rng.randint(1, 12):02d}-{rng.randint(1, 28):02d} 08:15:00'
            communications.append(
                (next_comm + i, sender, receiver, timestamp, sensitivity)
            )
        conn.executemany(
            'INSERT INTO communications(id, sender_id, receiver_id, timestamp, sensitivity_level) '
            'VALUES (?, ?, ?, ?, ?)',
            communications,
        )
        conn.commit()
        return threshold, rng.randint(2, 8)
    finally:
        conn.close()


def test_complete_tool():
    # Preserve the original source/binary existence and executable assertions.
    assert os.path.exists(CPP_SOURCE_PATH), f'C++ source code missing at {CPP_SOURCE_PATH}'
    assert os.path.isfile(CPP_SOURCE_PATH), f'{CPP_SOURCE_PATH} is not a regular file'
    assert os.path.exists(BINARY_PATH), f'Compiled binary missing at {BINARY_PATH}'
    assert os.path.isfile(BINARY_PATH), f'{BINARY_PATH} is not a regular file'
    st = os.stat(BINARY_PATH)
    assert bool(st.st_mode & stat.S_IXUSR), f'Binary {BINARY_PATH} is not executable'
    with open(BINARY_PATH, 'rb') as f:
        assert f.read(4) == b'\x7fELF', f'{BINARY_PATH} is not a compiled ELF executable'

    # Ensure the submitted source is compilable rather than a placeholder.
    compiled = subprocess.run(
        ['g++', CPP_SOURCE_PATH, '-lsqlite3', '-o', COMPILED_SOURCE_PATH],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=30,
    )
    assert compiled.returncode == 0, f'C++ source failed to compile: {compiled.stderr}'

    # Remove any pre-created artifacts so the submitted executable must create them.
    drop_indexes_and_report()

    # Preserve the original exact check for the required invocation.
    original_expected = [
        ['2', 'Bob', 'Engineering', '3', '3', '9'],
        ['3', 'Charlie', 'Engineering', '1', '2', '2'],
        ['1', 'Alice', 'HR', '0', '1', '0'],
    ]
    run_and_check(BINARY_PATH, 3, 3, original_expected)

    # Exercise the submitted binary against data and arguments chosen only at verification time.
    threshold, limit = add_unpredictable_data()
    drop_indexes_and_report()
    run_and_check(BINARY_PATH, threshold, limit)

    # Exercise a fresh build of the submitted source with a different argument pair.
    second_threshold = (threshold % 5) + 1
    second_limit = 5 if limit != 5 else 7
    drop_indexes_and_report()
    run_and_check(COMPILED_SOURCE_PATH, second_threshold, second_limit)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
