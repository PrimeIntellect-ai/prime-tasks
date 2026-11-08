#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import json
import os
import secrets
import shutil
import sqlite3
import subprocess
from pathlib import Path

import pytest

HOME = Path('/home/user')
DB_PATH = HOME / 'company.db'
SQL_QUERY_PATH = HOME / 'fixed_query.sql'
RELATIONAL_CSV_PATH = HOME / 'relational_export.csv'
DOCUMENT_JSON_PATH = HOME / 'document_export.json'
GRAPH_NODES_PATH = HOME / 'graph_nodes.csv'
GRAPH_EDGES_PATH = HOME / 'graph_edges.csv'

DEPARTMENTS = [(1, 'Engineering'), (2, 'Marketing')]
EMPLOYEES = [(101, 'Alice', 1), (102, 'Bob', 1), (103, 'Charlie', 2)]
PROJECTS = [(1001, 'Migration'), (1002, 'Analytics'), (1003, 'Campaign')]
ASSIGNMENTS = [(101, 1001), (101, 1002), (102, 1001), (103, 1003)]


def assert_regular_file(path):
    assert path.exists(), f'The file {path} does not exist.'
    assert path.is_file() and not path.is_symlink(), f'{path} must be a regular file.'


def assert_database_contents():
    assert_regular_file(DB_PATH)
    with sqlite3.connect(DB_PATH) as conn:
        assert conn.execute('SELECT id, name FROM departments ORDER BY id').fetchall() == DEPARTMENTS
        assert conn.execute('SELECT id, name, dept_id FROM employees ORDER BY id').fetchall() == EMPLOYEES
        assert conn.execute('SELECT id, name FROM projects ORDER BY id').fetchall() == PROJECTS
        assert conn.execute('SELECT emp_id, proj_id FROM employee_projects ORDER BY emp_id, proj_id').fetchall() == ASSIGNMENTS


def expected_relational(departments, employees, projects, assignments):
    dept = dict(departments)
    emp = {row[0]: row for row in employees}
    proj = dict(projects)
    rows = [(emp[eid][1], dept[emp[eid][2]], proj[pid]) for eid, pid in assignments]
    return sorted(rows, key=lambda row: (row[0], row[2]))


def expected_document(departments, employees, projects, assignments):
    proj = dict(projects)
    emp_dept = {eid: did for eid, _, did in employees}
    assigned = {eid: [] for eid, _, _ in employees}
    for eid, pid in assignments:
        assigned[eid].append({'project_id': pid, 'project_name': proj[pid]})
    result = []
    for did, dname in sorted(departments):
        emps = []
        for eid, ename, employee_did in sorted(employees):
            if employee_did == did:
                emps.append({
                    'employee_id': eid,
                    'employee_name': ename,
                    'projects': sorted(assigned[eid], key=lambda item: item['project_id'])
                })
        result.append({'department_id': did, 'department_name': dname, 'employees': emps})
    return result


def expected_graph(departments, employees, projects, assignments):
    nodes = [(f'dept_{did}', 'Department', name) for did, name in departments]
    nodes += [(f'emp_{eid}', 'Employee', name) for eid, name, _ in employees]
    nodes += [(f'proj_{pid}', 'Project', name) for pid, name in projects]
    nodes.sort(key=lambda row: (row[0], row[1]))

    edges = [(f'emp_{eid}', f'dept_{did}', 'WORKS_IN') for eid, _, did in employees]
    edges += [(f'emp_{eid}', f'proj_{pid}', 'ASSIGNED_TO') for eid, pid in assignments]
    edges.sort(key=lambda row: (row[0], row[1]))
    return nodes, edges


def read_csv(path, header):
    assert_regular_file(path)
    with path.open(newline='', encoding='utf-8') as handle:
        reader = csv.reader(handle)
        assert next(reader, None) == header, f'Incorrect headers in {path}'
        return [tuple(row) for row in reader]


def read_json(path):
    assert_regular_file(path)
    try:
        with path.open(encoding='utf-8') as handle:
            return json.load(handle)
    except json.JSONDecodeError:
        pytest.fail(f'File {path} does not contain valid JSON.')


