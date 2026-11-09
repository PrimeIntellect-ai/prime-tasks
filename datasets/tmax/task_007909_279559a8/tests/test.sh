#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import random
import re
import sqlite3
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
PROGRAM = HOME / 'process.go'
BINARY = Path('/tmp/process_submission')


def run_program():
    for path in (HOME / 'top_sales.json', HOME / 'ceo_sales.txt', HOME / 'data.db'):
        if path.exists() or path.is_symlink():
            path.unlink()
    result = subprocess.run(
        [str(BINARY)], cwd=str(HOME), text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=30
    )
    assert result.returncode == 0, (
        f'process.go exited with {result.returncode}.\n'
        f'stdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )


@pytest.fixture(scope='session')
def built_and_run():
    result = subprocess.run(
        ['go', 'build', '-o', str(BINARY), str(PROGRAM)],
        cwd=str(HOME), text=True, stdout=subprocess.PIPE,
        stderr=subprocess.PIPE, timeout=120
    )
    assert result.returncode == 0, (
        f'process.go did not build.\nstdout:\n{result.stdout}\nstderr:\n{result.stderr}'
    )
    assert BINARY.is_file() and os.access(BINARY, os.X_OK)
    run_program()
    return BINARY


def test_required_go_and_sql_artifacts_exist():
    assert PROGRAM.is_file() and not PROGRAM.is_symlink(), '/home/user/process.go must be a regular file.'
    source = PROGRAM.read_text(encoding='utf-8')
    assert source.strip(), '/home/user/process.go is empty.'

    go_mod = HOME / 'go.mod'
    assert go_mod.is_file() and not go_mod.is_symlink(), '/home/user/go.mod does not exist.'
    module_text = go_mod.read_text(encoding='utf-8')
    assert re.search(r'(?m)^\s*module\s+\S+', module_text), 'go.mod has no module declaration.'
    assert 'github.com/mattn/go-sqlite3' in module_text, 'go.mod does not include github.com/mattn/go-sqlite3.'
    assert 'github.com/mattn/go-sqlite3' in source, 'process.go does not import the required SQLite3 driver.'
    assert re.search(r'\bdatabase/sql\b', source), 'process.go does not use Go database/sql.'

    # Ignore Go comments before checking that the required SQL constructs are present.
    checked = re.sub(r'/\*.*?\*/', ' ', source, flags=re.S)
    checked = re.sub(r'(?m)//.*$', ' ', checked)
    assert re.search(r'(?is)\b(?:row_number|rank|dense_rank)\s*\(\s*\)\s*over\s*\(', checked), (
        'process.go does not contain a ranking Window Function.'
    )
    assert re.search(r'(?is)\bwith\s+recursive\b', checked), (
        'process.go does not contain a Recursive CTE.'
    )
    assert re.search(r'(?i)\.(?:query|queryrow|exec)(?:context)?\s*\(', checked), (
        'process.go does not execute SQL through database/sql.'
    )


def test_top_sales_json(built_and_run):
    file_path = '/home/user/top_sales.json'
    assert os.path.isfile(file_path), f'File {file_path} does not exist.'

    with open(file_path, 'r') as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError:
            pytest.fail(f'File {file_path} is not valid JSON.')

    expected_data = [
        {'department': 'Engineering', 'name': 'Eve', 'total_sales': 200},
        {'department': 'Engineering', 'name': 'David', 'total_sales': 200},
        {'department': 'Executive', 'name': 'Alice', 'total_sales': 1000},
        {'department': 'Sales', 'name': 'Heidi', 'total_sales': 500},
        {'department': 'Sales', 'name': 'Grace', 'total_sales': 350}
    ]

    # Preserve the original verifier's comparison.
    def sort_key(x):
        return (x.get('department', ''), -x.get('total_sales', 0), x.get('name', ''))

    sorted_data = sorted(data, key=sort_key)
    sorted_expected = sorted(expected_data, key=sort_key)
    assert sorted_data == sorted_expected, f'Content of {file_path} does not match the expected top sales data.'


def test_ceo_sales_txt(built_and_run):
    file_path = '/home/user/ceo_sales.txt'
    assert os.path.isfile(file_path), f'File {file_path} does not exist.'
    with open(file_path, 'r') as f:
        content = f.read().strip()
    assert content == '2650', f"Content of {file_path} is incorrect. Expected '2650', got '{content}'."


def test_sqlite_database_was_populated(built_and_run):
    db_path = HOME / 'data.db'
    assert db_path.is_file() and not db_path.is_symlink(), '/home/user/data.db was not created.'
    assert db_path.read_bytes()[:16] == b'SQLite format 3\x00', 'data.db is not an SQLite database.'

    con = sqlite3.connect(str(db_path))
    try:
        tables = [r[0] for r in con.execute(
            "SELECT name FROM sqlite_master WHERE type='table' AND name NOT LIKE 'sqlite_%'"
        )]
        employee_table = None
        sales_table = None
        for table in tables:
            quoted = table.replace('"', '""')
            columns = {r[1].lower() for r in con.execute(f'PRAGMA table_info("{quoted}")')}
            if {'id', 'name', 'manager_id', 'department'} <= columns:
                employee_table = table
            if {'employee_id', 'amount', 'date'} <= columns:
                sales_table = table
        assert employee_table is not None, 'No populated employees table with the CSV columns was found.'
        assert sales_table is not None, 'No populated sales table with the CSV columns was found.'
        eq = employee_table.replace('"', '""')
        sq = sales_table.replace('"', '""')
        assert con.execute(f'SELECT COUNT(*) FROM "{eq}"').fetchone()[0] == 8
        assert con.execute(f'SELECT COUNT(*) FROM "{sq}"').fetchone()[0] == 9
    finally:
        con.close()


def test_z_program_recomputes_reports_for_unseen_inputs(built_and_run):
    protected = [HOME / 'employees.csv', HOME / 'sales.csv', HOME / 'top_sales.json',
                 HOME / 'ceo_sales.txt', HOME / 'data.db']
    backups = {p: p.read_bytes() if p.exists() else None for p in protected}

    rng = random.SystemRandom()
    base = rng.randrange(2000, 9000)
    employees = [
        {'id': 11, 'name': 'Chief', 'manager_id': '', 'department': 'Leadership'},
        {'id': 20, 'name': 'EngLead', 'manager_id': 11, 'department': 'Engineering'},
        {'id': 21, 'name': 'Ada', 'manager_id': 20, 'department': 'Engineering'},
        {'id': 22, 'name': 'Linus', 'manager_id': 20, 'department': 'Engineering'},
        {'id': 30, 'name': 'SalesLead', 'manager_id': 11, 'department': 'Sales'},
        {'id': 31, 'name': 'Mira', 'manager_id': 30, 'department': 'Sales'},
        {'id': 32, 'name': 'Niko', 'manager_id': 30, 'department': 'Sales'},
        # This employee is intentionally disconnected from the CEO hierarchy.
        {'id': 99, 'name': 'Outsider', 'manager_id': 999, 'department': 'Rogue'},
    ]
    sales = [
        {'employee_id': 11, 'amount': base + 1, 'date': '2025-01-01'},
        {'employee_id': 20, 'amount': base + 30, 'date': '2025-01-02'},
        {'employee_id': 21, 'amount': base + 70, 'date': '2025-01-03'},
        {'employee_id': 21, 'amount': 13, 'date': '2025-01-04'},
        {'employee_id': 22, 'amount': base + 50, 'date': '2025-01-05'},
        {'employee_id': 30, 'amount': base + 20, 'date': '2025-01-06'},
        {'employee_id': 31, 'amount': base + 90, 'date': '2025-01-07'},
        {'employee_id': 32, 'amount': base + 60, 'date': '2025-01-08'},
        {'employee_id': 32, 'amount': 17, 'date': '2025-01-09'},
        {'employee_id': 99, 'amount': base * 20 + 777, 'date': '2025-01-10'},
    ]

    totals = {e['id']: 0 for e in employees}
    for row in sales:
        totals[row['employee_id']] += row['amount']

    by_department = {}
    for employee in employees:
        by_department.setdefault(employee['department'], []).append({
            'department': employee['department'],
            'name': employee['name'],
            'total_sales': totals[employee['id']],
        })
    expected_top = []
    for department in sorted(by_department):
        ranked = sorted(by_department[department], key=lambda x: (-x['total_sales'], x['name']))
        expected_top.extend(ranked[:2])

    children = {}
    for employee in employees:
        children.setdefault(employee['manager_id'], []).append(employee['id'])
    reachable = []
    stack = list(children.get('', []))
    while stack:
        employee_id = stack.pop()
        reachable.append(employee_id)
        stack.extend(children.get(employee_id, []))
    expected_ceo = sum(totals[i] for i in reachable)

    try:
        with (HOME / 'employees.csv').open('w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['id', 'name', 'manager_id', 'department'])
            writer.writeheader()
            writer.writerows(employees)
        with (HOME / 'sales.csv').open('w', newline='') as f:
            writer = csv.DictWriter(f, fieldnames=['employee_id', 'amount', 'date'])
            writer.writeheader()
            writer.writerows(sales)

        run_program()

        with (HOME / 'top_sales.json').open() as f:
            actual_top = json.load(f)
        assert actual_top == expected_top, (
            'The executed program did not recompute the ordered top-two-per-department report '
            'for unseen CSV input.'
        )

        actual_ceo = (HOME / 'ceo_sales.txt').read_text().strip()
        assert re.fullmatch(r'-?\d+', actual_ceo), 'ceo_sales.txt must contain one integer.'
        assert int(actual_ceo) == expected_ceo, (
            'The executed program did not recompute the CEO hierarchy total for unseen CSV input.'
        )
    finally:
        for path, content in backups.items():
            if content is None:
                if path.exists() or path.is_symlink():
                    path.unlink()
            else:
                path.write_bytes(content)
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
