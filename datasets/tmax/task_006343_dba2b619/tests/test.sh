#!/bin/bash
set -e
mkdir -p /logs/verifier

if python3 - <<'PY'
import ast
import json
import os
import re
import shutil
import sqlite3
import stat
import subprocess
from collections import defaultdict
from pathlib import Path

SCRIPT = Path('/home/user/etl_summary.py')
TTL = Path('/home/user/org_graph.ttl')
DB = Path('/home/user/sales.db')
RESULT = Path('/home/user/result.json')


def remove_path(path):
    if path.is_symlink() or path.is_file():
        path.unlink()
    elif path.exists():
        shutil.rmtree(path)


def validate_script():
    assert SCRIPT.exists(), f'Script missing: {SCRIPT}'
    assert not SCRIPT.is_symlink(), f'Script must be a regular file, not a symlink: {SCRIPT}'
    assert stat.S_ISREG(SCRIPT.stat().st_mode), f'Script is not a regular file: {SCRIPT}'

    source = SCRIPT.read_text(encoding='utf-8')
    ast.parse(source, filename=str(SCRIPT))
    upper = source.upper()

    assert re.search(r'\bRDFLIB\b', source, re.I), 'Script must use rdflib'
    assert re.search(r'\.query\s*\(', source), 'Script must execute a SPARQL query with rdflib Graph.query()'
    assert re.search(r'manages[^\r\n]{0,20}[+*]', source, re.I), \
        'SPARQL query must use a transitive property path for manages'

    assert re.search(r'AVG\s*\([^)]*AMOUNT[^)]*\)\s*OVER\s*\(', upper, re.S), \
        'SQL must calculate AVG(amount) with a window function'
    assert re.search(r'ROWS\s+BETWEEN\s+2\s+PRECEDING\s+AND\s+CURRENT\s+ROW', upper), \
        'SQL window must cover the current row and two preceding rows'

    tree = ast.parse(source, filename=str(SCRIPT))
    parameterized = False
    for node in ast.walk(tree):
        if not isinstance(node, ast.Call) or not isinstance(node.func, ast.Attribute):
            continue
        name = node.func.attr
        if name in {'execute', 'executemany'} and len(node.args) >= 2:
            parameterized = True
        if name in {'read_sql', 'read_sql_query'} and (
            len(node.args) >= 3 or any(k.arg == 'params' for k in node.keywords)
        ):
            parameterized = True
    assert parameterized, 'Script must execute a parameterized SQL query'


def expected_members(edges):
    graph = defaultdict(list)
    for manager, subordinate in edges:
        graph[manager].append(subordinate)
    members = {'Alice'}
    queue = ['Alice']
    while queue:
        current = queue.pop(0)
        for subordinate in graph[current]:
            if subordinate not in members:
                members.add(subordinate)
                queue.append(subordinate)
    return sorted(members)


def expected_total(rows, members):
    by_employee = defaultdict(list)
    for ident, employee, sale_date, amount in rows:
        by_employee[employee].append((sale_date, ident, float(amount)))

    total = 0.0
    for employee in members:
        transactions = sorted(by_employee[employee], key=lambda row: (row[0], row[1]))
        if transactions:
            latest_window = transactions[-3:]
            total += sum(row[2] for row in latest_window) / len(latest_window)
    return round(total, 2)


def install_fixture(edges, rows):
    remove_path(TTL)
    remove_path(DB)
    remove_path(RESULT)

    ttl = '@prefix ex: <http://example.org/> .\n\n'
    ttl += ''.join(f'ex:{manager} ex:manages ex:{subordinate} .\n' for manager, subordinate in edges)
    TTL.write_text(ttl, encoding='utf-8')

    conn = sqlite3.connect(DB)
    try:
        conn.execute('''CREATE TABLE transactions (
            id INTEGER PRIMARY KEY,
            employee_name TEXT,
            sale_date DATE,
            amount REAL
        )''')
        conn.executemany('INSERT INTO transactions VALUES (?, ?, ?, ?)', rows)
        conn.commit()
    finally:
        conn.close()


