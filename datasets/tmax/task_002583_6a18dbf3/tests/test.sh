#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'PY_EOF' > /tmp/test_final_state.py
import os
import re
import sqlite3
import subprocess
import secrets
from pathlib import Path

HOME = Path('/home/user')
DB = HOME / 'company.db'
REPORT = HOME / 'report.txt'
SOURCE = HOME / 'report_generator.cpp'
SQLITE_C = HOME / 'sqlite' / 'sqlite3.c'
SQLITE_H = HOME / 'sqlite' / 'sqlite3.h'
DATA = HOME / 'data'


def normalized_report(path):
    assert path.is_file(), f'{path} was not created.'
    return [line.replace(' ', '') for line in path.read_text().strip().splitlines() if line.strip()]


def table_definition(conn, table):
    rows = conn.execute(f'PRAGMA table_info({table})').fetchall()
    return [(r[1], (r[2] or '').upper(), r[5]) for r in rows]


def assert_required_index(conn, table, column):
    matches = []
    for row in conn.execute(f'PRAGMA index_list({table})'):
        name = row[1]
        columns = [r[2] for r in conn.execute(f'PRAGMA index_info("{name}")')]
        if columns == [column]:
            matches.append(name)
    assert matches, f'Missing an explicit index on {table}({column})'


def assert_schema_and_indexes(conn):
    assert table_definition(conn, 'departments') == [
        ('id', 'INTEGER', 1), ('name', 'TEXT', 0)
    ]
    assert table_definition(conn, 'employees') == [
        ('id', 'INTEGER', 1), ('name', 'TEXT', 0),
        ('department_id', 'INTEGER', 0), ('manager_id', 'INTEGER', 0)
    ]
    assert table_definition(conn, 'sales') == [
        ('id', 'INTEGER', 1), ('employee_id', 'INTEGER', 0), ('amount', 'INTEGER', 0)
    ]
    assert_required_index(conn, 'employees', 'department_id')
    assert_required_index(conn, 'sales', 'employee_id')


# Preserve the original fixed-fixture report assertion.
expected_initial = [
    'Frank|Marketing|Alice|200|1',
    'Grace|Sales|Alice|400|1',
    'Eve|Sales|Alice|300|2',
    'David|Sales|Alice|250|3',
    'Charlie|Sales|Alice|50|4'
]
assert normalized_report(REPORT) == expected_initial, f'Content of {REPORT} does not match expected output.'

# Preserve the original database/index-count assertion.
assert DB.is_file(), f'Database file {DB} was not created.'
with sqlite3.connect(DB) as conn:
    try:
        index_count = conn.execute("""
            SELECT count(*) FROM sqlite_master
            WHERE type='index' AND (tbl_name='employees' OR tbl_name='sales')
        """).fetchone()[0]
    except sqlite3.OperationalError as e:
        raise AssertionError(f'Failed to query sqlite_master in {DB}: {e}')
    assert index_count >= 2, f'Expected at least 2 indexes on employees/sales tables, found {index_count}.'
    assert_schema_and_indexes(conn)
    assert conn.execute('SELECT id,name FROM departments ORDER BY id').fetchall() == [
        (1, 'Engineering'), (2, 'Sales'), (3, 'Marketing')
    ]
    assert conn.execute('SELECT id,name,department_id,manager_id FROM employees ORDER BY id').fetchall() == [
        (1, 'Alice', None, None), (2, 'Bob', 1, 1), (3, 'Charlie', 2, 1),
        (4, 'David', 2, 3), (5, 'Eve', 2, 3), (6, 'Frank', 3, 1),
        (7, 'Grace', 2, 4)
    ]
    assert conn.execute('SELECT id,employee_id,amount FROM sales ORDER BY id').fetchall() == [
        (1, 4, 100), (2, 4, 150), (3, 5, 300),
        (4, 3, 50), (5, 7, 400), (6, 6, 200)
    ]

# Require the requested source program and a real, locally compiled SQLite amalgamation.
assert SOURCE.is_file(), f'{SOURCE} is missing'
assert SQLITE_C.is_file(), f'{SQLITE_C} is missing'
assert SQLITE_H.is_file(), f'{SQLITE_H} is missing'
assert SQLITE_C.stat().st_size > 5_000_000, 'sqlite3.c is not a SQLite amalgamation-sized source file'
sqlite_head = SQLITE_C.read_text(errors='ignore')
assert 'The SQLite amalgamation' in sqlite_head, 'sqlite3.c is not identified as the SQLite amalgamation'
version = re.search(r'#define\s+SQLITE_VERSION_NUMBER\s+(\d+)', sqlite_head)
assert version and int(version.group(1)) >= 3040000, 'SQLite amalgamation is not version 3.44.0 or similar'

