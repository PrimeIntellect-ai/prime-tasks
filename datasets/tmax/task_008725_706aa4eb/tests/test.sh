#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import secrets
import shutil
import sqlite3
import subprocess
from pathlib import Path

import pytest

REPORT_CSV_PATH = Path('/home/user/report.csv')
PROJECT_PATH = Path('/home/user/sales_report')
CARGO_TOML_PATH = PROJECT_PATH / 'Cargo.toml'
DATABASE_PATH = Path('/home/user/company.db')
DATABASE_BACKUP_PATH = Path('/tmp/company.db.verifier-backup')
ORIGINAL_REPORT_BACKUP_PATH = Path('/tmp/report.csv.verifier-original')
SELECTED_EXECUTABLE = None

EXPECTED_DATA = [
    ['id', 'name', 'department_id', 'total_sales', 'dept_rank'],
    ['1', 'Alice', '1', '510', '1'],
    ['2', 'Bob', '2', '270', '1'],
    ['3', 'Charlie', '3', '230', '1'],
    ['4', 'Dave', '2', '100', '3'],
    ['5', 'Eve', '2', '150', '2'],
    ['6', 'Frank', '3', '200', '2'],
]


def read_report():
    assert REPORT_CSV_PATH.is_file(), f'Report CSV not found at {REPORT_CSV_PATH}'
    with REPORT_CSV_PATH.open('r', newline='') as f:
        return list(csv.reader(f))