def run_and_check(edges, rows):
    install_fixture(edges, rows)
    completed = subprocess.run(
        ['python3', str(SCRIPT)],
        cwd='/home/user',
        text=True,
        stdout=subprocess.PIPE,
        stderr=subprocess.PIPE,
        timeout=30,
    )
    assert completed.returncode == 0, (
        f'etl_summary.py failed with exit code {completed.returncode}\n'
        f'stdout:\n{completed.stdout}\nstderr:\n{completed.stderr}'
    )

    # Preserve the original verifier's output existence and JSON validity checks.
    assert RESULT.exists(), f'Output file missing: {RESULT}'
    try:
        with RESULT.open('r', encoding='utf-8') as handle:
            data = json.load(handle)
    except json.JSONDecodeError as exc:
        raise AssertionError(f'File is not valid JSON: {RESULT}: {exc}')

    assert 'manager' in data, "Missing 'manager' key in JSON"
    assert 'subgraph_members' in data, "Missing 'subgraph_members' key in JSON"
    assert 'total_latest_rolling_avg' in data, "Missing 'total_latest_rolling_avg' key in JSON"

    members = expected_members(edges)
    total = expected_total(rows, members)

    assert data['manager'] == 'Alice', f"Expected manager 'Alice', got {data.get('manager')}"
    actual_members = data.get('subgraph_members', [])
    assert isinstance(actual_members, list), 'subgraph_members must be a list'
    assert actual_members == members, f'Expected subgraph members {members}, got {actual_members}'
    actual_total = data.get('total_latest_rolling_avg')
    assert isinstance(actual_total, (int, float)) and not isinstance(actual_total, bool), \
        'total_latest_rolling_avg must be a number'
    assert round(actual_total, 2) == total, \
        f'Expected total_latest_rolling_avg {total}, got {actual_total}'


validate_script()

fixtures = [
    (
        [('Alice', 'Bob'), ('Alice', 'Charlie'), ('Bob', 'David'),
         ('David', 'Frank'), ('Eve', 'Grace')],
        [(1, 'Alice', '2023-10-01', 100.0), (2, 'Alice', '2023-10-02', 150.0),
         (3, 'Alice', '2023-10-03', 200.0), (4, 'Bob', '2023-10-01', 50.0),
         (5, 'Bob', '2023-10-02', 70.0), (6, 'Charlie', '2023-10-01', 300.0),
         (7, 'Charlie', '2023-10-03', 300.0), (8, 'Charlie', '2023-10-05', 300.0),
         (9, 'David', '2023-10-01', 10.0), (10, 'David', '2023-10-02', 20.0),
         (11, 'David', '2023-10-03', 30.0), (12, 'David', '2023-10-04', 40.0),
         (13, 'Frank', '2023-10-01', 100.0), (14, 'Eve', '2023-10-01', 999.0)]
    ),
    (
        [('Alice', 'Mina'), ('Mina', 'Noah'), ('Noah', 'Omar'),
         ('Alice', 'Pia'), ('Zed', 'Iris')],
        [(1, 'Alice', '2024-01-01', 10.0), (2, 'Alice', '2024-01-04', 20.0),
         (3, 'Alice', '2024-01-09', 40.0), (4, 'Alice', '2024-02-01', 80.0),
         (5, 'Mina', '2024-03-01', 5.0), (6, 'Mina', '2024-03-08', 15.0),
         (7, 'Noah', '2024-01-02', 30.0), (8, 'Omar', '2024-01-01', 6.0),
         (9, 'Omar', '2024-01-02', 12.0), (10, 'Omar', '2024-01-10', 18.0),
         (11, 'Pia', '2024-04-01', 100.0), (12, 'Pia', '2024-04-02', 130.0),
         (13, 'Pia', '2024-04-03', 160.0), (14, 'Pia', '2024-04-04', 190.0),
         (15, 'Zed', '2024-01-01', 5000.0), (16, 'Iris', '2024-01-02', 7000.0)]
    ),
    (
        [('Alice', 'Quinn'), ('Quinn', 'Ruth'), ('Ruth', 'Sam'),
         ('Alice', 'Tia'), ('Una', 'Victor')],
        [(1, 'Alice', '2025-05-01', 7.0), (2, 'Alice', '2025-06-20', 14.0),
         (3, 'Quinn', '2025-01-01', 9.0), (4, 'Quinn', '2025-01-02', 18.0),
         (5, 'Quinn', '2025-02-01', 27.0), (6, 'Quinn', '2025-03-01', 36.0),
         (7, 'Ruth', '2025-07-01', 40.0), (8, 'Sam', '2025-01-01', 3.0),
         (9, 'Sam', '2025-04-01', 6.0), (10, 'Sam', '2025-09-01', 9.0),
         (11, 'Tia', '2025-08-01', 100.0), (12, 'Tia', '2025-08-03', 50.0),
         (13, 'Una', '2025-01-01', 900.0), (14, 'Victor', '2025-01-01', 800.0)]
    ),
]

for edges, rows in fixtures:
    run_and_check(edges, rows)
PY
then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