cpp = SOURCE.read_text(errors='ignore')
# Remove comments so comments alone cannot satisfy the required SQL/C API checks.
cpp_no_comments = re.sub(r'/\*.*?\*/', '', cpp, flags=re.S)
cpp_no_comments = re.sub(r'//[^\n]*', '', cpp_no_comments)
assert re.search(r'\bsqlite3_open(?:_v2)?\s*\(', cpp_no_comments), 'Program does not open SQLite through the C API'
assert re.search(r'\bsqlite3_(?:prepare(?:_v2|_v3)?|exec)\s*\(', cpp_no_comments), 'Program does not execute SQL through the SQLite C API'
assert re.search(r'\bWITH\s+RECURSIVE\b', cpp_no_comments, re.I), 'Program source has no recursive CTE'
assert re.search(r'\b(?:RANK|DENSE_RANK|ROW_NUMBER)\s*\(', cpp_no_comments, re.I), 'Program source has no ranking window function'
assert re.search(r'\bOVER\s*\(', cpp_no_comments, re.I), 'Program source has no window OVER clause'
assert re.search(r'\bJOIN\b', cpp_no_comments, re.I), 'Program analytical SQL has no join'

# Build a fresh executable from the submitted C++ and submitted amalgamation.
subprocess.run([
    'g++', '-std=c++17', str(SOURCE), str(SQLITE_C),
    '-I' + str(SQLITE_C.parent), '-lpthread', '-ldl',
    '-o', '/tmp/verified_report_generator'
], cwd=HOME, check=True, timeout=120, stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)


def write_csv(path, rows):
    path.write_text(''.join(','.join('' if value is None else str(value) for value in row) + '\n' for row in rows))


def remove_outputs():
    for path in (DB, REPORT, Path(str(DB) + '-wal'), Path(str(DB) + '-shm'), Path(str(DB) + '-journal')):
        try:
            path.unlink()
        except FileNotFoundError:
            pass

# Exercise the freshly built artifact on an unpredictable fixture, so the fixed
# five report lines cannot pass. Totals are distinct within each department.
tag = secrets.token_hex(5)
offset = secrets.randbelow(71) + 17
departments = [(10, 'Zeta' + tag), (20, 'Alpha' + tag), (30, 'Mu' + tag)]
employees = [
    (101, 'RootZ' + tag, 10, None),
    (102, 'MidZ' + tag, 10, 101),
    (103, 'LeafZ' + tag, 10, 102),
    (201, 'RootA' + tag, 20, None),
    (202, 'LeafA' + tag, 20, 201),
    (203, 'LeafB' + tag, 20, 201),
    (301, 'RootM' + tag, 30, None),
]
sales = [
    (901, 102, 40 + offset), (902, 102, 60),
    (903, 103, 400 + offset),
    (904, 201, 500 + offset),
    (905, 202, 300 + offset),
    (906, 203, 30), (907, 203, 70 + offset),
]
write_csv(DATA / 'departments.csv', departments)
write_csv(DATA / 'employees.csv', employees)
write_csv(DATA / 'sales.csv', sales)
remove_outputs()
subprocess.run(['/tmp/verified_report_generator'], cwd=HOME, check=True, timeout=30,
               stdout=subprocess.PIPE, stderr=subprocess.PIPE, text=True)

expected_dynamic = [
    f'RootA{tag}|Alpha{tag}|RootA{tag}|{500 + offset}|1',
    f'LeafA{tag}|Alpha{tag}|RootA{tag}|{300 + offset}|2',
    f'LeafB{tag}|Alpha{tag}|RootA{tag}|{100 + offset}|3',
    f'LeafZ{tag}|Zeta{tag}|RootZ{tag}|{400 + offset}|1',
    f'MidZ{tag}|Zeta{tag}|RootZ{tag}|{100 + offset}|2',
]
assert normalized_report(REPORT) == expected_dynamic, 'Freshly compiled program failed the unpredictable analytical fixture'
assert DB.is_file(), 'Freshly compiled program did not create company.db'
with sqlite3.connect(DB) as conn:
    assert_schema_and_indexes(conn)
    assert conn.execute('SELECT id,name FROM departments ORDER BY id').fetchall() == departments
    assert conn.execute('SELECT id,name,department_id,manager_id FROM employees ORDER BY id').fetchall() == employees
    assert conn.execute('SELECT id,employee_id,amount FROM sales ORDER BY id').fetchall() == sales
PY_EOF

if python3 /tmp/test_final_state.py 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