def run_executable(executable):
    if REPORT_CSV_PATH.exists():
        REPORT_CSV_PATH.unlink()
    result = subprocess.run(
        [str(executable)],
        cwd=str(PROJECT_PATH),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=60,
    )
    assert result.returncode == 0, (
        f'Compiled Rust executable failed with status {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert REPORT_CSV_PATH.is_file(), 'Running the compiled Rust program did not create report.csv'


def test_rust_project_exists():
    assert os.path.exists(CARGO_TOML_PATH), f'Rust project Cargo.toml not found at {CARGO_TOML_PATH}'


def test_cargo_toml_dependencies():
    with open(CARGO_TOML_PATH, 'r') as f:
        content = f.read()

    # Preserve the original dependency assertions.
    assert 'rusqlite' in content, 'rusqlite dependency missing in Cargo.toml'
    assert '0.29' in content or '0.29.0' in content, 'rusqlite version 0.29.0 not found in Cargo.toml'
    assert 'bundled' in content, "rusqlite 'bundled' feature missing in Cargo.toml"
    assert 'csv' in content, 'csv dependency missing in Cargo.toml'
    assert '1.3' in content or '1.3.0' in content, 'csv version 1.3.0 not found in Cargo.toml'


def test_source_contains_required_sql_constructs():
    source_files = list((PROJECT_PATH / 'src').rglob('*.rs')) + list(PROJECT_PATH.rglob('*.sql'))
    source_files = [p for p in source_files if 'target' not in p.parts]
    assert source_files, 'No Rust or SQL source files were found in the project'
    source = '\n'.join(p.read_text(errors='replace') for p in source_files)
    assert re.search(r'\bWITH\s+RECURSIVE\b', source, re.IGNORECASE), \
        'The project source does not contain a recursive CTE (WITH RECURSIVE)'
    assert re.search(r'\bDENSE_RANK\s*\(', source, re.IGNORECASE), \
        'The project source does not contain DENSE_RANK()'
    assert re.search(r'\bPARTITION\s+BY\b', source, re.IGNORECASE), \
        'The DENSE_RANK query must partition results by department_id'


def test_compile_and_run_rust_program_on_original_database():
    global SELECTED_EXECUTABLE

    shutil.copy2(DATABASE_PATH, DATABASE_BACKUP_PATH)
    command = [
        'cargo', 'build', '--bins',
        '--manifest-path', str(CARGO_TOML_PATH),
        '--message-format=json',
    ]
    result = subprocess.run(
        command,
        cwd=str(PROJECT_PATH),
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=300,
    )
    assert result.returncode == 0, (
        f'Cargo failed to compile the Rust project.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )

    executables = []
    for line in result.stdout.splitlines():
        try:
            message = json.loads(line)
        except json.JSONDecodeError:
            continue
        target = message.get('target', {})
        executable = message.get('executable')
        src_path = target.get('src_path', '')
        if executable and 'bin' in target.get('kind', []) and str(PROJECT_PATH) in src_path:
            executables.append(Path(executable))

    executables = list(dict.fromkeys(executables))
    assert executables, 'Cargo did not produce a Rust binary for this project'

    failures = []
    for executable in executables:
        try:
            run_executable(executable)
            actual = read_report()
            if actual == EXPECTED_DATA:
                SELECTED_EXECUTABLE = executable
                shutil.copy2(REPORT_CSV_PATH, ORIGINAL_REPORT_BACKUP_PATH)
                break
            failures.append(f'{executable}: generated incorrect original report')
        except Exception as exc:
            failures.append(f'{executable}: {exc}')

    assert SELECTED_EXECUTABLE is not None, \
        'No compiled project binary generated the required report:\n' + '\n'.join(failures)


def test_report_csv_content():
    # Preserve the original exact CSV assertions, now against freshly executed output.
    assert os.path.exists(REPORT_CSV_PATH), f'Report CSV not found at {REPORT_CSV_PATH}'
    actual_data = read_report()
    assert len(actual_data) == len(EXPECTED_DATA), \
        f'Expected {len(EXPECTED_DATA)} rows in CSV, but got {len(actual_data)}'
    for i, (actual_row, expected_row) in enumerate(zip(actual_data, EXPECTED_DATA)):
        assert actual_row == expected_row, \
            f'Row {i} mismatch in CSV. Expected {expected_row}, got {actual_row}'


def test_program_computes_recursive_totals_and_dense_ranks_for_new_data():
    assert SELECTED_EXECUTABLE is not None

    rng = random.SystemRandom()
    ids = rng.sample(range(1000, 9000), 8)
    root, b_id, c_id, d_id, e_id, h_id, f_id, g_id = ids
    a = rng.randint(30, 100)
    h = rng.randint(10, 60)
    b = rng.randint(7, 35)
    tied_total = a + h + b
    token = secrets.token_hex(6)

    employees = [
        (root, f'Root-{token}', None, 9, rng.randint(3, 20)),
        (b_id, f'Branch B-{token}', root, 2, b),
        (c_id, f'Branch C-{token}', root, 2, tied_total),
        (d_id, f'Deep, Node-{token}', b_id, 2, a),
        (e_id, f'Peer-{token}', None, 2, tied_total - 1),
        (h_id, f'Leaf-{token}', d_id, 7, h),
        (f_id, f'Other-{token}', None, 7, rng.randint(2, 25)),
        (g_id, f'Last-{token}', f_id, 9, rng.randint(2, 25)),
    ]

    temporary_db = Path('/tmp/company.db.dynamic')
    if temporary_db.exists():
        temporary_db.unlink()
    connection = sqlite3.connect(temporary_db)
    connection.execute('''
        CREATE TABLE employees (
            id INTEGER PRIMARY KEY,
            name TEXT,
            manager_id INTEGER,
            department_id INTEGER,
            individual_sales INTEGER
        )
    ''')
    connection.executemany('INSERT INTO employees VALUES (?, ?, ?, ?, ?)', employees)
    connection.commit()
    connection.close()

    by_id = {row[0]: row for row in employees}
    children = {employee_id: [] for employee_id in by_id}
    for employee_id, _name, manager_id, _department, _sales in employees:
        if manager_id is not None:
            children[manager_id].append(employee_id)

    def total_sales(employee_id):
        return by_id[employee_id][4] + sum(total_sales(child) for child in children[employee_id])

    totals = {employee_id: total_sales(employee_id) for employee_id in by_id}
    department_totals = {}
    for employee_id, _name, _manager, department_id, _sales in employees:
        department_totals.setdefault(department_id, set()).add(totals[employee_id])
    ranks = {
        department_id: {value: rank + 1 for rank, value in enumerate(sorted(values, reverse=True))}
        for department_id, values in department_totals.items()
    }

    expected = [['id', 'name', 'department_id', 'total_sales', 'dept_rank']]
    for employee_id, name, _manager, department_id, _sales in sorted(employees):
        expected.append([
            str(employee_id), name, str(department_id), str(totals[employee_id]),
            str(ranks[department_id][totals[employee_id]]),
        ])

    try:
        os.replace(temporary_db, DATABASE_PATH)
        run_executable(SELECTED_EXECUTABLE)
        actual = read_report()
        assert actual == expected, (
            'The compiled program did not recompute recursive hierarchy totals and '
            f'department DENSE_RANK values for a new database.\nExpected: {expected}\nActual: {actual}'
        )
        numeric_ids = [int(row[0]) for row in actual[1:]]
        assert numeric_ids == sorted(numeric_ids), 'CSV rows are not sorted by id ascending'
    finally:
        shutil.copy2(DATABASE_BACKUP_PATH, DATABASE_PATH)
        if ORIGINAL_REPORT_BACKUP_PATH.exists():
            shutil.copy2(ORIGINAL_REPORT_BACKUP_PATH, REPORT_CSV_PATH)
        if temporary_db.exists():
            temporary_db.unlink()
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
