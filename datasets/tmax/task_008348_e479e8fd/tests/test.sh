#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import re
import secrets
import sqlite3
import stat
import subprocess


def run_audit():
    audit_path = '/home/user/audit.py'
    assert os.path.exists(audit_path), f"Expected script {audit_path} is missing."
    assert stat.S_ISREG(os.lstat(audit_path).st_mode), f"{audit_path} is not a regular file."

    csv_path = '/home/user/violations.csv'
    if os.path.lexists(csv_path):
        os.remove(csv_path)

    result = subprocess.run(
        ['python3', audit_path],
        cwd='/home/user',
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=15,
    )
    assert result.returncode == 0, (
        f"audit.py failed with exit code {result.returncode}.\n"
        f"stdout:\n{result.stdout}\nstderr:\n{result.stderr}"
    )
    assert os.path.exists(csv_path), "audit.py did not create /home/user/violations.csv."
    assert os.path.isfile(csv_path), f"{csv_path} is not a file."


def read_csv_rows():
    with open('/home/user/violations.csv', 'r', newline='') as f:
        return list(csv.reader(f))


def test_audit_script_and_violations_csv():
    db_path = '/home/user/access_logs.db'
    json_path = '/home/user/resources.json'
    csv_path = '/home/user/violations.csv'

    with open(db_path, 'rb') as f:
        original_db = f.read()
    with open(json_path, 'rb') as f:
        original_json = f.read()
    original_csv = None
    if os.path.isfile(csv_path):
        with open(csv_path, 'rb') as f:
            original_csv = f.read()

    fixed_csv = None
    try:
        # Execute the submitted artifact on the supplied data before retaining
        # the original exact-output assertions.
        run_audit()
        rows = read_csv_rows()
        assert len(rows) > 0, "violations.csv is empty."

        header = rows[0]
        expected_header = ['emp_id', 'resource_id', 'violation_count']
        assert header == expected_header, f"CSV header is incorrect. Expected {expected_header}, got {header}."

        data_rows = rows[1:]
        expected_data = [
            ['2', 'R1', '1'],
            ['3', 'R2', '2'],
            ['4', 'R1', '1']
        ]
        assert data_rows == expected_data, f"CSV data is incorrect. Expected {expected_data}, got {data_rows}."
        with open(csv_path, 'rb') as f:
            fixed_csv = f.read()

        # Replace both sources with a fresh fixture so a hard-coded copy of the
        # supplied CSV cannot pass. Expected rows are independently derived.
        token = secrets.token_hex(6)
        base = 10000 + secrets.randbelow(50000)
        employees = [
            (base + 7, 'Alpha', f'DA_{token}'),
            (base + 2, 'Beta', f'DB_{token}'),
            (base + 19, 'Gamma', f'DC_{token}'),
            (base + 11, 'Delta', f'DD_{token}'),
        ]
        r1, r2, r3 = (f'R1_{token}', f'R2_{token}', f'R3_{token}')
        resources = [
            {'resource_id': r1, 'allowed_depts': [employees[0][2]]},
            {'resource_id': r2, 'allowed_depts': [employees[1][2]]},
            {'resource_id': r3, 'allowed_depts': [employees[2][2], employees[3][2]]},
        ]
        logs = [
            (1, employees[0][0], r1, '2040-01-01', 'SUCCESS'),
            (2, employees[1][0], r1, '2040-01-02', 'SUCCESS'),
            (3, employees[1][0], r1, '2040-01-03', 'SUCCESS'),
            (4, employees[1][0], r1, '2040-01-04', 'FAILED'),
            (5, employees[2][0], r2, '2040-01-05', 'SUCCESS'),
            (6, employees[0][0], r2, '2040-01-06', 'SUCCESS'),
            (7, employees[2][0], r3, '2040-01-07', 'SUCCESS'),
            (8, employees[3][0], r3, '2040-01-08', 'SUCCESS'),
        ]

        if os.path.lexists(db_path):
            os.remove(db_path)
        conn = sqlite3.connect(db_path)
        try:
            conn.execute('CREATE TABLE employees (emp_id INTEGER, name TEXT, dept_id TEXT)')
            conn.execute('CREATE TABLE logs (log_id INTEGER, emp_id INTEGER, resource_id TEXT, access_time TEXT, status TEXT)')
            conn.executemany('INSERT INTO employees VALUES (?,?,?)', employees)
            conn.executemany('INSERT INTO logs VALUES (?,?,?,?,?)', logs)
            conn.commit()
        finally:
            conn.close()
        with open(json_path, 'w') as f:
            json.dump(resources, f)

        dept_by_emp = {emp_id: dept for emp_id, _name, dept in employees}
        allowed_by_resource = {r['resource_id']: set(r['allowed_depts']) for r in resources}
        counts = {}
        for _log_id, emp_id, resource_id, _time, status_value in logs:
            if status_value == 'SUCCESS' and dept_by_emp[emp_id] not in allowed_by_resource[resource_id]:
                counts[(emp_id, resource_id)] = counts.get((emp_id, resource_id), 0) + 1
        expected_dynamic = [
            [str(emp_id), resource_id, str(counts[(emp_id, resource_id)])]
            for emp_id, resource_id in sorted(counts)
        ]

        run_audit()
        dynamic_rows = read_csv_rows()
        assert dynamic_rows and dynamic_rows[0] == ['emp_id', 'resource_id', 'violation_count'], (
            "Dynamic output has an incorrect CSV header."
        )
        assert dynamic_rows[1:] == expected_dynamic, (
            f"audit.py did not correctly cross-reference the dynamic SQL and JSON inputs. "
            f"Expected {expected_dynamic}, got {dynamic_rows[1:]}."
        )
    finally:
        with open(db_path, 'wb') as f:
            f.write(original_db)
        with open(json_path, 'wb') as f:
            f.write(original_json)
        restore_csv = fixed_csv if fixed_csv is not None else original_csv
        if restore_csv is not None:
            with open(csv_path, 'wb') as f:
                f.write(restore_csv)
        elif os.path.lexists(csv_path):
            os.remove(csv_path)