def test_database_was_not_emptied_or_modified():
    assert_database_contents()


def test_fixed_query_exists_and_executes_correctly():
    assert_regular_file(SQL_QUERY_PATH)
    sql = SQL_QUERY_PATH.read_text(encoding='utf-8').strip()
    assert sql, f'{SQL_QUERY_PATH} is empty.'
    assert sql.lstrip().lower().startswith(('select', 'with')), 'The corrected query must be a SELECT statement.'

    token = secrets.token_hex(6)
    did = 800000 + secrets.randbelow(10000)
    eid1, eid2, eid3 = did + 10000, did + 10001, did + 10002
    pid1, pid2, pid3 = did + 20000, did + 20001, did + 20002
    extra_departments = [(did, f'Department_{token}')]
    extra_employees = [
        (eid1, f'Employee_A_{token}', did),
        (eid2, f'Employee_B_{token}', did),
        (eid3, f'Unassigned_Employee_{token}', did),
    ]
    extra_projects = [
        (pid1, f'Project_A_{token}'),
        (pid2, f'Project_B_{token}'),
        (pid3, f'Unassigned_Project_{token}'),
    ]
    extra_assignments = [(eid1, pid1), (eid1, pid2), (eid2, pid2)]

    test_db = Path('/tmp/query_test.db')
    shutil.copy2(DB_PATH, test_db)
    with sqlite3.connect(test_db) as conn:
        conn.executemany('INSERT INTO departments VALUES (?, ?)', extra_departments)
        conn.executemany('INSERT INTO employees VALUES (?, ?, ?)', extra_employees)
        conn.executemany('INSERT INTO projects VALUES (?, ?)', extra_projects)
        conn.executemany('INSERT INTO employee_projects VALUES (?, ?)', extra_assignments)

    uri = f'file:{test_db}?mode=ro'
    with sqlite3.connect(uri, uri=True) as conn:
        cursor = conn.execute(sql)
        assert [item[0] for item in cursor.description] == [
            'employee_name', 'department_name', 'project_name'
        ], 'The corrected SELECT must return the requested column names.'
        actual = cursor.fetchall()

    expected = expected_relational(
        DEPARTMENTS + extra_departments,
        EMPLOYEES + extra_employees,
        PROJECTS + extra_projects,
        ASSIGNMENTS + extra_assignments,
    )
    assert actual == expected, 'The corrected SELECT does not properly join assignments, employees, departments, and projects.'


def test_relational_export():
    actual = read_csv(RELATIONAL_CSV_PATH, ['employee_name', 'department_name', 'project_name'])
    assert actual == expected_relational(DEPARTMENTS, EMPLOYEES, PROJECTS, ASSIGNMENTS), \
        f'Data in {RELATIONAL_CSV_PATH} does not match expected output or is not correctly sorted.'


def test_document_export():
    actual = read_json(DOCUMENT_JSON_PATH)
    assert actual == expected_document(DEPARTMENTS, EMPLOYEES, PROJECTS, ASSIGNMENTS), \
        f'JSON structure in {DOCUMENT_JSON_PATH} does not match the expected output.'


def test_graph_export_and_on_disk_order():
    expected_nodes, expected_edges = expected_graph(DEPARTMENTS, EMPLOYEES, PROJECTS, ASSIGNMENTS)
    actual_nodes = read_csv(GRAPH_NODES_PATH, ['node_id', 'label', 'name'])
    actual_edges = read_csv(GRAPH_EDGES_PATH, ['source', 'target', 'relationship'])
    assert actual_nodes == expected_nodes, f'Nodes in {GRAPH_NODES_PATH} are incorrect or not sorted on disk.'
    assert actual_edges == expected_edges, f'Edges in {GRAPH_EDGES_PATH} are incorrect or not sorted on disk.'


