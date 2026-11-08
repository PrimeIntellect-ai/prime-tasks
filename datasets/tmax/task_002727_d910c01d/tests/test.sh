#!/bin/bash
set -e
mkdir -p /logs/verifier

cat <<'TEST_EOF' > /tmp/test_final_state.py
import csv
import os
import re
import secrets
import stat
import subprocess

SCRIPT = '/home/user/generate_report.sh'
EMPLOYEES = '/home/user/employees.csv'
DEPARTMENTS = '/home/user/departments.csv'
DATABASE = '/home/user/org.db'
OUTPUT = '/home/user/org_chart.csv'
HEADER = ['emp_id', 'name', 'dept_name', 'manager_name', 'management_chain']


def write_csv(path, rows):
    with open(path, 'w', newline='') as f:
        csv.writer(f).writerows(rows)


def run_script():
    for path in (DATABASE, OUTPUT):
        if os.path.exists(path):
            os.remove(path)
    result = subprocess.run(
        [SCRIPT], cwd='/home/user', text=True,
        stdout=subprocess.PIPE, stderr=subprocess.PIPE, timeout=20
    )
    assert result.returncode == 0, (
        f'{SCRIPT} failed with exit code {result.returncode}. '
        f'stdout={result.stdout!r}, stderr={result.stderr!r}'
    )
    assert os.path.isfile(OUTPUT), f'File {OUTPUT} is missing. Did the script generate it?'


def assert_output(expected_rows):
    with open(OUTPUT, 'r', newline='') as f:
        reader = csv.reader(f)
        try:
            header = next(reader)
        except StopIteration:
            raise AssertionError(f'{OUTPUT} is empty.')
        actual_rows = list(reader)

    assert header == HEADER, f'Header in {OUTPUT} is incorrect. Expected {HEADER}, got {header}.'
    assert len(actual_rows) == len(expected_rows), (
        f'Expected {len(expected_rows)} rows, but got {len(actual_rows)}.'
    )
    actual_sorted = sorted(actual_rows, key=lambda row: int(row[0]) if row and row[0].isdigit() else 0)
    expected_sorted = sorted(expected_rows, key=lambda row: int(row[0]))
    for actual, expected in zip(actual_sorted, expected_sorted):
        assert actual == expected, f'Row mismatch: Expected {expected}, got {actual}.'


def derive_expected(employee_rows, department_rows):
    departments = {row[0]: row[1] for row in department_rows}
    employees = {row[0]: row for row in employee_rows}
    expected = []
    for emp_id, name, manager_id, dept_id in employee_rows:
        manager_name = employees[manager_id][1] if manager_id else ''
        chain = []
        current = emp_id
        seen = set()
        while current:
            assert current not in seen, 'Test fixture unexpectedly contains a management cycle.'
            seen.add(current)
            employee = employees[current]
            chain.append(employee[1])
            current = employee[2]
        expected.append([emp_id, name, departments[dept_id], manager_name, '->'.join(reversed(chain))])
    return expected


def test_script_and_generated_reports():
    assert os.path.exists(SCRIPT), f'{SCRIPT} is missing.'
    mode = os.stat(SCRIPT).st_mode
    assert stat.S_ISREG(mode), f'{SCRIPT} is not a regular file.'
    assert os.access(SCRIPT, os.X_OK), f'{SCRIPT} is not executable.'

    with open(SCRIPT, 'r', encoding='utf-8') as f:
        script_text = f.read()
    first_line = script_text.splitlines()[0] if script_text.splitlines() else ''
    assert first_line.startswith('#!') and 'bash' in first_line, f'{SCRIPT} is not a bash script.'

    # Ignore shell and SQL comments so merely mentioning the required syntax in a comment does not pass.
    inspected = re.sub(r'/\*.*?\*/', ' ', script_text, flags=re.DOTALL)
    inspected = re.sub(r'--[^\n]*', ' ', inspected)
    inspected = '\n'.join(
        line if index == 0 else re.sub(r'#[^\n]*', ' ', line)
        for index, line in enumerate(inspected.splitlines())
    )
    assert re.search(r'\bWITH\s+RECURSIVE\b', inspected, flags=re.IGNORECASE), (
        f'{SCRIPT} does not contain a WITH RECURSIVE query.'
    )

    # Preserve the original verifier's exact assertions, but regenerate the file by executing the script.
    canonical_employees = [
        ['emp_id', 'name', 'manager_id', 'dept_id'],
        ['1', 'Alice', '', '10'],
        ['2', 'Bob', '1', '10'],
        ['3', 'Charlie', '1', '20'],
        ['4', 'Dave', '2', '10'],
        ['5', 'Eve', '3', '20'],
    ]
    canonical_departments = [
        ['dept_id', 'dept_name'],
        ['10', 'Engineering'],
        ['20', 'Sales'],
    ]
    expected_rows = [
        ['1', 'Alice', 'Engineering', '', 'Alice'],
        ['2', 'Bob', 'Engineering', 'Alice', 'Alice->Bob'],
        ['3', 'Charlie', 'Sales', 'Alice', 'Alice->Charlie'],
        ['4', 'Dave', 'Engineering', 'Bob', 'Alice->Bob->Dave'],
        ['5', 'Eve', 'Sales', 'Charlie', 'Alice->Charlie->Eve'],
    ]
    write_csv(EMPLOYEES, canonical_employees)
    write_csv(DEPARTMENTS, canonical_departments)
    run_script()
    assert_output(expected_rows)

    # Exercise joins and recursion on fresh, unpredictable data to reject a script that writes fixed rows.
    token = secrets.token_hex(4)
    dynamic_employees = [
        ['101', f'Root_{token}', '', '70'],
        ['205', f'Lead_{token}', '101', '80'],
        ['309', f'Senior_{token}', '205', '70'],
        ['412', f'Junior_{token}', '309', '90'],
        ['518', f'Peer_{token}', '101', '90'],
    ]
    dynamic_departments = [
        ['70', f'Platform_{token}'],
        ['80', f'Research_{token}'],
        ['90', f'Operations_{token}'],
    ]
    write_csv(EMPLOYEES, [['emp_id', 'name', 'manager_id', 'dept_id']] + dynamic_employees)
    write_csv(DEPARTMENTS, [['dept_id', 'dept_name']] + dynamic_departments)
    run_script()
    assert_output(derive_expected(dynamic_employees, dynamic_departments))
TEST_EOF

if python3 -m pytest --noconftest -c /dev/null -p no:cacheprovider /tmp/test_final_state.py -x --tb=short 2>&1; then
    echo "1" > /logs/verifier/reward.txt
else
    echo "0" > /logs/verifier/reward.txt
fi