def test_index_sql_exists_and_correct():
    sql_path = '/home/user/index.sql'
    assert os.path.exists(sql_path), f"Expected SQL file {sql_path} is missing."
    assert os.path.isfile(sql_path), f"{sql_path} is not a file."

    with open(sql_path, 'r') as f:
        original_sql = f.read()
    sql_content = original_sql.strip().lower()

    # Retain the original content assertions.
    assert "create index" in sql_content, "SQL file does not contain 'CREATE INDEX'."
    assert "idx_logs_emp_status" in sql_content, "Index name 'idx_logs_emp_status' is missing."
    assert "on logs" in sql_content or "on logs(" in sql_content or "on logs " in sql_content, "Index is not created on the 'logs' table."
    assert "emp_id" in sql_content, "Column 'emp_id' is missing from the index definition."
    assert "status" in sql_content, "Column 'status' is missing from the index definition."

    match = re.search(r'\((.*?)\)', sql_content)
    assert match is not None, "Could not find column list in parentheses."
    columns = [col.strip() for col in match.group(1).split(',')]
    assert "emp_id" in columns and "status" in columns, "The index must include both 'emp_id' and 'status' columns."

    # sqlite3.execute rejects additional SQL statements. Execute against a
    # fresh schema, then inspect the actual index rather than trusting text.
    conn = sqlite3.connect(':memory:')
    try:
        conn.execute('CREATE TABLE logs (log_id INTEGER, emp_id INTEGER, resource_id TEXT, access_time TEXT, status TEXT)')
        try:
            conn.execute(original_sql)
        except sqlite3.Error as exc:
            raise AssertionError(f"index.sql is not exactly one executable CREATE INDEX statement: {exc}")

        indexes = conn.execute("PRAGMA index_list('logs')").fetchall()
        assert len(indexes) == 1, f"Expected exactly one index on logs, found {indexes}."
        assert indexes[0][1].lower() == 'idx_logs_emp_status', (
            f"Expected index named idx_logs_emp_status, found {indexes[0][1]}."
        )
        indexed_columns = [row[2].lower() for row in conn.execute("PRAGMA index_info('idx_logs_emp_status')")]
        assert len(indexed_columns) == 2 and set(indexed_columns) == {'emp_id', 'status'}, (
            f"The index must be composite and contain exactly emp_id and status; got {indexed_columns}."
        )
    finally:
        conn.close()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
