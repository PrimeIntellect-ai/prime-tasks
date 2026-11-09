#!/bin/bash
mkdir -p /logs/verifier

if (
    set -e

    test -d /home/user/manager_report
    test -f /home/user/manager_report/Cargo.toml
    test -f /home/user/manager_report/src/main.rs

    python3 - <<'PY'
import pathlib
import re

src_dir = pathlib.Path('/home/user/manager_report/src')
files = list(src_dir.rglob('*.rs'))
assert files, 'No Rust source files found'
source = '\n'.join(p.read_text(errors='replace') for p in files)
source = re.sub(r'/\*.*?\*/', '', source, flags=re.S)
source = re.sub(r'//[^\n]*', '', source)
assert re.search(r'\b(?:ROW_NUMBER|RANK|DENSE_RANK)\s*\(', source, re.I), \
    'Rust source must use a SQL ranking window function'
assert re.search(r'\bOVER\s*\(', source, re.I), \
    'Rust source must contain an OVER clause for the window function'
PY

    cp /home/user/company.db /tmp/company.db.verifier-backup
    trap 'cp /tmp/company.db.verifier-backup /home/user/company.db' EXIT

    rm -f /home/user/top_managers.json
    cd /home/user/manager_report
    timeout 180 cargo run --quiet

    cat << 'TEST_EOF' > /tmp/test_final_state.py
# test_final_state.py

import os
import json
import pytest

JSON_PATH = "/home/user/top_managers.json"

def test_json_file_exists():
    """Check if the output JSON file exists."""
    assert os.path.isfile(JSON_PATH), f"Output JSON file not found at {JSON_PATH}"

def test_json_contents():
    """Check if the JSON file contains the correct results."""
    with open(JSON_PATH, "r") as f:
        try:
            data = json.load(f)
        except json.JSONDecodeError as e:
            pytest.fail(f"Failed to parse JSON file: {e}")

    assert isinstance(data, list), "JSON output must be a list of objects"
    assert len(data) == 2, f"Expected exactly 2 elements in the output, found {len(data)}"

    # Sort data by dept_name to ensure consistent checking
    data_sorted = sorted(data, key=lambda x: x.get("dept_name", ""))

    expected_engineering = {
        "dept_name": "Engineering",
        "manager_name": "Alice",
        "direct_reports": 2,
        "salary": 120000
    }

    expected_sales = {
        "dept_name": "Sales",
        "manager_name": "Heidi",
        "direct_reports": 1,
        "salary": 90000
    }

    # Verify Engineering
    eng_record = data_sorted[0]
    for key, expected_value in expected_engineering.items():
        assert key in eng_record, f"Missing key '{key}' in Engineering record"
        assert eng_record[key] == expected_value, f"Expected {key}={expected_value} for Engineering, found {eng_record[key]}"

    # Verify Sales
    sales_record = data_sorted[1]
    for key, expected_value in expected_sales.items():
        assert key in sales_record, f"Missing key '{key}' in Sales record"
        assert sales_record[key] == expected_value, f"Expected {key}={expected_value} for Sales, found {sales_record[key]}"
TEST_EOF

    python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short

    python3 - <<'PY'
import json
import secrets
import sqlite3

path = '/home/user/company.db'
con = sqlite3.connect(path)
cur = con.cursor()
cur.execute('DELETE FROM reports_to')
cur.execute('DELETE FROM employees')
cur.execute('DELETE FROM departments')

token = secrets.token_hex(6)
base_dept = 10000 + secrets.randbelow(100000)
base_emp = 1000000 + secrets.randbelow(1000000)

depts = [
    (base_dept, f'Zulu_{token}'),
    (base_dept + 7, f'Alpha_{token}'),
    (base_dept + 19, f'NoReports_{token}'),
    (base_dept + 31, f'Middle_{token}'),
]
cur.executemany('INSERT INTO departments(dept_id, dept_name) VALUES (?, ?)', depts)

employees = []
by_dept = {}
for dpos, (dept_id, dept_name) in enumerate(depts):
    rows = []
    for i in range(10):
        emp_id = base_emp + dpos * 100 + i
        name = f'Employee_{token}_{dpos}_{i}'
        salary = 50000 + secrets.randbelow(20000)
        rows.append([emp_id, name, dept_id, salary])
    by_dept[dept_id] = rows
    employees.extend(rows)

# Zulu: all three candidates tie on report count. Candidates 0 and 2 also
# tie on the highest salary, so the lower emp_id (candidate 0) must win.
zrows = by_dept[depts[0][0]]
high_salary = 130000 + secrets.randbelow(10000)
zrows[0][3] = high_salary
zrows[1][3] = high_salary - 10000
zrows[2][3] = high_salary

# Alpha: report count must take precedence over salary.
arows = by_dept[depts[1][0]]
arows[0][3] = 190000
arows[1][3] = 70000
arows[2][3] = 180000

# Middle has a single qualifying manager; NoReports has none.
mrows = by_dept[depts[3][0]]
mrows[4][3] = 99000

cur.executemany(
    'INSERT INTO employees(emp_id, name, dept_id, salary) VALUES (?, ?, ?, ?)',
    employees,
)

edges = []
for manager in zrows[:3]:
    for reportee in zrows[3:7]:
        edges.append((manager[0], reportee[0]))
for reportee in arows[3:5]:
    edges.append((arows[0][0], reportee[0]))
for reportee in arows[3:7]:
    edges.append((arows[1][0], reportee[0]))
edges.append((arows[2][0], arows[8][0]))
edges.append((mrows[4][0], mrows[7][0]))
cur.executemany('INSERT INTO reports_to(mgr_id, emp_id) VALUES (?, ?)', edges)
con.commit()

# Derive the oracle independently from the database using ordinary Python
# grouping and the specified tie-breaking rules.
departments = dict(cur.execute('SELECT dept_id, dept_name FROM departments'))
counts = dict(cur.execute('SELECT mgr_id, COUNT(*) FROM reports_to GROUP BY mgr_id'))
candidates = {}
for emp_id, name, dept_id, salary in cur.execute(
    'SELECT emp_id, name, dept_id, salary FROM employees'
):
    count = counts.get(emp_id, 0)
    if count > 0:
        candidates.setdefault(dept_id, []).append(
            (count, salary, emp_id, name)
        )

expected = []
for dept_id, rows in candidates.items():
    count, salary, emp_id, name = sorted(
        rows, key=lambda row: (-row[0], -row[1], row[2])
    )[0]
    expected.append({
        'dept_name': departments[dept_id],
        'manager_name': name,
        'direct_reports': count,
        'salary': salary,
    })
expected.sort(key=lambda row: row['dept_name'])
with open('/tmp/dynamic_expected.json', 'w') as f:
    json.dump(expected, f)
con.close()
PY

    rm -f /home/user/top_managers.json
    cd /home/user/manager_report
    timeout 180 cargo run --quiet

    python3 - <<'PY'
import json
import os

output_path = '/home/user/top_managers.json'
assert os.path.isfile(output_path), f'Output JSON file not found at {output_path}'
with open(output_path) as f:
    actual = json.load(f)
with open('/tmp/dynamic_expected.json') as f:
    expected = json.load(f)

assert isinstance(actual, list), 'JSON output must be a list of objects'
assert actual == expected, f'Dynamic database result was incorrect: expected {expected!r}, got {actual!r}'
required = {'dept_name', 'manager_name', 'direct_reports', 'salary'}
for record in actual:
    assert isinstance(record, dict), 'Every array element must be an object'
    assert set(record) == required, f'Each object must contain exactly {sorted(required)}'
assert actual == sorted(actual, key=lambda row: row['dept_name']), \
    'Output must be sorted alphabetically by dept_name'
PY
); then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
