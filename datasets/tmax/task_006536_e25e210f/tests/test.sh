#!/bin/bash
set -e
mkdir -p /logs/verifier

cat << 'TEST_EOF' > /tmp/test_final_state.py
import os
import re
import secrets
import shutil
import sqlite3
import subprocess
import tempfile

SOURCE = '/home/user/get_org.c'
EXECUTABLE = '/home/user/get_org'
DATABASE = '/home/user/company.db'
REPORT = '/home/user/org_report.txt'


def test_c_source_exists():
    """Verify that the C source file exists."""
    assert os.path.isfile(SOURCE), "The C source file /home/user/get_org.c does not exist."


def test_executable_exists():
    """Verify that the compiled executable exists and is executable."""
    assert os.path.isfile(EXECUTABLE), f"The executable {EXECUTABLE} does not exist."
    assert os.access(EXECUTABLE, os.X_OK), f"The file {EXECUTABLE} is not executable."


def test_report_content():
    """Verify that the initially requested report exists and is correct."""
    assert os.path.isfile(REPORT), f"The report file {REPORT} does not exist."
    expected_lines = [
        "0 - 2: Bob",
        "1 - 4: David",
        "1 - 5: Eve",
        "2 - 6: Frank",
        "2 - 7: Grace",
        "3 - 9: Ivan"
    ]
    with open(REPORT, 'r') as f:
        content = f.read().strip()
    actual_lines = [line.strip() for line in content.splitlines() if line.strip()]
    assert actual_lines == expected_lines, (
        f"The content of {REPORT} is incorrect.\n"
        f"Expected:\n{chr(10).join(expected_lines)}\n"
        f"Got:\n{chr(10).join(actual_lines)}"
    )


def test_source_uses_required_sqlite_recursive_cte():
    with open(SOURCE, 'r', encoding='utf-8', errors='strict') as f:
        source = f.read()

    # Remove comments before looking for the required implementation elements.
    checked = re.sub(r'/\*.*?\*/', ' ', source, flags=re.S)
    checked = re.sub(r'//[^\n]*', ' ', checked)
    lower = checked.lower()

    assert re.search(r'\bsqlite3_open(?:_v2)?\s*\(', lower), "Source must open the SQLite database with the SQLite3 C API."
    assert re.search(r'\bsqlite3_prepare(?:_v2|_v3)?\s*\(', lower), "Source must prepare its SQL statement."
    assert re.search(r'\bsqlite3_bind_[a-z0-9_]+\s*\(', lower), "The root employee must be bound as a SQL parameter."
    assert re.search(r'\bsqlite3_step\s*\(', lower), "Source must execute the prepared SQLite statement."
    assert re.search(r'with\s+recursive', lower), "The query must use a recursive CTE."
    assert ('?' in checked or re.search(r'[:@$][A-Za-z_][A-Za-z0-9_]*', checked)), "The prepared query must contain a parameter placeholder."
    assert re.search(r'order\s+by[\s\S]{0,500}?depth[\s\S]{0,300}?emp_id', lower), "The query must order by depth and then emp_id."


def _create_test_database(path, token, base):
    conn = sqlite3.connect(path)
    try:
        conn.executescript('''
            CREATE TABLE employees (
                emp_id INTEGER PRIMARY KEY,
                emp_name TEXT,
                manager_id INTEGER
            );
            INSERT INTO employees VALUES
                (1, 'Alice', NULL),
                (2, 'Bob', 1),
                (3, 'Charlie', 1),
                (4, 'David', 2),
                (5, 'Eve', 2),
                (6, 'Frank', 4),
                (7, 'Grace', 5),
                (8, 'Heidi', 3),
                (9, 'Ivan', 6);
        ''')
        rows = [
            (base,     f'Root_{token}', None),
            (base + 1, f'ChildB_{token}', base),
            (base + 2, f'ChildA_{token}', base),
            (base + 3, f'Grandchild_{token}', base + 2),
            (base + 4, f'UnderCharlie_{token}', 3),
            (base + 5, f'DeepCharlie_{token}', base + 4),
            (base + 6, f'UnderBob_{token}', 2),
            (base + 7, f'DeepBob_{token}', base + 6),
        ]
        conn.executemany('INSERT INTO employees(emp_id, emp_name, manager_id) VALUES (?, ?, ?)', rows)
        conn.commit()
    finally:
        conn.close()