def find_generation_scripts():
    excluded = {
        SQL_QUERY_PATH, RELATIONAL_CSV_PATH, DOCUMENT_JSON_PATH,
        GRAPH_NODES_PATH, GRAPH_EDGES_PATH, DB_PATH
    }
    scripts = []
    for path in HOME.rglob('*'):
        if not path.is_file() or path.is_symlink() or path in excluded:
            continue
        relative_parts = path.relative_to(HOME).parts
        if any(part.startswith('.') or part in {'__pycache__', 'venv', '.venv', 'node_modules'} for part in relative_parts[:-1]):
            continue
        if path.suffix.lower() in {'.py', '.sh'}:
            scripts.append(path)
            continue
        try:
            first_line = path.open('rb').readline(256).decode('utf-8', errors='ignore').lower()
        except OSError:
            continue
        if first_line.startswith('#!') and any(word in first_line for word in ('python', '/bash', '/sh')):
            scripts.append(path)
    return sorted(set(scripts))


def script_command(path):
    if path.suffix.lower() == '.py':
        return ['python3', str(path)]
    if path.suffix.lower() == '.sh':
        return ['bash', str(path)]
    first_line = path.open('rb').readline(256).decode('utf-8', errors='ignore').lower()
    if 'python' in first_line:
        return ['python3', str(path)]
    if '/bash' in first_line:
        return ['bash', str(path)]
    return ['sh', str(path)]


def test_generation_scripts_run_and_regenerate_exports_from_database():
    scripts = find_generation_scripts()
    assert scripts, 'No generation script was provided under /home/user.'

    token = secrets.token_hex(6)
    did = 900000 + secrets.randbelow(10000)
    eid1, eid2, eid3 = did + 10000, did + 10001, did + 10002
    pid1, pid2, pid3 = did + 20000, did + 20001, did + 20002
    extra_departments = [(did, f'Generated_Department_{token}')]
    extra_employees = [
        (eid1, f'Generated_Employee_A_{token}', did),
        (eid2, f'Generated_Employee_B_{token}', did),
        (eid3, f'Generated_Unassigned_{token}', did),
    ]
    extra_projects = [
        (pid1, f'Generated_Project_A_{token}'),
        (pid2, f'Generated_Project_B_{token}'),
        (pid3, f'Generated_Unassigned_Project_{token}'),
    ]
    extra_assignments = [(eid1, pid1), (eid1, pid2), (eid2, pid2)]

    backup = Path('/tmp/company_original.db')
    shutil.copy2(DB_PATH, backup)
    try:
        with sqlite3.connect(DB_PATH) as conn:
            conn.executemany('INSERT INTO departments VALUES (?, ?)', extra_departments)
            conn.executemany('INSERT INTO employees VALUES (?, ?, ?)', extra_employees)
            conn.executemany('INSERT INTO projects VALUES (?, ?)', extra_projects)
            conn.executemany('INSERT INTO employee_projects VALUES (?, ?)', extra_assignments)

        for output in (DOCUMENT_JSON_PATH, GRAPH_NODES_PATH, GRAPH_EDGES_PATH):
            if output.exists() or output.is_symlink():
                output.unlink()

        for script in scripts:
            result = subprocess.run(
                script_command(script), cwd=HOME, text=True,
                stdout=subprocess.PIPE, stderr=subprocess.STDOUT, timeout=30
            )
            assert result.returncode == 0, f'Generation script {script} failed:\n{result.stdout}'

        departments = DEPARTMENTS + extra_departments
        employees = EMPLOYEES + extra_employees
        projects = PROJECTS + extra_projects
        assignments = ASSIGNMENTS + extra_assignments

        assert read_json(DOCUMENT_JSON_PATH) == expected_document(departments, employees, projects, assignments), \
            'The generation script did not regenerate the document export from the database.'
        expected_nodes, expected_edges = expected_graph(departments, employees, projects, assignments)
        assert read_csv(GRAPH_NODES_PATH, ['node_id', 'label', 'name']) == expected_nodes, \
            'The generation script did not regenerate correctly sorted graph nodes.'
        assert read_csv(GRAPH_EDGES_PATH, ['source', 'target', 'relationship']) == expected_edges, \
            'The generation script did not regenerate correctly sorted graph edges.'
    finally:
        for suffix in ('-journal', '-wal', '-shm'):
            sidecar = Path(str(DB_PATH) + suffix)
            if sidecar.exists():
                sidecar.unlink()
        shutil.copy2(backup, DB_PATH)

    assert_database_contents()
TEST_EOF

if python3 -m pytest /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