def _expected_lines(root_id):
    conn = sqlite3.connect(DATABASE)
    try:
        rows = conn.execute('SELECT emp_id, emp_name, manager_id FROM employees').fetchall()
    finally:
        conn.close()

    names = {emp_id: name for emp_id, name, _ in rows}
    children = {}
    for emp_id, _, manager_id in rows:
        children.setdefault(manager_id, []).append(emp_id)

    if root_id not in names:
        return []

    result = []
    queue = [(root_id, 0)]
    seen = set()
    while queue:
        emp_id, depth = queue.pop(0)
        if emp_id in seen:
            continue
        seen.add(emp_id)
        result.append((depth, emp_id, names[emp_id]))
        for child_id in children.get(emp_id, []):
            queue.append((child_id, depth + 1))

    result.sort(key=lambda item: (item[0], item[1]))
    return [f'{depth} - {emp_id}: {name}' for depth, emp_id, name in result]


def _run_and_check(program, root_id):
    if os.path.exists(REPORT):
        os.remove(REPORT)
    proc = subprocess.run(
        [program, str(root_id)],
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        text=True,
        timeout=10,
    )
    assert proc.returncode == 0, (
        f'{program} failed for root {root_id} with exit code {proc.returncode}.\n'
        f'stdout: {proc.stdout}\nstderr: {proc.stderr}'
    )
    assert os.path.isfile(REPORT), f'{program} did not create {REPORT} for root {root_id}.'
    with open(REPORT, 'r', encoding='utf-8') as f:
        actual = f.read().splitlines()
    expected = _expected_lines(root_id)
    assert actual == expected, (
        f'Incorrect report from {program} for root {root_id}.\n'
        f'Expected:\n{chr(10).join(expected)}\nGot:\n{chr(10).join(actual)}'
    )


def test_executable_and_source_against_dynamic_database():
    backup_dir = tempfile.mkdtemp(prefix='get_org_backup_')
    compiled = os.path.join(backup_dir, 'get_org_from_source')
    saved_report = None
    if os.path.exists(REPORT):
        with open(REPORT, 'rb') as f:
            saved_report = f.read()

    db_files = [DATABASE, DATABASE + '-wal', DATABASE + '-shm', DATABASE + '-journal']
    for path in db_files:
        if os.path.exists(path):
            shutil.copy2(path, os.path.join(backup_dir, os.path.basename(path)))

    try:
        subprocess.run(
            ['gcc', SOURCE, '-o', compiled, '-lsqlite3'],
            check=True,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=20,
        )

        for path in db_files:
            if os.path.lexists(path):
                os.remove(path)

        token = secrets.token_hex(8)
        base = 100000 + secrets.randbelow(800000)
        _create_test_database(DATABASE, token, base)

        roots = [2, 3, 1, base]
        # Exercise both the submitted executable and a fresh build of the submitted source.
        for program in (EXECUTABLE, compiled):
            for root_id in roots:
                _run_and_check(program, root_id)
    finally:
        for path in db_files:
            if os.path.lexists(path):
                os.remove(path)
        for path in db_files:
            saved = os.path.join(backup_dir, os.path.basename(path))
            if os.path.exists(saved):
                shutil.copy2(saved, path)
        if saved_report is not None:
            with open(REPORT, 'wb') as f:
                f.write(saved_report)
        elif os.path.exists(REPORT):
            os.remove(REPORT)
        shutil.rmtree(backup_dir, ignore_errors=True)
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
